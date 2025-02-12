// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {Initializable} from "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {IBeacon} from "lib/openzeppelin-contracts/contracts/proxy/beacon/IBeacon.sol";
import {ReentrancyGuardUpgradeable} from
    "lib/openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC20 as IERC20V4} from "lib/eigenlayer-contracts/lib/openzeppelin-contracts-v4.9.0/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ArrayLib} from "src/lib/ArrayLib.sol";
import {ISignatureUtils} from "lib/eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";
import {IStrategyManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IDelegationManager, IDelegationManagerTypes} from "lib/eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategy} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IRewardsCoordinator} from "lib/eigenlayer-contracts/src/contracts/interfaces/IRewardsCoordinator.sol";
import {SlashingLib, DepositScalingFactor} from "lib/eigenlayer-contracts/src/contracts/libraries/SlashingLib.sol";
import {IAllocationManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {ITokenStakingNode} from "src/interfaces/ITokenStakingNode.sol";
import {ITokenStakingNodesManager} from "src/interfaces/ITokenStakingNodesManager.sol";
import {IWrapper} from "src/interfaces/IWrapper.sol";
import {IYieldNestStrategyManager} from "src/interfaces/IYieldNestStrategyManager.sol";
import {IDelegationManagerExtended} from "src/external/eigenlayer/IDelegationManagerExtended.sol";

interface ITokenStakingNodeEvents {
    event DepositToEigenlayer(IERC20 indexed asset, IStrategy indexed strategy, uint256 amount, uint256 eigenShares);
    event Delegated(address indexed operator, bytes32 approverSalt);
    event Undelegated(bytes32[] withdrawalRoots);
    event QueuedWithdrawals(IStrategy strategies, uint256 shares, bytes32[] fullWithdrawalRoots);
    event CompletedQueuedWithdrawals(uint256 shares, uint256 amountOut, address strategy);
    event DeallocatedTokens(uint256 amount, IERC20 token);
    event CompletedManyQueuedWithdrawals(IDelegationManager.Withdrawal[] withdrawals);
    event ClaimerSet(address indexed claimer);
}

/**
 * @title Token Staking Node
 * @dev Implements staking node functionality for tokens, enabling token staking, delegation, and rewards management.
 * This contract interacts with the Eigenlayer protocol to deposit assets, delegate staking operations, and manage staking rewards.
 */
contract TokenStakingNode is ITokenStakingNode, Initializable, ReentrancyGuardUpgradeable, ITokenStakingNodeEvents {
    using SafeERC20 for IERC20;
    using SlashingLib for DepositScalingFactor;
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
    error StrategyNotFound(address strategy);
    error AlreadyDelegated();
    error InvalidWithdrawal(uint256 index);
    //--------------------------------------------------------------------------------------
    //----------------------------------  VARIABLES  ---------------------------------------
    //--------------------------------------------------------------------------------------

    ITokenStakingNodesManager public override tokenStakingNodesManager;
    uint256 public nodeId;

    mapping(IStrategy => uint256) public queuedShares;
    mapping(IERC20 => uint256) public withdrawn;

    address public delegatedTo;

    /**
     * @notice Tracks the operator/strategy maxMagnitude.
     */
    mapping(bytes32 => uint64) public maxMagnitudeByWithdrawalRoot;

    /**
     * @notice Tracks the withdrawable shares for each withdrawal.
     */
    mapping(bytes32 => uint256) public withdrawableSharesByWithdrawalRoot;

    //--------------------------------------------------------------------------------------
    //----------------------------------  INITIALIZATION  ----------------------------------
    //--------------------------------------------------------------------------------------

    constructor() {
        _disableInitializers();
    }

    function initialize(Init memory init) public notZeroAddress(address(init.tokenStakingNodesManager)) initializer {
        __ReentrancyGuard_init();
        tokenStakingNodesManager = init.tokenStakingNodesManager;
        nodeId = init.nodeId;
    }

    function initializeV2() public reinitializer(2) {
        delegatedTo =
            IDelegationManager(address(tokenStakingNodesManager.delegationManager())).delegatedTo(address(this));
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

        IStrategyManager strategyManager = tokenStakingNodesManager.strategyManager();

        for (uint256 i = 0; i < assetsLength; i++) {
            IERC20 asset = assets[i];
            uint256 amount = amounts[i];
            IStrategy strategy = strategies[i];

            asset.forceApprove(address(strategyManager), amount);

            uint256 eigenShares = strategyManager.depositIntoStrategy(IStrategy(strategy), IERC20V4(address(asset)), amount);
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
     * @param _depositShares The number of deposit shares to withdraw. The amount of withdrawn shares on completion might be lower due to slashing.
     * @return _fullWithdrawalRoots An array of withdrawal roots generated by the queueWithdrawals operation
     */
    function queueWithdrawals(IStrategy _strategy, uint256 _depositShares)
        external
        onlyTokenStakingNodesWithdrawer
        onlyWhenSynchronized
        returns (bytes32[] memory _fullWithdrawalRoots)
    {
        IStrategy[] memory _strategiesArray = new IStrategy[](1);
        _strategiesArray[0] = _strategy;
        uint256[] memory _depositSharesArray = new uint256[](1);
        _depositSharesArray[0] = _depositShares;
        IDelegationManagerTypes.QueuedWithdrawalParams[] memory _params = new IDelegationManagerTypes.QueuedWithdrawalParams[](1);
        _params[0] = IDelegationManagerTypes.QueuedWithdrawalParams({
            strategies: _strategiesArray,
            depositShares: _depositSharesArray,
            __deprecated_withdrawer: address(0)
        });

        IDelegationManagerExtended delegationManager = IDelegationManagerExtended(address(tokenStakingNodesManager.delegationManager()));

        // For accounting purposes, we need to calculate the withdrawable shares based on the deposit shares and the slashing factor of the operator.
        // The slashing factor for non beacon chain strategies is composed only of the operator's max magnitude.
        // If the operator is address(0) the max magnitude will be 1e18 (wad).
        uint64 maxMagnitude = delegationManager.allocationManager().getMaxMagnitude(delegatedTo, _strategy);
        DepositScalingFactor memory depositScalingFactor = DepositScalingFactor({_scalingFactor: delegationManager.depositScalingFactor(address(this), _strategy)});
        uint256 withdrawableShares = depositScalingFactor.calcWithdrawable(_depositShares, maxMagnitude);

        queuedShares[_strategy] += withdrawableShares;

        _fullWithdrawalRoots = delegationManager.queueWithdrawals(_params);

        emit QueuedWithdrawals(_strategy, withdrawableShares, _fullWithdrawalRoots);
    }

    /**
     * @notice Completes queued withdrawals with receiveAsTokens set to true
     * @param withdrawals Array of withdrawals to complete
     * @param middlewareTimesIndexes Array of middleware times indexes
     * @param updateTokenStakingNodesBalances If true calls updateTokenStakingNodesBalances for yieldNestStrategyManager
     */
    function completeQueuedWithdrawals(
        IDelegationManager.Withdrawal[] memory withdrawals,
        uint256[] memory middlewareTimesIndexes,
        bool updateTokenStakingNodesBalances
    ) public onlyTokenStakingNodesWithdrawer onlyWhenSynchronized {

        if (withdrawals.length != middlewareTimesIndexes.length) {
            revert ArrayLengthMismatch();
        }

        IDelegationManager _delegationManager = tokenStakingNodesManager.delegationManager();
        IERC20V4[][] memory _tokens = new IERC20V4[][](withdrawals.length);
        IStrategy[] memory _strategies = new IStrategy[](withdrawals.length);
        bool[] memory _receiveAsTokens = new bool[](withdrawals.length);
        IWrapper _wrapper = IYieldNestStrategyManager(tokenStakingNodesManager.yieldNestStrategyManager()).wrapper();
        address[] memory _dupTokens = new address[](withdrawals.length);

        for (uint256 i = 0; i < withdrawals.length; i++) {
            if (withdrawals[i].scaledShares.length != 1 || withdrawals[i].strategies.length != 1) {
                revert InvalidWithdrawal(i);
            }
            IStrategy _strategy = withdrawals[i].strategies[0];
            queuedShares[_strategy] -= withdrawals[i].scaledShares[0];

            _strategies[i] = _strategy;
            _tokens[i] = new IERC20V4[](1);
            _tokens[i][0] = _strategy.underlyingToken();
            IERC20V4 _token = _tokens[i][0];
            _receiveAsTokens[i] = true;
            _dupTokens[i] = address(_token);
        }

        address[] memory _dedupTokens = ArrayLib.deduplicate(_dupTokens);
        uint256[] memory _balancesBefore = new uint256[](_dedupTokens.length);

        for (uint256 i = 0; i < _dedupTokens.length; i++) {
            _balancesBefore[i] = IERC20(_dedupTokens[i]).balanceOf(address(this));
        }

        _delegationManager.completeQueuedWithdrawals(
            withdrawals, 
            _tokens, 
            // middlewareTimesIndexes, 
            _receiveAsTokens
        ); 

        for (uint256 i = 0; i < _dedupTokens.length; i++) {
            IERC20 _token = IERC20(_dedupTokens[i]);
            uint256 _actualAmountOut = _token.balanceOf(address(this)) - _balancesBefore[i];
            IERC20(_token).forceApprove(address(_wrapper), _actualAmountOut); // NOTE: approving also token that will not be transferred
            (_actualAmountOut, _token) = _wrapper.wrap(_actualAmountOut, _token);
            withdrawn[_token] += _actualAmountOut;
            if (updateTokenStakingNodesBalances) {
                IYieldNestStrategyManager(tokenStakingNodesManager.yieldNestStrategyManager())
                    .updateTokenStakingNodesBalances(_token);
            }
        }

        emit CompletedManyQueuedWithdrawals(withdrawals);
    }

    /**
     * @notice Completes queued withdrawals with receiveAsTokens set to true
     * @param withdrawal The withdrawal to complete
     * @param middlewareTimesIndex The middleware times index
     * @param updateTokenStakingNodesBalances If true calls updateTokenStakingNodesBalances for yieldNestStrategyManager
     */
    function completeQueuedWithdrawals(
        IDelegationManager.Withdrawal calldata withdrawal,
        uint256 middlewareTimesIndex,
        bool updateTokenStakingNodesBalances
    ) public onlyTokenStakingNodesWithdrawer onlyWhenSynchronized {
        IDelegationManager.Withdrawal[] memory _withdrawals = new IDelegationManager.Withdrawal[](1);
        _withdrawals[0] = withdrawal;
        uint256[] memory _middlewareTimesIndexes = new uint256[](1);
        _middlewareTimesIndexes[0] = middlewareTimesIndex;
        completeQueuedWithdrawals(_withdrawals, _middlewareTimesIndexes, updateTokenStakingNodesBalances);
    }

    /**
     * @notice Struct containing strategy and shares information
     * @param strategy The strategy contract address
     * @param shares The number of shares
     */
    struct StrategyShares {
        IStrategy strategy;
        uint256 shares;
    }

    /**
     * @notice Completes queued withdrawals with receiveAsTokens set to false
     * @param withdrawals Array of withdrawals to complete
     * @param middlewareTimesIndexes Array of middleware times indexes
     */
    function completeQueuedWithdrawalsAsShares(
        IDelegationManager.Withdrawal[] calldata withdrawals,
        uint256[] calldata middlewareTimesIndexes
    ) external onlyDelegator onlyWhenSynchronized {
        if (withdrawals.length != middlewareTimesIndexes.length) {
            revert ArrayLengthMismatch();
        }

        IDelegationManager delegationManager = IDelegationManager(address(tokenStakingNodesManager.delegationManager()));
        IERC20V4[][] memory _tokens = new IERC20V4[][](withdrawals.length);
        bool[] memory _receiveAsTokens = new bool[](withdrawals.length);
        // Decrease queued shares for each strategy
        for (uint256 i = 0; i < withdrawals.length; i++) {
            if (withdrawals[i].scaledShares.length != 1 || withdrawals[i].strategies.length != 1) {
                revert InvalidWithdrawal(i);
            }
            queuedShares[withdrawals[i].strategies[0]] -= withdrawals[i].scaledShares[0];
            _tokens[i] = new IERC20V4[](1);
            _tokens[i][0] = withdrawals[i].strategies[0].underlyingToken();
            _receiveAsTokens[i] = false;
        }

        // Complete withdrawals with receiveAsTokens = false
        delegationManager.completeQueuedWithdrawals(
            withdrawals, 
            _tokens, 
            // middlewareTimesIndexes, 
            _receiveAsTokens
        );

        emit CompletedManyQueuedWithdrawals(withdrawals);
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
    function delegate(address operator, ISignatureUtils.SignatureWithExpiry memory signature, bytes32 approverSalt)
        public
        virtual
        onlyDelegator
        onlyWhenSynchronized
    {
        IDelegationManager delegationManager = tokenStakingNodesManager.delegationManager();
        delegationManager.delegateTo(operator, signature, approverSalt);

        delegatedTo = operator;

        emit Delegated(operator, approverSalt);
    }

    /**
     * @notice Undelegates the staking operation.
     */
    function undelegate()
        public
        override
        onlyDelegator
        onlyWhenSynchronized
        returns (bytes32[] memory withdrawalRoots)
    {
        IDelegationManagerExtended delegationManager =
            IDelegationManagerExtended(address(tokenStakingNodesManager.delegationManager()));

        (IStrategy[] memory strategies,) = delegationManager.getDepositedShares(address(this));

        (uint256[] memory withdrawableShares,) = delegationManager.getWithdrawableShares(address(this), strategies);

        withdrawalRoots = delegationManager.undelegate(address(this));

        // Update queued shares for each strategy
        for (uint256 i = 0; i < strategies.length; i++) {
            queuedShares[strategies[i]] += withdrawableShares[i];
        }

        delegatedTo = address(0);

        emit Undelegated(withdrawalRoots);
    }

    /**
     * @notice Sets the claimer for rewards using the rewards coordinator
     * @dev Only callable by delegator. Sets the claimer address for this staking node's rewards.
     * @param claimer The address to set as the claimer
     */
    function setClaimer(address claimer) external onlyDelegator {
        IRewardsCoordinator rewardsCoordinator = tokenStakingNodesManager.rewardsCoordinator();
        rewardsCoordinator.setClaimerFor(claimer);
        emit ClaimerSet(claimer);
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

    /**
     * @notice Synchronizes the staking node's delegation state with the DelegationManager.
     * @dev This function will be called by the trusted entity when the operator calls undelegate() on this staking node because shares accounting will be out of sync
     * @param queuedSharesAmounts The amount of shares to be queued for each strategy.
     * @param undelegateBlockNumber The block number of the undelegate() call by the operator
     * @param strategies The strategies to be queued.
     */
    function synchronize(
        uint256[] calldata queuedSharesAmounts,
        uint32 undelegateBlockNumber,
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

        if (delegationManager.isDelegated(thisNode)) {
            revert AlreadyDelegated();
        }

        // Get the total number of withdrawals queued for this staking node
        // this is respresented as nonce in Eigenlayer's Withdrawal struct
        uint256 totalWithdrawals = delegationManager.cumulativeWithdrawalsQueued(thisNode);

        // operator which called undelegate on this staking node
        address _delegatedTo = delegatedTo;

        // if there are other queued withdrawals apart from the ones due to undelegate call
        uint256 withdrawalsNonceFromOperatorUndelegate = totalWithdrawals - strategies.length;

        // Loop through the last withdrawals in reverse order to verify each strategy withdrawal
        for (uint256 i = 0; i < strategies.length; i++) {
            IStrategy[] memory singleStrategy = new IStrategy[](1);
            uint256[] memory singleShare = new uint256[](1);
            singleStrategy[0] = strategies[i];
            singleShare[0] = queuedSharesAmounts[i];

            IDelegationManagerTypes.Withdrawal memory withdrawal = IDelegationManagerTypes.Withdrawal({
                staker: thisNode,
                delegatedTo: _delegatedTo,
                withdrawer: thisNode,
                nonce: withdrawalsNonceFromOperatorUndelegate + i,
                startBlock: undelegateBlockNumber,
                strategies: singleStrategy,
                scaledShares: singleShare
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

        delegatedTo = address(0);
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  MODIFIERS  ---------------------------------------
    //--------------------------------------------------------------------------------------

    modifier onlyOperator() {
        if (!tokenStakingNodesManager.hasTokenStakingNodeOperatorRole(msg.sender)) {
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
            !IYieldNestStrategyManager(tokenStakingNodesManager.yieldNestStrategyManager()).isStakingNodesWithdrawer(
                msg.sender
            )
        ) revert NotTokenStakingNodesWithdrawer();
        _;
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  BEACON IMPLEMENTATION  ---------------------------
    //--------------------------------------------------------------------------------------

    /**
     * Beacons slot value is defined here:
     *   https://github.com/OpenZeppelin/openzeppelin-contracts/blob/afb20119b33072da041c97ea717d3ce4417b5e01/contracts/proxy/ERC1967/ERC1967Upgrade.sol#L142
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
