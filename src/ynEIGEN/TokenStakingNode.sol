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
import {ISignatureUtilsMixinTypes} from "lib/eigenlayer-contracts/src/contracts/interfaces/ISignatureUtilsMixin.sol";
import {IStrategyManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IDelegationManager, IDelegationManagerTypes} from "lib/eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategy} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IRewardsCoordinator} from "lib/eigenlayer-contracts/src/contracts/interfaces/IRewardsCoordinator.sol";
import {IAllocationManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {ITokenStakingNode} from "src/interfaces/ITokenStakingNode.sol";
import {ITokenStakingNodesManager} from "src/interfaces/ITokenStakingNodesManager.sol";
import {IWrapper} from "src/interfaces/IWrapper.sol";
import {IYieldNestStrategyManager} from "src/interfaces/IYieldNestStrategyManager.sol";
import {DelegationManagerStorage} from "lib/eigenlayer-contracts/src/contracts/core/DelegationManagerStorage.sol";
import {IAssetRegistry} from "src/interfaces/IAssetRegistry.sol";

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
    error NotSynchronized();
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

    //--------------------------------------------------------------------------------------
    //----------------------------------  ELIP-002 VARIABLES  ------------------------------
    //--------------------------------------------------------------------------------------

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
    //----------------------------------  STRUCTS  -----------------------------------------
    //--------------------------------------------------------------------------------------

    /**
     * @dev Used in the synchronize function to prevent doing an external call to the allocation manager multiple times for the same operator/strategy pair.
     */
    struct OperatorStrategyPair {
        address operator;
        IStrategy strategy;
        uint64 maxMagnitude;
    }

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
        delegatedTo =
            IDelegationManager(address(tokenStakingNodesManager.delegationManager())).delegatedTo(address(this));
    }

    /**
     * @notice Initializes the contract by storing the pre slashing queued shares.
     */
    function initializeV3() public reinitializer(3) {
        IYieldNestStrategyManager eigenStrategyManager = IYieldNestStrategyManager(tokenStakingNodesManager.yieldNestStrategyManager());
        IAssetRegistry assetRegistry = IAssetRegistry(eigenStrategyManager.ynEigen().assetRegistry());
        IERC20[] memory assets = assetRegistry.getAssets();

        for (uint256 i = 0; i < assets.length; i++) {
            IStrategy strategy = eigenStrategyManager.strategies(assets[i]);
            // Store the value of the queued shares as legacy.
            legacyQueuedShares[strategy] = queuedShares[strategy];
            // Resets the queued shares to 0 as they will only be used to track new queued withdrawals.
            delete queuedShares[strategy];
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

    /**
     * @notice Returns the queued shares and withdrawn balance for a specific strategy and asset.
     * @dev The queued shares are the sum of the legacy queued shares and the post slashing queued shares.
     */
    function getQueuedSharesAndWithdrawn(IStrategy _strategy, IERC20 _asset) external view returns (uint256, uint256) {
        return (legacyQueuedShares[_strategy] + queuedShares[_strategy], withdrawn[_asset]);
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

        DelegationManagerStorage _delegationManager = DelegationManagerStorage(address(tokenStakingNodesManager.delegationManager()));
        // Queue the withdrawals and get the withdrawal root.
        _fullWithdrawalRoots = _delegationManager.queueWithdrawals(_params);
        // Only one withdrawal root is generated given that only 1 strategy is provided.
        bytes32 _withdrawalRoot = _fullWithdrawalRoots[0];
        // Get the withdrawable shares for withdraw.
        // Also, given that only 1 strategy was withdrawn, we can expect the withdrawable shares array to contain only 1 value.
        (, uint256[] memory _singleWithdrawableShares) = _delegationManager.getQueuedWithdrawal(_withdrawalRoot);
        uint256 _withdrawableShares = _singleWithdrawableShares[0];

        // Add the new withdrawn shares to the queued shares mapping.
        queuedShares[_strategy] += _withdrawableShares;
        // Store the current maxMagnitude to verify later if the operator was slashed mid withdrawal.
        maxMagnitudeByWithdrawalRoot[_withdrawalRoot] = _delegationManager.allocationManager().getMaxMagnitude(delegatedTo, _strategy);
        // Store the withdrawable shares for the particular withdrawal root.
        withdrawableSharesByWithdrawalRoot[_withdrawalRoot] = _withdrawableShares;
        // Flags the withdrawal as done after the slashing upgrade.
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
    ) public onlyTokenStakingNodesWithdrawer onlyWhenSynchronized {
        DelegationManagerStorage _delegationManager = DelegationManagerStorage(address(tokenStakingNodesManager.delegationManager()));
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
    ) public onlyTokenStakingNodesWithdrawer onlyWhenSynchronized {
        IDelegationManager.Withdrawal[] memory _withdrawals = new IDelegationManager.Withdrawal[](1);
        _withdrawals[0] = withdrawal;
        completeQueuedWithdrawals(_withdrawals, updateTokenStakingNodesBalances);
    }

    /**
     * @notice Completes queued withdrawals with receiveAsTokens set to false
     * @param withdrawals Array of withdrawals to complete
     */
    function completeQueuedWithdrawalsAsShares(
        IDelegationManager.Withdrawal[] calldata withdrawals
    ) external onlyDelegator onlyWhenSynchronized {
        DelegationManagerStorage _delegationManager = DelegationManagerStorage(address(tokenStakingNodesManager.delegationManager()));
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
    function delegate(address operator, ISignatureUtilsMixinTypes.SignatureWithExpiry memory signature, bytes32 approverSalt)
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
    function isSynchronized() public view returns (bool) {
        IDelegationManager delegationManager = IDelegationManager(address(tokenStakingNodesManager.delegationManager()));
        return delegatedTo == delegationManager.delegatedTo(address(this));
    }

    /**
     * @notice Synchronizes both the delegatedTo address with the DelegationManager and the queued shares.
     * @dev Anyone can call this function because every call is beneficial to the protocol as it keeps accounting in sync.
     */
    function synchronize() public {
        DelegationManagerStorage delegationManager = DelegationManagerStorage(address(tokenStakingNodesManager.delegationManager()));
        IAllocationManager allocationManager = delegationManager.allocationManager();

        // Update the delegatedTo address to the current operator.
        delegatedTo = delegationManager.delegatedTo(address(this));

        // Requests the queued withdrawals and the withdrawable shares of each from the delegation manager.
        (IDelegationManager.Withdrawal[] memory withdrawals, uint256[][] memory withdrawableSharesPerWithdrawal) = delegationManager.getQueuedWithdrawals(address(this));

        // Stores unique strategies to avoid duplicate storage access when resetting queued shares
        IStrategy[] memory uniqueStrategies = new IStrategy[](withdrawals.length);
        uint256 uniqueStrategiesLength = 0;

        // Reset queued shares to 0 for each unique strategy
        for (uint256 i = 0; i < withdrawals.length; i++) {
            IStrategy strategy = withdrawals[i].strategies[0];

            bool alreadyAdded = false;

            // Check if the strategy was already processed
            for (uint256 j = 0; j < uniqueStrategiesLength; j++) {
                if (uniqueStrategies[j] == strategy) {
                    alreadyAdded = true;
                    break;
                }
            }

            // Skip reset if the strategy was already processed
            if (alreadyAdded) {
                continue;
            }

            // Track the strategy as already processed and reset its queuedShares value back to zero.
            uniqueStrategies[uniqueStrategiesLength++] = strategy; 
            delete queuedShares[strategy];
        }

        // Stores unique operator-strategy pairs to avoid duplicate maxMagnitude calls
        OperatorStrategyPair[] memory uniqueOperatorStrategyPairs = new OperatorStrategyPair[](withdrawals.length);
        uint256 uniqueOperatorStrategyPairsLength = 0;

        for (uint256 i = 0; i < withdrawals.length; i++) {
            IDelegationManagerTypes.Withdrawal memory withdrawal = withdrawals[i];
            IStrategy strategy = withdrawal.strategies[0];

            uint256 withdrawableShares = withdrawableSharesPerWithdrawal[i][0];
            bytes32 withdrawalRoot = delegationManager.calculateWithdrawalRoot(withdrawal);

            // Track if this operator-strategy pair was already processed
            bool alreadyAdded = false;
            uint256 alreadyAddedIndex = 0;

            // Look for existing operator-strategy pair
            for (uint256 j = 0; j < uniqueOperatorStrategyPairsLength; j++) {
                OperatorStrategyPair memory pair = uniqueOperatorStrategyPairs[j];

                if (pair.operator == withdrawal.delegatedTo && pair.strategy == strategy) {
                    alreadyAdded = true;
                    alreadyAddedIndex = j;
                    break;
                }
            }

            uint64 maxMagnitude = 0;

            if (!alreadyAdded) {
                // Get and store maxMagnitude for new operator-strategy pair
                maxMagnitude = allocationManager.getMaxMagnitude(withdrawal.delegatedTo, strategy);
                uniqueOperatorStrategyPairs[uniqueOperatorStrategyPairsLength] = OperatorStrategyPair({
                    operator: withdrawal.delegatedTo,
                    strategy: strategy,
                    maxMagnitude: maxMagnitude
                });
                uniqueOperatorStrategyPairsLength++;
            } else {
                // Reuse stored maxMagnitude for existing pair
                maxMagnitude = uniqueOperatorStrategyPairs[alreadyAddedIndex].maxMagnitude;
            }

            // Update the queued shares for the strategy by adding the withdrawable shares.
            queuedShares[strategy] += withdrawableShares;
            
            // Update the withdrawable shares for the withdrawal root.
            if (withdrawableSharesByWithdrawalRoot[withdrawalRoot] != withdrawableShares) {
                withdrawableSharesByWithdrawalRoot[withdrawalRoot] = withdrawableShares;
            }

            // Update the maxMagnitude for the withdrawal root.
            if (maxMagnitudeByWithdrawalRoot[withdrawalRoot] != maxMagnitude) {
                maxMagnitudeByWithdrawalRoot[withdrawalRoot] = maxMagnitude;
            }

            // Flags the withdrawal as post slashing.
            // This is to sync queued withdrawals that were caused by undelegating directly from the DelegationManager.
            if (!queuedAfterSlashingUpgrade[withdrawalRoot]) {
                queuedAfterSlashingUpgrade[withdrawalRoot] = true;
            }
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
    modifier onlyWhenSynchronized() {
        if (!isSynchronized()) {
            revert NotSynchronized();
        }
        _;
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  INTERNAL  ----------------------------------------
    //--------------------------------------------------------------------------------------

    /**
     * @dev Decreases the queued shares by the withdrawable amount after validating if the contract was synchronized after a slashing event.
     * @param _delegationManager The delegation manager contract.
     * @param _allocationManager The allocation manager contract.
     * @param _strategy The strategy to decrease the queued shares for.
     * @param _withdrawal The withdrawal to decrease the queued shares for.
     */
    function _decreaseQueuedSharesOnCompleteWithdrawals(
        DelegationManagerStorage _delegationManager,
        IAllocationManager _allocationManager,
        IStrategy _strategy,
        IDelegationManagerTypes.Withdrawal memory _withdrawal
    ) internal {
        bytes32 withdrawalRoot = _delegationManager.calculateWithdrawalRoot(_withdrawal);

        // If the withdrawal was queued before the upgrade, it is considered legacy.
        if (!queuedAfterSlashingUpgrade[withdrawalRoot]) {
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
        delete queuedAfterSlashingUpgrade[withdrawalRoot];
    }
}
