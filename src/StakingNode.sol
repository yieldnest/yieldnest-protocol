/// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {ReentrancyGuardUpgradeable} from
    "lib/openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import {BeaconChainProofs} from "lib/eigenlayer-contracts/src/contracts/libraries/BeaconChainProofs.sol";
import {IDelegationManagerExtended} from "src/external/eigenlayer/IDelegationManagerExtended.sol";
import {IDelegationManager, IDelegationManagerTypes} from "lib/eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IEigenPodManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IEigenPodManager.sol";
import {IEigenPod} from "lib/eigenlayer-contracts/src/contracts/interfaces/IEigenPod.sol";
import {IRewardsCoordinator} from "lib/eigenlayer-contracts/src/contracts/interfaces/IRewardsCoordinator.sol";
import {ISignatureUtils} from "lib/eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";
import {IStrategy} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IBeacon} from "lib/openzeppelin-contracts/contracts/proxy/beacon/IBeacon.sol";
import {IEigenPodManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IEigenPodManager.sol";
import {IStakingNodesManager} from "src/interfaces/IStakingNodesManager.sol";
import {IStakingNode} from "src/interfaces/IStakingNode.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {SlashingLib} from "lib/eigenlayer-contracts/src/contracts/libraries/SlashingLib.sol";

import {IERC20 as IERC20V4} from "lib/eigenlayer-contracts/lib/openzeppelin-contracts-v4.9.0/contracts/interfaces/IERC20.sol";
import {DEFAULT_VALIDATOR_STAKE} from "src/Constants.sol";

interface StakingNodeEvents {

    event EigenPodCreated(address indexed nodeAddress, address indexed podAddress);
    event Delegated(address indexed operator, bytes32 approverSalt);
    event Undelegated(address indexed operator, int256 shares);
    event NonBeaconChainETHWithdrawalsProcessed(uint256 claimedAmount);
    event ETHReceived(address sender, uint256 value);
    event WithdrawnNonBeaconChainETH(uint256 amount, uint256 remainingBalance);
    event AllocatedStakedETH(uint256 currentUnverifiedStakedETH, uint256 newAmount);
    event DeallocatedStakedETH(uint256 amount, uint256 currentWithdrawnETH);
    event ValidatorRestaked(uint40 indexed validatorIndex, uint64 oracleTimestamp, uint256 effectiveBalanceGwei);
    event VerifyWithdrawalCredentialsCompleted(
        uint40 indexed validatorIndex, uint64 oracleTimestamp, uint256 effectiveBalanceGwei
    );
    event WithdrawalProcessed(
        uint40 indexed validatorIndex,
        uint256 effectiveBalance,
        bytes32 withdrawalCredentials,
        uint256 withdrawalAmount,
        uint64 oracleTimestamp
    );

    event QueuedWithdrawals(uint256 sharesAmount, bytes32[] fullWithdrawalRoots);
    event CompletedQueuedWithdrawals(
        IDelegationManager.Withdrawal[] withdrawals, uint256 totalWithdrawalAmount, uint256 actualWithdrawalAmount
    );
    event ClaimerSet(address indexed claimer);
    event QueuedSharesSynced(uint256 queuedSharesAmount);
}

/**
 * @title StakingNode
 * @dev Implements staking node functionality for the YieldNest protocol, enabling ETH staking, delegation, and rewards management.
 * Each StakingNode owns exactl one EigenPod which acts as a delegation unit, as it can be associated with exactly one operator.
 */
contract StakingNode is IStakingNode, StakingNodeEvents, ReentrancyGuardUpgradeable {

    using BeaconChainProofs for *;
    using SlashingLib for *;

    //--------------------------------------------------------------------------------------
    //----------------------------------  ERRORS  ------------------------------------------
    //--------------------------------------------------------------------------------------

    error NotStakingNodesOperator();
    error ETHDepositorNotEigenPod();
    error ClaimAmountTooLow(uint256 expected, uint256 actual);
    error ZeroAddress();
    error NotStakingNodesManager();
    error NotStakingNodesDelegator();
    error NoBalanceToProcess();
    error MismatchInExpectedETHBalanceAfterWithdrawals(uint256 actualWithdrawalAmount, uint256 totalWithdrawalAmount);
    error TransferFailed();
    error InsufficientWithdrawnETH(uint256 amount, uint256 withdrawnETH);
    error NotStakingNodesWithdrawer();
    error NotSyncedAfterSlashing();

    error NotSynchronized();
    error AlreadySynchronized();
    error WithdrawalMismatch();
    error InvalidWithdrawal();

    //--------------------------------------------------------------------------------------
    //----------------------------------  CONSTANTS  ---------------------------------------
    //--------------------------------------------------------------------------------------

    IStrategy public constant beaconChainETHStrategy = IStrategy(0xbeaC0eeEeeeeEEeEeEEEEeeEEeEeeeEeeEEBEaC0);

    //--------------------------------------------------------------------------------------
    //----------------------------------  VARIABLES  ---------------------------------------
    //--------------------------------------------------------------------------------------

    IStakingNodesManager public stakingNodesManager;
    IEigenPod public eigenPod;
    uint256 public nodeId;

    /**
     * @dev Monitors the ETH balance that was committed to validators allocated to this StakingNode
     */
    uint256 private _unused_former_allocatedETH;

    /**
     * @dev Accounts for withdrawn ETH balance that can be withdrawn by the StakingNodesManager contract
     *         This is made up of both validator principal, rewards and arbitrary ETH sent to the Eigenpod
     *         that are withdrawn from Eigenlayer.
     */
    uint256 public withdrawnETH;

    /**
     * @dev Accounts for ETH staked with validators whose withdrawal address is this Node's eigenPod.
     * that is not yet verified with verifyWithdrawalCredentials.
     * Increases when calling allocateETH, and decreases when verifying with verifyWithdrawalCredentials
     */
    uint256 public unverifiedStakedETH;

    /**
     * @dev Amount of shares queued for withdrawal (no longer active in staking). 1 share == 1 ETH.
     * Increases when calling queueWithdrawals, and decreases when calling completeQueuedWithdrawals and on slashing
     */
    uint256 public queuedSharesAmount;

    /**
     * @dev The address of the operator that this staking node is delegated to.
     */
    address public delegatedTo;

    /**
     * @dev The amount of shares queued for withdrawal that were queued before the eigenlayer ELIP-002 upgrade
     */
    uint256 public preELIP002QueuedSharesAmount;

    /**
     * @dev Maps a withdrawal root to the amount of shares that can be withdrawn and whether the withdrawal root is post ELIP-002 slashing upgrade.
     * This is used to track the amount of withdrawable shares that are queued for withdrawal.
     */
    mapping(bytes32 withdrawalRoot => WithdrawableShareInfo withdrawableShareInfo) public withdrawableShareInfo;

    /** 
     * @dev Allows only a whitelisted address to configure the contract 
     */
    modifier onlyOperator() {
        if (!stakingNodesManager.isStakingNodesOperator(msg.sender)) revert NotStakingNodesOperator();
        _;
    }

    modifier onlyDelegator() {
        if (!stakingNodesManager.isStakingNodesDelegator(msg.sender)) revert NotStakingNodesDelegator();
        _;
    }

    modifier onlyStakingNodesManager() {
        if (msg.sender != address(stakingNodesManager)) revert NotStakingNodesManager();
        _;
    }

    modifier onlyStakingNodesWithdrawer() {
        if (!stakingNodesManager.isStakingNodesWithdrawer(msg.sender)) revert NotStakingNodesWithdrawer();
        _;
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  INITIALIZATION  ----------------------------------
    //--------------------------------------------------------------------------------------

    receive() external payable {
        // Consensus Layer rewards and the validator principal will be sent this way.
        if (msg.sender != address(eigenPod)) revert ETHDepositorNotEigenPod();
        emit ETHReceived(msg.sender, msg.value);
    }

    constructor() {
        _disableInitializers();
    }

    function initialize(
        Init memory init
    ) external notZeroAddress(address(init.stakingNodesManager)) initializer {
        __ReentrancyGuard_init();

        stakingNodesManager = init.stakingNodesManager;
        nodeId = init.nodeId;
    }

    function initializeV2(
        uint256 initialUnverifiedStakedETH
    ) external onlyStakingNodesManager reinitializer(2) {
        unverifiedStakedETH = initialUnverifiedStakedETH;
    }

    function initializeV3() external onlyStakingNodesManager reinitializer(3) {
        delegatedTo = stakingNodesManager.delegationManager().delegatedTo(address(this));
    }
    
    function initializeV4() external onlyStakingNodesManager reinitializer(4) {
        preELIP002QueuedSharesAmount = queuedSharesAmount;
        queuedSharesAmount = 0;
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  EIGENPOD CREATION   ------------------------------
    //--------------------------------------------------------------------------------------

    /**
     * @notice Creates an EigenPod if it does not already exist for this StakingNode.
     * @dev If it does not exist, it proceeds to create a new EigenPod via EigenPodManager
     * @return The address of the EigenPod associated with this StakingNode.
     */
    function createEigenPod() public nonReentrant returns (IEigenPod) {
        if (address(eigenPod) != address(0)) return eigenPod; // already have pod

        IEigenPodManager eigenPodManager = IEigenPodManager(IStakingNodesManager(stakingNodesManager).eigenPodManager());
        eigenPodManager.createPod();
        eigenPod = eigenPodManager.getPod(address(this));
        emit EigenPodCreated(address(this), address(eigenPod));

        return eigenPod;
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  VERIFICATION AND DELEGATION   --------------------
    //--------------------------------------------------------------------------------------

    /**
     * @dev Validates the withdrawal credentials for a withdrawal.
     * This activates the staked funds within EigenLayer as shares.
     * verifyWithdrawalCredentials MUST be called for all validators BEFORE they
     * are exited from the beacon chain to keep the getETHBalance return value consistent.
     * If a validator is exited without this call, TVL is double counted for its principal.
     * @param beaconTimestamp The timestamp of the oracle that signed the block.
     * @param stateRootProof The state root proof.
     * @param validatorIndices The indices of the validators.
     * @param validatorFieldsProofs The validator fields proofs.
     * @param validatorFields The validator fields.
     */
    function verifyWithdrawalCredentials(
        uint64 beaconTimestamp,
        BeaconChainProofs.StateRootProof calldata stateRootProof,
        uint40[] calldata validatorIndices,
        bytes[] calldata validatorFieldsProofs,
        bytes32[][] calldata validatorFields
    ) external onlyOperator onlyWhenSynchronized {
        IEigenPod(address(eigenPod)).verifyWithdrawalCredentials(
            beaconTimestamp, stateRootProof, validatorIndices, validatorFieldsProofs, validatorFields
        );

        for (uint256 i = 0; i < validatorIndices.length; i++) {
            // If the validator is already exited, the effectiveBalanceGwei is 0.
            // if the validator has not been exited, the effectiveBalanceGwei is whatever is staked
            // (32ETH in the absence of slasing, and less than that if slashed)
            uint256 effectiveBalanceGwei = validatorFields[i].getEffectiveBalanceGwei();

            emit VerifyWithdrawalCredentialsCompleted(validatorIndices[i], beaconTimestamp, effectiveBalanceGwei);

            // If the effectiveBalanceGwei is not 0, then the full stake of the validator
            // is verified as part of this process and shares are credited to this StakingNode instance.
            // verifyWithdrawalCredentials can only be called for non-exited validators
            // This assumes StakingNodesManager.sol always stakes the full 32 ETH in one go.
            // effectiveBalanceGwei *may* be less than DEFAULT_VALIDATOR_STAKE if the validator was slashed.
            unverifiedStakedETH -= DEFAULT_VALIDATOR_STAKE;

            emit ValidatorRestaked(validatorIndices[i], beaconTimestamp, effectiveBalanceGwei);
        }
    }

    /**
     * @dev Create a checkpoint used to prove the pod's active validator set.
     * This function can only be called by the Operator.
     * @param revertIfNoBalance Forces a revert if the pod ETH balance is 0.
     */
    function startCheckpoint(
        bool revertIfNoBalance
    ) external onlyOperator {
        eigenPod.startCheckpoint(revertIfNoBalance);
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  DELEGATION   -------------------------------------
    //--------------------------------------------------------------------------------------

    /**
     * @notice Delegates authority to an operator.
     * @dev Delegates the staking node's authority to an operator using a signature with expiry.
     * @param operator The address of the operator to whom the delegation is made.
     * @param approverSignatureAndExpiry The signature of the approver along with its expiry details.
     * @param approverSalt The unique salt used to prevent replay attacks.
     */
    function delegate(
        address operator,
        ISignatureUtils.SignatureWithExpiry memory approverSignatureAndExpiry,
        bytes32 approverSalt
    ) public override onlyDelegator onlyWhenSynchronized {
        IDelegationManager delegationManager = stakingNodesManager.delegationManager();
        delegationManager.delegateTo(operator, approverSignatureAndExpiry, approverSalt);

        delegatedTo = operator;

        emit Delegated(operator, approverSalt);
    }

    /**
     * @notice Undelegates the authority previously delegated to an operator.
     * @dev This function revokes the delegation by calling the `undelegate` method on the `DelegationManager`.
     * It emits an `Undelegated` event with the address of the operator from whom the delegation is being removed.
     */
    function undelegate() public onlyDelegator onlyWhenSynchronized returns (bytes32[] memory withdrawalRoots) {
        IDelegationManager delegationManager = stakingNodesManager.delegationManager();

        address operator = delegationManager.delegatedTo(address(this));

        IStrategy[] memory strategies = new IStrategy[](1);
        strategies[0] = beaconChainETHStrategy;

        (uint256[] memory withdrawableShares, ) = delegationManager.getWithdrawableShares(address(this), strategies);

        withdrawalRoots = delegationManager.undelegate(address(this));

        syncQueuedShares();

        delegatedTo = address(0);

        emit Undelegated(operator, int256(withdrawableShares[0]));
    }

    /**
     * @notice Sets the claimer for rewards using the rewards coordinator
     * @dev Only callable by delegator. Sets the claimer address for this staking node's rewards.
     * @param claimer The address to set as the claimer
     */
    function setClaimer(
        address claimer
    ) external onlyDelegator {
        IRewardsCoordinator rewardsCoordinator = stakingNodesManager.rewardsCoordinator();
        rewardsCoordinator.setClaimerFor(claimer);
        emit ClaimerSet(claimer);
    }

    /**
     * @notice Syncs the queuedSharesAmount with the actual withdrawable shares queued for withdrawal.
     * @dev This is generally used when slashing is done on this staking node or operator is slashed
     */
    function syncQueuedShares() public {

        IDelegationManager delegationManager = stakingNodesManager.delegationManager();
        // This is used to track the amount of withdrawable shares that are queued for withdrawal.
        uint256 queuedWithdrawableShares = 0; 

        (IDelegationManagerTypes.Withdrawal[] memory withdrawals, uint256[][] memory shares) = delegationManager.getQueuedWithdrawals(address(this));
        for(uint256 i = 0; i < withdrawals.length; i++) {
            bytes32 withdrawalRoot = delegationManager.calculateWithdrawalRoot(withdrawals[i]);
            uint256 withdrawableShares = shares[i][0];
            withdrawableShareInfo[withdrawalRoot] = WithdrawableShareInfo({
                withdrawableShares: withdrawableShares,
                postELIP002SlashingUpgrade: true
            });
            queuedWithdrawableShares += withdrawableShares;
        }

        // updating queuedSharesAmount due to sync 
        queuedSharesAmount = queuedWithdrawableShares;
        
        emit QueuedSharesSynced(queuedWithdrawableShares + preELIP002QueuedSharesAmount);
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  WITHDRAWALS  -------------------------------------
    //--------------------------------------------------------------------------------------

    /**
     * @dev Queues a validator Principal withdrawal for processing. DelegationManager calls EigenPodManager.decreasesShares
     * which decreases the `podOwner`'s shares by `depositSharesAmount`, down to a minimum of zero. The actual shares withdrawable
     * will be less than `depositSharesAmount` depending on the slashing factor
     * @param depositSharesAmount The amount of deposit shares to be queued for withdrawals.
     * @return fullWithdrawalRoots An array of keccak256 hashes of each withdrawal created.
     */
    function queueWithdrawals(
        uint256 depositSharesAmount
    ) external onlyStakingNodesWithdrawer onlyWhenSynchronized returns (bytes32[] memory) {

        IDelegationManager delegationManager = stakingNodesManager.delegationManager();

        IDelegationManagerTypes.QueuedWithdrawalParams[] memory params = new IDelegationManagerTypes.QueuedWithdrawalParams[](1);
        IStrategy[] memory strategies = new IStrategy[](1);

        // Assumption: 1 Share of beaconChainETHStrategy = 1 ETH.
        uint256[] memory shares = new uint256[](1);

        strategies[0] = beaconChainETHStrategy;
        shares[0] = depositSharesAmount;
        // The delegationManager requires the withdrawer == msg.sender (the StakingNode in this case).
        params[0] = IDelegationManagerTypes.QueuedWithdrawalParams({
            strategies: strategies,
            depositShares: shares,
            __deprecated_withdrawer: address(this)
        });
        uint256[] memory withdrawableShares;
        // fullWithdrawalRoots will be of length 1 because there is only one strategy
        bytes32[] memory fullWithdrawalRoots = delegationManager.queueWithdrawals(params);

        (, withdrawableShares) = delegationManager.getQueuedWithdrawal(fullWithdrawalRoots[0]);
    
        // After running queueWithdrawals, eigenPodManager.getWithdrawableShares(address(this)) decreases by `withdrawableShares`.
        // Therefore queuedSharesAmount increase by `withdrawableShares`.
        queuedSharesAmount += withdrawableShares[0];
        withdrawableShareInfo[fullWithdrawalRoots[0]] = WithdrawableShareInfo({
            withdrawableShares: withdrawableShares[0],
            postELIP002SlashingUpgrade: true
        });
        emit QueuedWithdrawals(depositSharesAmount, fullWithdrawalRoots);

        return fullWithdrawalRoots;
    }

    /**
     * @dev Triggers the completion of particular queued withdrawals.
     *      Withdrawals can only be completed if
     *      max(delegationManager.minWithdrawalDelayBlocks(), delegationManager.strategyWithdrawalDelayBlocks(beaconChainETHStrategy))
     *      number of blocks have passed since withdrawal was queued.
     * @param withdrawals The Withdrawals to complete. This withdrawalRoot (keccak hash of the Withdrawal) must match the
     *                    the withdrawal created as part of the queueWithdrawals call.
     */
    function completeQueuedWithdrawals(
        IDelegationManager.Withdrawal[] calldata withdrawals
    ) external onlyStakingNodesWithdrawer onlyWhenSynchronized {

        IDelegationManager delegationManager = stakingNodesManager.delegationManager();

        bool[] memory receiveAsTokens = new bool[](withdrawals.length);
        IERC20V4[][] memory tokens = new IERC20V4[][](withdrawals.length);
        uint256 totalWithdrawableShares = 0;
        for (uint256 i = 0; i < withdrawals.length; i++) {
            if (withdrawals[i].scaledShares.length != 1 || withdrawals[i].strategies.length != 1 || withdrawals[i].strategies[0] != beaconChainETHStrategy) {
                revert InvalidWithdrawal();
            }
            // Set receiveAsTokens to true to receive ETH when completeQueuedWithdrawals runs.
            ///IMPORTANT: beaconChainETHStrategy shares are non-transferrable, so if `receiveAsTokens = false`
            // and `withdrawal.withdrawer != withdrawal.staker`, any beaconChainETHStrategy shares
            // in the `withdrawal` will be _returned to the staker_, rather than transferred to the withdrawer,
            // unlike shares in any other strategies, which will be transferred to the withdrawer.
            receiveAsTokens[i] = true;

            // tokens array must match length of the withdrawals[i].strategies
            // but does not need actual values in the case of the beaconChainETHStrategy
            tokens[i] = new IERC20V4[](1);
            
            bytes32 withdrawalRoot = delegationManager.calculateWithdrawalRoot(withdrawals[i]);

            totalWithdrawableShares += _decreaseQueuedSharesOnCompleteQueuedWithdrawal(delegationManager, withdrawals[i]);
        }

        uint256 initialETHBalance = address(this).balance;

        // NOTE:  completeQueuedWithdrawals can only be called by withdrawal.withdrawer for each withdrawal
        // The Eigenlayer beaconChainETHStrategy  queued withdrawal completion flow follows the following steps:
        // 1. The flow starts in the DelegationManager where queued withdrawals are managed.
        // 2. For beaconChainETHStrategy, the DelegationManager calls _withdrawSharesAsTokens interacts with the EigenPodManager.withdrawSharesAsTokens
        // 3. Finally, the EigenPodManager calls withdrawRestakedBeaconChainETH on the EigenPod of this StakingNode to finalize the withdrawal.
        // 4. the EigenPod decrements withdrawableRestakedExecutionLayerGwei and send the ETH to address(this)
        delegationManager.completeQueuedWithdrawals(withdrawals, tokens, receiveAsTokens);

        uint256 finalETHBalance = address(this).balance;
        uint256 actualWithdrawalAmount = finalETHBalance - initialETHBalance;

        if (actualWithdrawalAmount != totalWithdrawableShares) {
            revert NotSyncedAfterSlashing();
        }

        // Withdraw validator principal resides in the StakingNode until StakingNodesManager retrieves it.
        withdrawnETH += actualWithdrawalAmount;

        emit CompletedQueuedWithdrawals(withdrawals, totalWithdrawableShares, actualWithdrawalAmount);
    }

    /**
     * @notice Completes queued withdrawals with receiveAsTokens set to false
     * @dev Call updateTotalETHStaked after this function
     * @param withdrawals Array of withdrawals to complete
     */
    function completeQueuedWithdrawalsAsShares(
        IDelegationManager.Withdrawal[] calldata withdrawals
    ) external onlyDelegator onlyWhenSynchronized {

        syncQueuedShares();

        uint256 totalWithdrawableShares = 0;

        IDelegationManager delegationManager = stakingNodesManager.delegationManager();

        // Create empty tokens array since we're not receiving as tokens
        IERC20V4[][] memory tokens = new IERC20V4[][](withdrawals.length);
        bool[] memory receiveAsTokens = new bool[](withdrawals.length);

        // Calculate total shares being withdrawn
        for (uint256 i = 0; i < withdrawals.length; i++) {
            if (withdrawals[i].scaledShares.length != 1 || withdrawals[i].strategies.length != 1 || withdrawals[i].strategies[0] != beaconChainETHStrategy) {
                revert InvalidWithdrawal();
            }
            tokens[i] = new IERC20V4[](1);
            receiveAsTokens[i] = false;
            
            totalWithdrawableShares += _decreaseQueuedSharesOnCompleteQueuedWithdrawal(delegationManager, withdrawals[i]);
        }

        // Complete withdrawals with receiveAsTokens = false
        delegationManager.completeQueuedWithdrawals(
            withdrawals, 
            tokens, 
            receiveAsTokens
        );

        emit CompletedQueuedWithdrawals(withdrawals, totalWithdrawableShares, 0);
    }

    /**
     * @notice Decreases the queued shares on complete queued withdrawals and returns the total withdrawable shares
     * @param delegationManager The delegation manager
     * @param withdrawal The withdrawal struct
     * @return totalWithdrawableShare The total withdrawable shares for the withdrawal struct
     */
    function _decreaseQueuedSharesOnCompleteQueuedWithdrawal(
        IDelegationManager delegationManager,
        IDelegationManager.Withdrawal calldata withdrawal
    ) internal returns (uint256 totalWithdrawableShare) {

        bytes32 withdrawalRoot = delegationManager.calculateWithdrawalRoot(withdrawal);
        WithdrawableShareInfo storage withdrawableShareInfo = withdrawableShareInfo[withdrawalRoot];

        if (withdrawableShareInfo.postELIP002SlashingUpgrade) {
            // If the withdrawal root queued after ELIP-002 slashing upgrade, we need to subtract the shares from queuedSharesAmount 
            // and set the withdrawableShares to 0 for the withdrawal root
            totalWithdrawableShare = withdrawableShareInfo.withdrawableShares;
            queuedSharesAmount -= totalWithdrawableShare;
            withdrawableShareInfo.withdrawableShares = 0;
        } else {
            // If the withdrawal root queued was before ELIP-002 slashing upgrade, we need to subtract the shares from preELIP002QueuedSharesAmount 
            totalWithdrawableShare = withdrawal.scaledShares[0];
            preELIP002QueuedSharesAmount -= totalWithdrawableShare;
        }
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
        IDelegationManager delegationManager = stakingNodesManager.delegationManager();
        return delegatedTo == delegationManager.delegatedTo(address(this));
    }

    /**
     * @notice Synchronizes the StakingNode's delegation state with the DelegationManager and queued shares.
     * @dev This function should be called after operator undelegate to this StakingNode or there is slashing event.
     */
    function synchronize() public onlyDelegator {

        syncQueuedShares();

        IDelegationManager delegationManager = stakingNodesManager.delegationManager();
        delegatedTo = delegationManager.delegatedTo(address(this));
        stakingNodesManager.updateTotalETHStaked();
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  ETH BALANCE ACCOUNTING  --------------------------
    //--------------------------------------------------------------------------------------

    /**
     * @dev Record total staked ETH for this StakingNode
     */
    function allocateStakedETH(
        uint256 amount
    ) external onlyStakingNodesManager {
        emit AllocatedStakedETH(unverifiedStakedETH, amount);

        unverifiedStakedETH += amount;
    }

    /**
     * @notice Deallocates a specified amount of staked ETH from the withdrawn validator principal
     *          and transfers it to the StakingNodesManager.
     * @dev This function can only be called by the StakingNodesManager. It emits a DeallocatedStakedETH
     *      event upon successful deallocation.
     * @param amount The amount of ETH to deallocate and transfer.
     */
    function deallocateStakedETH(
        uint256 amount
    ) external onlyStakingNodesManager {
        uint256 _withdrawnETH = withdrawnETH;
        if (amount > _withdrawnETH) revert InsufficientWithdrawnETH(amount, _withdrawnETH);

        emit DeallocatedStakedETH(amount, _withdrawnETH);

        withdrawnETH -= amount;

        (bool success,) = address(stakingNodesManager).call{value: amount}("");
        if (!success) revert TransferFailed();
    }
    
    /**
     * @notice Calculates the total ETH balance of the StakingNode
     * @dev This function aggregates all forms of ETH associated with this StakingNode:
     *      1. withdrawnETH - ETH that has been withdrawn from Eigenlayer and is held by this contract
     *      2. unverifiedStakedETH - ETH staked with validators but not yet verified with withdrawal credentials
     *      3. queuedSharesAmount - Shares queued for withdrawal after ELIP-002 upgrade (1 share = 1 ETH)
     *      4. preELIP002QueuedSharesAmount - Shares queued before the ELIP-002 upgrade (1 share = 1 ETH)
     *      5. Active withdrawable shares in Eigenlayer - Representing staked ETH that can be withdrawn (1 share = 1 ETH)
     * @return The total ETH balance in wei, or 0 if the calculation results in a negative value
     */
    function getETHBalance() public view returns (uint256) {
        IDelegationManager delegationManager = stakingNodesManager.delegationManager();
        IStrategy[] memory strategies = new IStrategy[](1);
        strategies[0] = beaconChainETHStrategy;

        (uint256[] memory withdrawableShares, ) = delegationManager.getWithdrawableShares(address(this), strategies);
        uint256 beaconChainETHStrategyWithdrawableShares = withdrawableShares[0];
    
        // Compute the total ETH balance of the StakingNode
        int256 totalETHBalance =
            int256(withdrawnETH + unverifiedStakedETH + queuedSharesAmount + preELIP002QueuedSharesAmount + beaconChainETHStrategyWithdrawableShares);

        if (totalETHBalance < 0) {
            return 0;
        }
        return uint256(totalETHBalance);
    }

    /**
     * @notice Retrieves the amount of unverified staked ETH held by this StakingNode.
     * @return The amount of unverified staked ETH in wei.
     */
    function getUnverifiedStakedETH() public view returns (uint256) {
        return unverifiedStakedETH;
    }

    /**
     * @notice Retrieves the amount of shares currently queued for withdrawal.
     * @return The amount of queued shares.
     */
    function getQueuedSharesAmount() public view returns (uint256) {
        return queuedSharesAmount;
    }

    /**
     * @notice Retrieves the amount of ETH that has been withdrawn from Eigenlayer and is held by this StakingNode.
     *            Composed of validator principal, validator staking rewards and arbitrary ETH sent to the Eigenpod.
     * @return The amount of withdrawn ETH.
     */
    function getWithdrawnETH() public view returns (uint256) {
        return withdrawnETH;
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

    /**
     * @notice Retrieve the version number of the highest/newest initialize
     *         function that was executed.
     */
    function getInitializedVersion() external view returns (uint64) {
        return _getInitializedVersion();
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  MODIFIERS  ---------------------------------------
    //--------------------------------------------------------------------------------------

    /**
     * @notice Ensure that the given address is not the zero address.
     * @param _address The address to check.
     */
    modifier notZeroAddress(
        address _address
    ) {
        if (_address == address(0)) revert ZeroAddress();
        _;
    }

    modifier onlyWhenSynchronized() {
        if (!isSynchronized()) revert NotSynchronized();
        _;
    }

}
