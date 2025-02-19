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
import {IAllocationManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {ITokenStakingNode} from "src/interfaces/ITokenStakingNode.sol";
import {ITokenStakingNodesManager} from "src/interfaces/ITokenStakingNodesManager.sol";
import {IWrapper} from "src/interfaces/IWrapper.sol";
import {IYieldNestStrategyManager} from "src/interfaces/IYieldNestStrategyManager.sol";
import {IDelegationManagerExtended} from "src/external/eigenlayer/IDelegationManagerExtended.sol";
import {IAssetRegistry} from "src/interfaces/IAssetRegistry.sol";
import {IynEigen} from "src/interfaces/IynEigen.sol";

interface ITokenStakingNodeEvents {
    event DepositToEigenlayer(IERC20 indexed asset, IStrategy indexed strategy, uint256 amount, uint256 eigenShares);
    event Delegated(address indexed operator, bytes32 approverSalt);
    event Undelegated(bytes32[] withdrawalRoots);
    event QueuedWithdrawals(IStrategy strategies, uint256 shares, bytes32[] fullWithdrawalRoots);
    event DeallocatedTokens(uint256 amount, IERC20 token);
    event CompletedManyQueuedWithdrawals(IDelegationManager.Withdrawal[] withdrawals);
    event ClaimerSet(address indexed claimer);
    event QueuedSharesSynced();
}

/// This interface is created because the src/interfaces/IynEigen.sol does not provide a way to obtain the assetRegistry.
/// TODO: Should we expose assetRegistry in IynEigen?
interface IynEigenExtended is IynEigen {
    function assetRegistry() external view returns (IAssetRegistry);
}

/// This interface is created because src/interfaces/IYieldNestStrategyManager.sol does not provide a way to obtain `ynEigen` which is needed to get the assetRegistry.
/// TODO: Should we expose ynEigen in IYieldNestStrategyManager?
interface IYieldNestStrategyManagerExtended is IYieldNestStrategyManager {
    function ynEigen() external view returns (IynEigenExtended);
}

/**
 * @title Token Staking Node
 * @dev Implements staking node functionality for tokens, enabling token staking, delegation, and rewards management.
 * This contract interacts with the Eigenlayer protocol to deposit assets, delegate staking operations, and manage staking rewards.
 */
contract TokenStakingNode is ITokenStakingNode, Initializable, ReentrancyGuardUpgradeable, ITokenStakingNodeEvents {
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
    error OperatorNotSynchronized();
    error InvalidWithdrawal(uint256 index);
    error NotSyncedAfterSlashing(bytes32 withdrawalRoot, uint64 maxMagnitudeAtSync, uint64 maxMagnitudeNow);
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
     * @dev Used to check if the queuedShares have been synced after a slashing event.
     */
    mapping(bytes32 => uint64) public maxMagnitudeByWithdrawalRoot;

    /**
     * @notice Tracks the withdrawable shares for each withdrawal.
     * @dev Used to decrease the queuedShares amount after completing a withdrawal.
     */
    mapping(bytes32 => uint256) public withdrawableSharesByWithdrawalRoot;

    /**
     * @notice Tracks the pre slashing upgrade queued shares for each strategy.
     * @dev Used to persist any pre slashing queued shares on sync without losing them.
     * The values will tend to zero as the legacy withdrawals are completed.
     */
    mapping(IStrategy => uint256) public legacyQueuedShares;
    
    /**
     * @notice Tracks if a withdrawal was queued after the slashing upgrade.
     * @dev using `maxMagnitudeByWithdrawalRoot` or `withdrawableSharesByWithdrawalRoot` might not be enough to detect this
     * because the operator might be fully slashed and the values provided will be 0, same as the default values.
     */
    mapping(bytes32 => bool) public queuedAfterSlashingUpgrade;

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

    /**
     * @notice Initializes the contract by storing the current operator and pre slashing queued shares.
     */
    function initializeV2() public reinitializer(2) {
        delegatedTo = IDelegationManager(address(tokenStakingNodesManager.delegationManager())).delegatedTo(address(this));

        IYieldNestStrategyManagerExtended eigenStrategyManager = IYieldNestStrategyManagerExtended(tokenStakingNodesManager.yieldNestStrategyManager());
        IAssetRegistry assetRegistry = IAssetRegistry(eigenStrategyManager.ynEigen().assetRegistry());
        IERC20[] memory assets = assetRegistry.getAssets();

        for (uint256 i = 0; i < assets.length; i++) {
            IStrategy strategy = eigenStrategyManager.strategies(assets[i]);
            legacyQueuedShares[strategy] = queuedShares[strategy];
        }
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
    ) external nonReentrant onlyYieldNestStrategyManager onlyWhenOperatorSynchronized {
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
        onlyWhenOperatorSynchronized
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

        IDelegationManagerExtended _delegationManager = IDelegationManagerExtended(address(tokenStakingNodesManager.delegationManager()));

        // `onlyWhenOperatorSynchronized` is used so we can assume that the operator is the same as the one in the DelegationManager.
        address _operator = delegatedTo;
        uint256 _withdrawableShares;
        bytes32 _withdrawalRoot;

        if (_operator == address(0)) {
            _fullWithdrawalRoots = _delegationManager.queueWithdrawals(_params);
            _withdrawalRoot = _fullWithdrawalRoots[0];
            IDelegationManagerTypes.Withdrawal memory _queuedWithdrawal = _delegationManager.getQueuedWithdrawal(_withdrawalRoot);

            // If the staker has not yet delegated to an operator, and given that this contract does not handle the beacon chain strategy.
            // We can assume that the scaledShares can be used as the withdrawable shares because:
            // - withdrawableShares = scaledShares * maxMagnitude * beaconChainSlashFactor.
            // - scaledShares = withdrawableShares / (maxMagnitude * beaconChainSlashFactor).
            // - scaledShares = withdrawableShares / (1 * 1). maxMagnitude is 1 when not delegated and beaconChainSlashFactor is 1 because it is not using the beacon chain strategy.
            // - scaledShares = withdrawableShares.
            _withdrawableShares = _queuedWithdrawal.scaledShares[0];
        } else {
            uint256[] memory operatorSharesBefore = _delegationManager.getOperatorShares(_operator, _params[0].strategies);
            _fullWithdrawalRoots = _delegationManager.queueWithdrawals(_params);
            _withdrawalRoot = _fullWithdrawalRoots[0];
            uint256[] memory operatorSharesAfter = _delegationManager.getOperatorShares(_operator, _params[0].strategies);

            // Operator shares are decreased by the amount of withdrawable shares so we can use the difference to update the queued shares.
            _withdrawableShares = operatorSharesBefore[0] - operatorSharesAfter[0];
        }

        queuedShares[_strategy] += _withdrawableShares;
        maxMagnitudeByWithdrawalRoot[_withdrawalRoot] = _delegationManager.allocationManager().getMaxMagnitude(_operator, _strategy);
        withdrawableSharesByWithdrawalRoot[_withdrawalRoot] = _withdrawableShares;
        queuedAfterSlashingUpgrade[_withdrawalRoot] = true;

        emit QueuedWithdrawals(_strategy, _withdrawableShares, _fullWithdrawalRoots);
    }

    /**
     * @notice Completes queued withdrawals with receiveAsTokens set to true
     * @param withdrawals Array of withdrawals to complete
     * @param updateTokenStakingNodesBalances If true calls updateTokenStakingNodesBalances for yieldNestStrategyManager
     */
    function completeQueuedWithdrawals(
        IDelegationManager.Withdrawal[] memory withdrawals,
        bool updateTokenStakingNodesBalances
    ) public onlyTokenStakingNodesWithdrawer onlyWhenOperatorSynchronized {
        IDelegationManagerExtended _delegationManager = IDelegationManagerExtended(address(tokenStakingNodesManager.delegationManager()));
        IERC20V4[][] memory _tokens = new IERC20V4[][](withdrawals.length);
        IStrategy[] memory _strategies = new IStrategy[](withdrawals.length);
        bool[] memory _receiveAsTokens = new bool[](withdrawals.length);
        IWrapper _wrapper = IYieldNestStrategyManager(tokenStakingNodesManager.yieldNestStrategyManager()).wrapper();
        address[] memory _dupTokens = new address[](withdrawals.length);

        IAllocationManager _allocationManager = _delegationManager.allocationManager();

        for (uint256 i = 0; i < withdrawals.length; i++) {
            IDelegationManagerTypes.Withdrawal memory _withdrawal = withdrawals[i];

            if (_withdrawal.scaledShares.length != 1 || _withdrawal.strategies.length != 1) {
                revert InvalidWithdrawal(i);
            }

            IStrategy _strategy = _withdrawal.strategies[0];

            _strategies[i] = _strategy;
            _tokens[i] = new IERC20V4[](1);
            _tokens[i][0] = _strategy.underlyingToken();
            _receiveAsTokens[i] = true;
            _dupTokens[i] = address(_tokens[i][0]);

            _decreaseQueuedSharesOnCompleteWithdrawals(_delegationManager, _allocationManager, _strategy, _withdrawal);
        }

        address[] memory _dedupTokens = ArrayLib.deduplicate(_dupTokens);
        uint256[] memory _balancesBefore = new uint256[](_dedupTokens.length);

        for (uint256 i = 0; i < _dedupTokens.length; i++) {
            _balancesBefore[i] = IERC20(_dedupTokens[i]).balanceOf(address(this));
        }

        _delegationManager.completeQueuedWithdrawals(withdrawals, _tokens, _receiveAsTokens);

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
     * @param updateTokenStakingNodesBalances If true calls updateTokenStakingNodesBalances for yieldNestStrategyManager
     */
    function completeQueuedWithdrawals(
        IDelegationManager.Withdrawal calldata withdrawal,
        bool updateTokenStakingNodesBalances
    ) public onlyTokenStakingNodesWithdrawer onlyWhenOperatorSynchronized {
        IDelegationManager.Withdrawal[] memory _withdrawals = new IDelegationManager.Withdrawal[](1);
        _withdrawals[0] = withdrawal;
        completeQueuedWithdrawals(_withdrawals, updateTokenStakingNodesBalances);
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
     */
    function completeQueuedWithdrawalsAsShares(
        IDelegationManager.Withdrawal[] calldata withdrawals
    ) external onlyDelegator onlyWhenOperatorSynchronized {
        IDelegationManagerExtended _delegationManager = IDelegationManagerExtended(address(tokenStakingNodesManager.delegationManager()));
        IERC20V4[][] memory _tokens = new IERC20V4[][](withdrawals.length);
        bool[] memory _receiveAsTokens = new bool[](withdrawals.length);

        IAllocationManager _allocationManager = _delegationManager.allocationManager();

        // Decrease queued shares for each strategy
        for (uint256 i = 0; i < withdrawals.length; i++) {
            IDelegationManagerTypes.Withdrawal memory _withdrawal = withdrawals[i];

            if (_withdrawal.scaledShares.length != 1 || _withdrawal.strategies.length != 1) {
                revert InvalidWithdrawal(i);
            }

            IStrategy _strategy = _withdrawal.strategies[0];

            _tokens[i] = new IERC20V4[](1);
            _tokens[i][0] = _strategy.underlyingToken();
            _receiveAsTokens[i] = false;

            _decreaseQueuedSharesOnCompleteWithdrawals(_delegationManager, _allocationManager, _strategy, _withdrawal);
        }

        // Complete withdrawals with receiveAsTokens = false
        _delegationManager.completeQueuedWithdrawals(withdrawals, _tokens, _receiveAsTokens);

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
        onlyWhenOperatorSynchronized
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
        onlyWhenOperatorSynchronized
        returns (bytes32[] memory withdrawalRoots)
    {
        IDelegationManager delegationManager = tokenStakingNodesManager.delegationManager();

        withdrawalRoots = delegationManager.undelegate(address(this));

        // Call to synchronize to update the queued shares and delegatedTo address.
        synchronize();

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
     * @notice Checks if the StakingNode's delegatedTo is synced with the DelegationManager.
     * @dev Compares the locally stored delegatedTo address with the actual delegation in DelegationManager.
     * @return True if the delegation state is synced, false otherwise.
     */
    function isOperatorSynchronized() public view returns (bool) {
        IDelegationManager delegationManager = IDelegationManager(address(tokenStakingNodesManager.delegationManager()));
        return delegatedTo == delegationManager.delegatedTo(address(this));
    }

    /**
     * @notice Synchronizes both the delegatedTo address with the DelegationManager and the queued shares.
     * @dev Anyone can call this function because every call is beneficial to the protocol as it keeps accounting in sync.
     */
    function synchronize() public {
        IDelegationManagerExtended delegationManager = IDelegationManagerExtended(address(tokenStakingNodesManager.delegationManager()));
        IAllocationManager allocationManager = delegationManager.allocationManager();

        // Update the delegatedTo address to the current operator.
        delegatedTo = delegationManager.delegatedTo(address(this));

        // Requests the queued withdrawals and the withdrawable shares of each from the delegation manager.
        (IDelegationManager.Withdrawal[] memory withdrawals, uint256[][] memory withdrawableSharesPerWithdrawal) = delegationManager.getQueuedWithdrawals(address(this));

        // Reset the queued shares for each strategy back to zero.
        for (uint256 i = 0; i < withdrawals.length; i++) {
            // Withdrawals are queued always with a single strategy so we can ignore other entries in the strategies array.
            // Queued shares are reset to the legacy queued shares value given that `getQueuedWithdrawals` returns only withdrawals post slashing upgrade.
            queuedShares[withdrawals[i].strategies[0]] = legacyQueuedShares[withdrawals[i].strategies[0]];
        }

        for (uint256 i = 0; i < withdrawals.length; i++) {
            IDelegationManagerTypes.Withdrawal memory withdrawal = withdrawals[i];
            IStrategy strategy = withdrawal.strategies[0];

            uint256 withdrawableShares = withdrawableSharesPerWithdrawal[i][0];
            bytes32 withdrawalRoot = delegationManager.calculateWithdrawalRoot(withdrawal);

            // Update the queued shares for the strategy by adding the withdrawable shares.
            queuedShares[strategy] += withdrawableShares;
            // Store the current withdrawable shares for the withdrawal.
            withdrawableSharesByWithdrawalRoot[withdrawalRoot] = withdrawableShares;
            // Get the current maxMagnitude for operator/strategy of the withdrawal.
            maxMagnitudeByWithdrawalRoot[withdrawalRoot] = allocationManager.getMaxMagnitude(withdrawal.delegatedTo, strategy);
            // Set the value to true to indicate that the withdrawal was queued after the slashing upgrade in case it was done outside of the contract.
            // For example, when the operator undelegates itself from the staker via the DelegationManager::undelegate function.
            queuedAfterSlashingUpgrade[withdrawalRoot] = true;
        }

        emit QueuedSharesSynced();
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

    /// @notice Modifier to ensure the token staking node's delegatedTo is synchronized with the DelegationManager.
    modifier onlyWhenOperatorSynchronized() {
        if (!isOperatorSynchronized()) {
            revert OperatorNotSynchronized();
        }
        _;
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  INTERNAL  ------------------------------
    //--------------------------------------------------------------------------------------

    /**
     * @dev Decreases the queued shares by the withdrawable amount after validating if the contract was synchronized after a slashing event.
     * @param _delegationManager The delegation manager contract.
     * @param _allocationManager The allocation manager contract.
     * @param _strategy The strategy to decrease the queued shares for.
     * @param _withdrawal The withdrawal to decrease the queued shares for.
     */
    function _decreaseQueuedSharesOnCompleteWithdrawals(
        IDelegationManagerExtended _delegationManager,
        IAllocationManager _allocationManager,
        IStrategy _strategy,
        IDelegationManagerTypes.Withdrawal memory _withdrawal
    ) internal {
        bytes32 withdrawalRoot = _delegationManager.calculateWithdrawalRoot(_withdrawal);

        // If the withdrawal was queued before the slashing upgrade, it is considered legacy.
        // NOTE: There is a particular case in which if the operator undelegates itself from the staker, automatically queueing withdrawals,
        // If the node is not synchronized, this might not catch it correctly as it will be marked as legacy.
        if (!queuedAfterSlashingUpgrade[withdrawalRoot]) {
            // Queued shares is decreased by the scaled shares which for legacy withdrawals is the same as the withdrawable shares.
            queuedShares[_strategy] -= _withdrawal.scaledShares[0];
            // Legacy queued shares are decreased by the scaled shares for accounting when calling synchronize.
            legacyQueuedShares[_strategy] -= _withdrawal.scaledShares[0];

            return;
        }

        // To detect if the queued shares have not been synchronized after a slashing event, we compare the
        // maxMagnitude of the withdrawal root at the time of queueing with the current maxMagnitude.
        uint64 maxMagnitudeAtSync = maxMagnitudeByWithdrawalRoot[withdrawalRoot];
        uint64 maxMagnitudeNow = _allocationManager.getMaxMagnitude(_withdrawal.delegatedTo, _strategy);

        // If they are different, it means that the queued shares have not been synced. 
        // In this case, it reverts to prevent accounting issues with the queuedShares variable.
        if (maxMagnitudeAtSync != maxMagnitudeNow) {
            revert NotSyncedAfterSlashing(withdrawalRoot, maxMagnitudeAtSync, maxMagnitudeNow);
        }

        // Decreases the queued shares by the withdrawable amount.
        // This will net to 0 after all queued withdrawals are completed.
        queuedShares[_strategy] -= withdrawableSharesByWithdrawalRoot[withdrawalRoot];

        // Delete the stored sync values to save gas.
        delete withdrawableSharesByWithdrawalRoot[withdrawalRoot];
        delete maxMagnitudeByWithdrawalRoot[withdrawalRoot];
    }
}
