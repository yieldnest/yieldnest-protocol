// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {Initializable} from "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {IBeacon} from "lib/openzeppelin-contracts/contracts/proxy/beacon/IBeacon.sol";
import {ReentrancyGuardUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ISignatureUtils} from "lib/eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";
import {IStrategyManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IDelegationManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategy} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {ITokenStakingNode} from "src/interfaces/ITokenStakingNode.sol";
import {ITokenStakingNodesManager} from "src/interfaces/ITokenStakingNodesManager.sol";
import {IwstETH} from "src/external/lido/IwstETH.sol";
import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";

interface ITokenStakingNodeEvents {
    event DepositToEigenlayer(
        IERC20 indexed asset,
        IStrategy indexed strategy,
        uint256 amount,
        uint256 eigenShares
    );
    event Delegated(address indexed operator, bytes32 approverSalt);
    event Undelegated(bytes32[] withdrawalRoots);
    event QueuedWithdrawals(IStrategy[] _strategies, uint256[] _shares, bytes32[] _fullWithdrawalRoots);
}

interface IYieldNestStrategyManager {
    function wstETH() external view returns (IwstETH);
    function stETH() external view returns (IERC20);
    function woETH() external view returns (IERC4626);
    function oETH() external view returns (IERC20);
}

interface IStrategyManagerExt {
    function yieldNestStrategyManager() external view returns (address);
}

/**
 * @title Token Staking Node
 * @dev Implements staking node functionality for tokens, enabling token staking, delegation, and rewards management.
 * This contract interacts with the Eigenlayer protocol to deposit assets, delegate staking operations, and manage staking rewards.
 */
contract TokenStakingNode is
    ITokenStakingNode,
    Initializable,
    ReentrancyGuardUpgradeable,
    ITokenStakingNodeEvents
{
    using SafeERC20 for IERC20;

    //--------------------------------------------------------------------------------------
    //----------------------------------  ERRORS  ------------------------------------------
    //--------------------------------------------------------------------------------------

    error ZeroAddress();
    error NotTokenStakingNodeOperator();
    error NotStrategyManager();
    error NotTokenStakingNodeDelegator();
    error NotTokenStakingNodesWithdrawer();

    //--------------------------------------------------------------------------------------
    //----------------------------------  VARIABLES  ---------------------------------------
    //--------------------------------------------------------------------------------------

    ITokenStakingNodesManager public override tokenStakingNodesManager;
    uint256 public nodeId;

    mapping(IStrategy => uint256) public queuedShares;
    mapping(IERC20 => uint256) public withdrawn;

    //--------------------------------------------------------------------------------------
    //----------------------------------  INITIALIZATION  ----------------------------------
    //--------------------------------------------------------------------------------------

    constructor() {
        _disableInitializers();
    }

    function initialize(
        Init memory init
    )
        public
        notZeroAddress(address(init.tokenStakingNodesManager))
        initializer
    {
        __ReentrancyGuard_init();
        tokenStakingNodesManager = init.tokenStakingNodesManager;
        nodeId = init.nodeId;
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  EIGENLAYER DEPOSITS  -----------------------------
    //--------------------------------------------------------------------------------------

    /**
     * @notice Deposits multiple assets into their respective strategies on Eigenlayer by retrieving them from tokenStakingNodesManager.
     * @dev Iterates through the provided arrays of assets and amounts, depositing each into its corresponding strategy.
     * @param assets An array of IERC20 tokens to be deposited.
     * @param amounts An array of amounts corresponding to each asset to be deposited.
     */
    function depositAssetsToEigenlayer(
        IERC20[] calldata assets,
        uint256[] calldata amounts,
        IStrategy[] calldata strategies
    ) external nonReentrant onlyYieldNestStrategyManager {
        IStrategyManager strategyManager = tokenStakingNodesManager
            .strategyManager();

        uint256 assetsLength = assets.length;
        for (uint256 i = 0; i < assetsLength; i++) {
            IERC20 asset = assets[i];
            uint256 amount = amounts[i];
            IStrategy strategy = strategies[i];

            asset.forceApprove(address(strategyManager), amount);

            uint256 eigenShares = strategyManager.depositIntoStrategy(
                IStrategy(strategy),
                asset,
                amount
            );
            emit DepositToEigenlayer(asset, strategy, amount, eigenShares);
        }
    }

    //--------------------------------------------------------------------------------------
    //-------------------------------- EIGENLAYER WITHDRAWALS  -----------------------------
    //--------------------------------------------------------------------------------------

    function queueWithdrawals(
        IStrategy _strategy,
        uint256 _shares
    ) external onlyTokenStakingNodesWithdrawer returns (bytes32[] memory _fullWithdrawalRoots) {

        IStrategy[] memory _strategiesArray = new IStrategy[](1);
        _strategiesArray[0] = _strategy;
        uint256[] memory _sharesArray = new uint256[](1);
        _sharesArray[0] = _shares;
        IDelegationManager.QueuedWithdrawalParams[] memory _params = new IDelegationManager.QueuedWithdrawalParams[](1);
        _params[0] = IDelegationManager.QueuedWithdrawalParams({
            strategies: _strategiesArray,
            shares: _sharesArray,
            withdrawer: address(this)
        });

        queuedShares[_strategy] += _shares;

        _fullWithdrawalRoots = tokenStakingNodesManager.delegationManager().queueWithdrawals(_params);

        emit QueuedWithdrawals(_strategiesArray, _sharesArray, _fullWithdrawalRoots);
    }

    // struct Withdrawal {
    //     // The address that originated the Withdrawal
    //     address staker;
    //     // The address that the staker was delegated to at the time that the Withdrawal was created
    //     address delegatedTo;
    //     // The address that can complete the Withdrawal + will receive funds when completing the withdrawal
    //     address withdrawer;
    //     // Nonce used to guarantee that otherwise identical withdrawals have unique hashes
    //     uint256 nonce;
    //     // Block number when the Withdrawal was created
    //     uint32 startBlock;
    //     // Array of strategies that the Withdrawal contains
    //     IStrategy[] strategies;
    //     // Array containing the amount of shares in each Strategy in the `strategies` array
    //     uint256[] shares;
    // }
    function completeQueuedWithdrawals(
        uint256 _nonce,
        uint32 _startBlock,
        uint256 _shares,
        IStrategy _strategy,
        uint256[] memory _middlewareTimesIndexes
    ) public onlyTokenStakingNodesWithdrawer {

        IStrategy[] memory _strategiesArray = new IStrategy[](1);
        _strategiesArray[0] = _strategy;
        uint256[] memory _sharesArray = new uint256[](1);
        _sharesArray[0] = _shares;

        IDelegationManager _delegationManager = tokenStakingNodesManager.delegationManager();

        IDelegationManager.Withdrawal[] memory _withdrawals = new IDelegationManager.Withdrawal[](1);
        _withdrawals[0] = IDelegationManager.Withdrawal({
            staker: address(this),
            delegatedTo: _delegationManager.delegatedTo(address(this)),
            withdrawer: address(this),
            nonce: _nonce,
            startBlock: _startBlock,
            strategies: _strategiesArray,
            shares: _sharesArray
        });

        uint256 _expectedAmountOut = _strategy.sharesToUnderlyingView(_shares);

        IERC20 _token = _strategy.underlyingToken();
        uint256 _balanceBefore = _token.balanceOf(address(this));

        bool[] memory _receiveAsTokens = new bool[](1);
        _receiveAsTokens[0] = true;
        IERC20[][] memory _tokens = new IERC20[][](1);
        _tokens[0] = new IERC20[](1);
        _tokens[0][0] = _token;

        _delegationManager.completeQueuedWithdrawals(
            _withdrawals,
            _tokens,
            _middlewareTimesIndexes,
            _receiveAsTokens
        );

        if (_token.balanceOf(address(this)) - _balanceBefore != _expectedAmountOut) revert("WithdrawalAmountMismatch"); // @todo

        (_expectedAmountOut, _token) = _wrapIfNeeded(_expectedAmountOut, _token);

        queuedShares[_strategy] -= _shares;
        withdrawn[_token] += _expectedAmountOut;

        // emit CompletedQueuedWithdrawals(withdrawals, totalWithdrawalAmount); // @todo
    }

    // function completeQueuedWithdrawals(
    //     IDelegationManager.Withdrawal[] memory _withdrawals,
    //     uint256[] memory _middlewareTimesIndexes
    // ) public onlyTokenStakingNodesWithdrawer {

    //     uint256 _withdrawalsLength = _withdrawals.length;
    //     bool[] memory _receiveAsTokens = new bool[](_withdrawalsLength);
    //     IERC20[][] memory _tokens = new IERC20[][](_withdrawalsLength);

    //     uint256 _totalShares;
    //     IStrategy _allowedStrategy = _withdrawals[0].strategies[0];
    //     IERC20 _allowedToken = _allowedStrategy.underlyingToken();
    //     for (uint256 i = 0; i < _withdrawalsLength; ++i) {
    //         if (_withdrawals[i].strategies[0] != _allowedStrategy) revert("DifferentTokensNotAllowed"); // @todo
    //         if (_withdrawals[i].shares[0] == 0) revert("ZeroShares");// @todo

    //         uint256 _strategiesLength = _withdrawals[i].strategies.length;
    //         if (
    //             _strategiesLength != 1 ||
    //             _withdrawals[i].shares.length != _strategiesLength
    //         ) revert("OnlyOneStrategyPerWithdrawalAllowed"); // @todo

    //         _receiveAsTokens[i] = true;

    //         _tokens[i] = new IERC20[](_strategiesLength);
    //         _tokens[i][0] = _allowedToken;

    //         _totalShares += _withdrawals[i].shares[0];
    //     }

    //     uint256 _expectedAmountOut = _allowedStrategy.sharesToUnderlyingView(_totalShares);
    //     uint256 _balanceBefore = _allowedToken.balanceOf(address(this));

    //     tokenStakingNodesManager.delegationManager().completeQueuedWithdrawals(
    //         _withdrawals,
    //         _tokens,
    //         _middlewareTimesIndexes,
    //         _receiveAsTokens
    //     );

    //     if (_allowedToken.balanceOf(address(this)) - _balanceBefore != _expectedAmountOut) revert("WithdrawalAmountMismatch"); // @todo

    //     (_expectedAmountOut, _allowedToken) = _wrapIfNeeded(_expectedAmountOut, _allowedToken);

    //     queuedShares[_allowedStrategy] -= _totalShares;
    //     withdrawn[_allowedToken] += _expectedAmountOut;

    //     // emit CompletedQueuedWithdrawals(withdrawals, totalWithdrawalAmount); // @todo
    // }
    function _wrapIfNeeded(uint256 _amount, IERC20 _token) internal returns (uint256, IERC20) {
        IYieldNestStrategyManager _strategyManager =
            IYieldNestStrategyManager(IStrategyManagerExt(address(tokenStakingNodesManager)).yieldNestStrategyManager());
        IwstETH _wstETH = _strategyManager.wstETH();
        IERC20 _stETH = _strategyManager.stETH();
        IERC4626 _woETH = _strategyManager.woETH();
        IERC20 _oETH = _strategyManager.oETH();
        if (_token == _stETH) {
            _stETH.forceApprove(address(_wstETH), _amount);
            uint256 _wstETHAmount = _wstETH.wrap(_amount);
            return (_wstETHAmount, IERC20(_wstETH));
        } else if (_token == _oETH) {
            _oETH.forceApprove(address(_woETH), _amount);
            uint256 _woETHShares = _woETH.deposit(_amount, address(this));
            return (_woETHShares, IERC20(_woETH));
        } else {
            return (_amount, _token);
        }
    }

    function deallocateTokens(IERC20 _token, uint256 _amount) external onlyTokenStakingNodesManager {

        withdrawn[_token] -= _amount;
        _token.forceApprove(address(tokenStakingNodesManager), _amount);

        // emit DeallocatedTokens(_amount, _token); // @todo
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  DELEGATION  --------------------------------------
    //--------------------------------------------------------------------------------------

    /**
     * @notice Delegates the staking operation to a specified operator.
     * @param operator The address of the operator to whom the staking operation is being delegated.
     */
    function delegate(
        address operator,
        ISignatureUtils.SignatureWithExpiry memory signature,
        bytes32 approverSalt
    ) public virtual onlyDelegator {
        IDelegationManager delegationManager = tokenStakingNodesManager
            .delegationManager();
        delegationManager.delegateTo(operator, signature, approverSalt);

        emit Delegated(operator, approverSalt);
    }

    /**
     * @notice Undelegates the staking operation.
     */
    function undelegate() public override onlyDelegator {
        IDelegationManager delegationManager = IDelegationManager(
            address(tokenStakingNodesManager.delegationManager())
        );
        bytes32[] memory withdrawalRoots = delegationManager.undelegate(
            address(this)
        );

        emit Undelegated(withdrawalRoots);
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  MODIFIERS  ---------------------------------------
    //--------------------------------------------------------------------------------------

    modifier onlyOperator() {
        if (
            !tokenStakingNodesManager.hasTokenStakingNodeOperatorRole(msg.sender)
        ) {
            revert NotTokenStakingNodeOperator();
        }
        _;
    }

    modifier onlyDelegator() {
        if (!tokenStakingNodesManager.hasTokenStakingNodeDelegatorRole(msg.sender)) {
            revert NotTokenStakingNodeDelegator();
        }
        _;
    }

    modifier onlyYieldNestStrategyManager() {
        if (!tokenStakingNodesManager.hasYieldNestStrategyManagerRole(msg.sender)) {
            revert NotStrategyManager();
        }
        _;
    }

    modifier onlyTokenStakingNodesWithdrawer() {
        if (!tokenStakingNodesManager.isStakingNodesWithdrawer(msg.sender)) revert NotTokenStakingNodesWithdrawer();
        _;
    }

    modifier onlyTokenStakingNodesManager() {
        // if(msg.sender != address(tokenStakingNodesManager)) revert NotTokenStakingNodesManager(); // @todo
        if(msg.sender != address(tokenStakingNodesManager)) revert("NotTokenStakingNodesManager");
        _;
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  BEACON IMPLEMENTATION  ---------------------------
    //--------------------------------------------------------------------------------------

    /**
      Beacons slot value is defined here:
      https://github.com/OpenZeppelin/openzeppelin-contracts/blob/afb20119b33072da041c97ea717d3ce4417b5e01/contracts/proxy/ERC1967/ERC1967Upgrade.sol#L142
     */
    function implementation() public view returns (address) {
        bytes32 slot = bytes32(uint256(keccak256("eip1967.proxy.beacon")) - 1);
        address implementationVariable;
        assembly {
            implementationVariable := sload(slot)
        }

        IBeacon beacon = IBeacon(implementationVariable);
        return beacon.implementation();
    }

    /// @notice Retrieve the version number of the highest/newest initialize
    ///         function that was executed.
    function getInitializedVersion() external view returns (uint64) {
        return _getInitializedVersion();
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  MODIFIERS  ---------------------------------------
    //--------------------------------------------------------------------------------------

    /// @notice Ensure that the given address is not the zero address.
    /// @param _address The address to check.
    modifier notZeroAddress(address _address) {
        if (_address == address(0)) {
            revert ZeroAddress();
        }
        _;
    }
}
