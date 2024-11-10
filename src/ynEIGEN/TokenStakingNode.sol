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
import {IWrapper} from "src/interfaces/IWrapper.sol";
import {IYieldNestStrategyManager} from "src/interfaces/IYieldNestStrategyManager.sol";
import {IDelegationManagerExtended} from "src/external/eigenlayer/IDelegationManagerExtended.sol";


interface ITokenStakingNodeEvents {
    event DepositToEigenlayer(
        IERC20 indexed asset,
        IStrategy indexed strategy,
        uint256 amount,
        uint256 eigenShares
    );
    event Delegated(address indexed operator, bytes32 approverSalt);
    event Undelegated(bytes32[] withdrawalRoots);
    event QueuedWithdrawals(IStrategy strategies, uint256 shares, bytes32[] fullWithdrawalRoots);
    event CompletedQueuedWithdrawals(uint256 shares, uint256 amountOut, address strategy);
    event DeallocatedTokens(uint256 amount, IERC20 token);
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
    error ArrayLengthMismatch();
    error AlreadySynchronized();
    error WithdrawalMismatch(IStrategy singleStrategy, uint256 singleShare);
    error NotSynchronized();

    //--------------------------------------------------------------------------------------
    //----------------------------------  VARIABLES  ---------------------------------------
    //--------------------------------------------------------------------------------------

    ITokenStakingNodesManager public override tokenStakingNodesManager;
    uint256 public nodeId;

    mapping(IStrategy => uint256) public queuedShares;
    mapping(IERC20 => uint256) public withdrawn;

    address public delegatedTo;

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

    function initializeV2() public reinitializer(2) {
        delegatedTo = IDelegationManager(address(tokenStakingNodesManager.delegationManager())).delegatedTo(address(this));
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
    ) external nonReentrant onlyYieldNestStrategyManager onlyWhenSynchronized {

        uint256 assetsLength = assets.length;
        if (assetsLength != amounts.length || assetsLength != strategies.length) {
            revert ArrayLengthMismatch();
        }

        IStrategyManager strategyManager = tokenStakingNodesManager
            .strategyManager();

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

    function getQueuedSharesAndWithdrawn(IStrategy _strategy, IERC20 _asset) external view returns (uint256, uint256) {
        return (queuedShares[_strategy], withdrawn[_asset]);
    }

    /**
     * @notice Queues withdrawals for a specific strategy
     * @param _strategy The strategy from which to withdraw
     * @param _shares The number of shares to withdraw
     * @return _fullWithdrawalRoots An array of withdrawal roots generated by the queueWithdrawals operation
     */
    function queueWithdrawals(
        IStrategy _strategy,
        uint256 _shares
    ) external onlyTokenStakingNodesWithdrawer onlyWhenSynchronized returns (bytes32[] memory _fullWithdrawalRoots) {

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

        emit QueuedWithdrawals(_strategy, _shares, _fullWithdrawalRoots);
    }

    /**
     * @notice Completes queued withdrawals for a specific strategy
     * @param _nonce The nonce of the withdrawal
     * @param _startBlock The block number when the withdrawal was queued
     * @param _shares The number of shares to withdraw
     * @param _strategy The strategy from which to withdraw
     * @param _middlewareTimesIndexes The indexes of middleware times to use for the withdrawal
     * @param updateTokenStakingNodesBalances If true calls updateTokenStakingNodesBalances for yieldNestStrategyManager
     */
    function completeQueuedWithdrawals(
        uint256 _nonce,
        uint32 _startBlock,
        uint256 _shares,
        IStrategy _strategy,
        uint256[] memory _middlewareTimesIndexes,
        bool updateTokenStakingNodesBalances
    ) public onlyTokenStakingNodesWithdrawer onlyWhenSynchronized {

        IDelegationManager _delegationManager = tokenStakingNodesManager.delegationManager();

        IDelegationManager.Withdrawal[] memory _withdrawals = new IDelegationManager.Withdrawal[](1);
        {
            IStrategy[] memory _strategiesArray = new IStrategy[](1);
            _strategiesArray[0] = _strategy;
            uint256[] memory _sharesArray = new uint256[](1);
            _sharesArray[0] = _shares;
            _withdrawals[0] = IDelegationManager.Withdrawal({
                staker: address(this),
                delegatedTo: _delegationManager.delegatedTo(address(this)),
                withdrawer: address(this),
                nonce: _nonce,
                startBlock: _startBlock,
                strategies: _strategiesArray,
                shares: _sharesArray
            });
        }

        IERC20 _token = _strategy.underlyingToken();
        uint256 _balanceBefore = _token.balanceOf(address(this));

        {
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
        }

        uint256 _actualAmountOut = _token.balanceOf(address(this)) - _balanceBefore;
        IWrapper _wrapper = IYieldNestStrategyManager(tokenStakingNodesManager.yieldNestStrategyManager()).wrapper();
        IERC20(_token).forceApprove(address(_wrapper), _actualAmountOut); // NOTE: approving also token that will not be transferred
        (_actualAmountOut, _token) = _wrapper.wrap(_actualAmountOut, _token);

        queuedShares[_strategy] -= _shares;
        withdrawn[_token] += _actualAmountOut;

        if (updateTokenStakingNodesBalances) {
            // Actual balance changes only if slashing occured. choose to update here
            // only if the off-chain considers it necessary to save gas
            IYieldNestStrategyManager(tokenStakingNodesManager.yieldNestStrategyManager()).updateTokenStakingNodesBalances(
                _token
            );
        }

        emit CompletedQueuedWithdrawals(_shares, _actualAmountOut, address(_strategy));
    }

    /**
     * @notice Deallocates tokens from the withdrawn balance and approves them for transfer.
     * @param _token The ERC20 token to deallocate.
     * @param _amount The amount of tokens to deallocate.
     */
    function deallocateTokens(IERC20 _token, uint256 _amount) external onlyYieldNestStrategyManager {
        withdrawn[_token] -= _amount;
        _token.safeTransfer(msg.sender, _amount);

        emit DeallocatedTokens(_amount, _token);
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
    ) public virtual onlyDelegator onlyWhenSynchronized {
        IDelegationManager delegationManager = tokenStakingNodesManager
            .delegationManager();
        delegationManager.delegateTo(operator, signature, approverSalt);

        emit Delegated(operator, approverSalt);
    }

    /**
     * @notice Undelegates the staking operation.
     */
    function undelegate() public override onlyDelegator onlyWhenSynchronized {
        IDelegationManagerExtended delegationManager = IDelegationManagerExtended(
            address(tokenStakingNodesManager.delegationManager())
        );

        (IStrategy[] memory strategies, uint256[] memory shares) = delegationManager.getDelegatableShares(address(this));

        bytes32[] memory withdrawalRoots = delegationManager.undelegate(
            address(this)
        );

        // Update queued shares for each strategy
        for (uint256 i = 0; i < strategies.length; i++) {
            queuedShares[strategies[i]] += shares[i];
        }

        emit Undelegated(withdrawalRoots);
    }


    //--------------------------------------------------------------------------------------
    //----------------------------------  SYNCHRONIZATION  ---------------------------------
    //--------------------------------------------------------------------------------------

    /**
     * @notice Checks if the StakingNode's delegation state is synced with the DelegationManager.
     * @dev Compares the locally stored delegatedTo address with the actual delegation in DelegationManager.
     * @return True if the delegation state is synced, false otherwise.
     */
    function isSynchronized() public view returns (bool) {
        IDelegationManager delegationManager = IDelegationManager(address(tokenStakingNodesManager.delegationManager()));
        return delegatedTo == delegationManager.delegatedTo(address(this));
    }

    function synchronize(
        uint256[] calldata queuedSharesAmounts,
        uint32 lastQueuedWithdrawalBlockNumber,
        IStrategy[] calldata strategies
    ) public onlyDelegator {

        if (isSynchronized()) {
            revert AlreadySynchronized();
        }

        if (queuedSharesAmounts.length != strategies.length) {
            revert ArrayLengthMismatch();
        }

        IDelegationManager delegationManager = IDelegationManager(address(tokenStakingNodesManager.delegationManager()));

        address thisNode = address(this);
        
        // Get the total number of withdrawals queued for this staking node
        uint256 totalWithdrawals = delegationManager.cumulativeWithdrawalsQueued(thisNode);

        address _delegatedTo = delegatedTo;
        
        // Loop through the last withdrawals in reverse order to verify each strategy withdrawal
        for (uint256 i = 0; i < strategies.length; i++) {
            IStrategy[] memory singleStrategy = new IStrategy[](1);
            uint256[] memory singleShare = new uint256[](1);
            singleStrategy[0] = strategies[strategies.length - 1 - i];
            singleShare[0] = queuedSharesAmounts[strategies.length - 1 - i];

            IDelegationManager.Withdrawal memory withdrawal = IDelegationManager.Withdrawal({
                staker: thisNode,
                delegatedTo: _delegatedTo,
                withdrawer: thisNode,
                nonce: totalWithdrawals - 1 - i, // Check nonces in reverse order
                startBlock: lastQueuedWithdrawalBlockNumber,
                strategies: singleStrategy,
                shares: singleShare
            });

            bytes32 withdrawalRoot = delegationManager.calculateWithdrawalRoot(withdrawal);

            // Each withdrawal must exist
            if (!IDelegationManagerExtended(address(delegationManager)).pendingWithdrawals(withdrawalRoot)) {
                revert WithdrawalMismatch(singleStrategy[0], singleShare[0]);
            }
        }

        // queue shares
        for (uint256 i = 0; i < strategies.length; i++) {
            queuedShares[strategies[i]] += queuedSharesAmounts[i];
        }

        delegatedTo = delegationManager.delegatedTo(address(this));
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
        if (
            !IYieldNestStrategyManager(tokenStakingNodesManager.yieldNestStrategyManager()).isStakingNodesWithdrawer(msg.sender)
        ) revert NotTokenStakingNodesWithdrawer();
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

    modifier onlyWhenSynchronized() {
        if (!isSynchronized()) {
            revert NotSynchronized();
        }
        _;
    }  
}
