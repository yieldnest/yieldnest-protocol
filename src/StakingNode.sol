/// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {ReentrancyGuardUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import {BeaconChainProofs} from "lib/eigenlayer-contracts/src/contracts/libraries/BeaconChainProofs.sol";
import {IDelegationManager } from "lib/eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IEigenPodManager } from "lib/eigenlayer-contracts/src/contracts/interfaces/IEigenPodManager.sol";
import {IEigenPod } from "lib/eigenlayer-contracts/src/contracts/interfaces/IEigenPod.sol";
import {ISignatureUtils} from "lib/eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";
import {IStrategy} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IBeacon} from "lib/openzeppelin-contracts/contracts/proxy/beacon/IBeacon.sol";
import {IEigenPodManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IEigenPodManager.sol";
import {IStakingNodesManager} from "src/interfaces/IStakingNodesManager.sol";
import {IStakingNode} from "src/interfaces/IStakingNode.sol";
import {RewardsType} from "src/interfaces/IRewardsDistributor.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {ONE_GWEI, DEFAULT_VALIDATOR_STAKE} from "src/Constants.sol";

interface StakingNodeEvents {
     event EigenPodCreated(address indexed nodeAddress, address indexed podAddress);   
     event Delegated(address indexed operator, bytes32 approverSalt);
     event Undelegated(address indexed operator);
     event NonBeaconChainETHWithdrawalsProcessed(uint256 claimedAmount);
     event ETHReceived(address sender, uint256 value);
     event WithdrawnNonBeaconChainETH(uint256 amount, uint256 remainingBalance);
     event AllocatedStakedETH(uint256 currentUnverifiedStakedETH, uint256 newAmount);
     event DeallocatedStakedETH(uint256 amount, uint256 currentWithdrawnValidatorPrincipal);
     event ValidatorRestaked(uint40 indexed validatorIndex, uint64 oracleTimestamp, uint256 effectiveBalanceGwei);
     event VerifyWithdrawalCredentialsCompleted(uint40 indexed validatorIndex, uint64 oracleTimestamp, uint256 effectiveBalanceGwei);
     event WithdrawalProcessed(
        uint40 indexed validatorIndex,
        uint256 effectiveBalance,
        bytes32 withdrawalCredentials,
        uint256 withdrawalAmount,
        uint64 oracleTimestamp
    );

    event QueuedWithdrawals(uint256 sharesAmount, bytes32[] fullWithdrawalRoots);
    event CompletedQueuedWithdrawals(IDelegationManager.Withdrawal[] withdrawals, uint256 totalWithdrawalAmount);
}

/**
 * @title StakingNode
 * @dev Implements staking node functionality for the YieldNest protocol, enabling ETH staking, delegation, and rewards management.
 * Each StakingNode owns exactl one EigenPod which acts as a delegation unit, as it can be associated with exactly one operator.
 */
contract StakingNode is IStakingNode, StakingNodeEvents, ReentrancyGuardUpgradeable {
    using BeaconChainProofs for *;

    //--------------------------------------------------------------------------------------
    //----------------------------------  ERRORS  ------------------------------------------
    //--------------------------------------------------------------------------------------

    error NotStakingNodesOperator();
    error ETHDepositorNotDelayedWithdrawalRouterOrEigenPod();
    error ClaimAmountTooLow(uint256 expected, uint256 actual);
    error ZeroAddress();
    error NotStakingNodesManager();
    error NotStakingNodesDelegator();
    error NoBalanceToProcess();
    error MismatchInExpectedETHBalanceAfterWithdrawals(uint256 actualWithdrawalAmount, uint256 totalWithdrawalAmount);
    error TransferFailed();
    error InsufficientWithdrawnValidatorPrincipal(uint256 amount, uint256 withdrawnValidatorPrincipal);
    error NotStakingNodesWithdrawer();

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

    /** @dev Monitors the ETH balance that was committed to validators allocated to this StakingNode */
    uint256 private _unused_former_allocatedETH;

    /** @dev Accounts for withdrawn ETH balance that can be withdrawn by the StakingNodesManager contract */
    uint256 public withdrawnValidatorPrincipal;

    /** 
     * @dev Accounts for ETH staked with validators whose withdrawal address is this Node's eigenPod.
     * that is not yet verified with verifyWithdrawalCredentials.
     * Increases when calling allocateETH, and decreases when verifying with verifyWithdrawalCredentials
     */
    uint256 public unverifiedStakedETH;

    /** 
     * @dev Amount of shares queued for withdrawal (no longer active in staking). 1 share == 1 ETH.
     * Increases when calling queueWithdrawals, and decreases when calling completeQueuedWithdrawals.
     */
    uint256 public queuedSharesAmount;

    /** @dev Allows only a whitelisted address to configure the contract */
    modifier onlyOperator() {
        if(!stakingNodesManager.isStakingNodesOperator(msg.sender)) revert NotStakingNodesOperator();
        _;
    }

    modifier onlyDelegator() {
        if (!stakingNodesManager.isStakingNodesDelegator(msg.sender)) revert NotStakingNodesDelegator();
        _;
    }

    modifier onlyStakingNodesManager() {
        if(msg.sender != address(stakingNodesManager)) revert NotStakingNodesManager();
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
    //    if (msg.sender != address(stakingNodesManager.delayedWithdrawalRouter())
    //         && msg.sender != address(eigenPod)) {
    //         revert ETHDepositorNotDelayedWithdrawalRouterOrEigenPod();
    //    }
       emit ETHReceived(msg.sender, msg.value);
    }

    constructor() {
       _disableInitializers();
    }

    function initialize(Init memory init)
        external
        notZeroAddress(address(init.stakingNodesManager))
        initializer {
        __ReentrancyGuard_init();

        stakingNodesManager = init.stakingNodesManager;
        nodeId = init.nodeId;
    }

    function initializeV2(uint256 initialUnverifiedStakedETH) external onlyStakingNodesManager reinitializer(2) {
        unverifiedStakedETH = initialUnverifiedStakedETH;
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
    //----------------------------------  EXPEDITED WITHDRAWAL   ---------------------------
    //--------------------------------------------------------------------------------------

    /**
     * @notice Processes withdrawals by verifying the node's balance and transferring ETH to the StakingNodesManager.
     * @dev This function checks if the node's current balance matches the expected balance and then transfers the ETH to the StakingNodesManager.
     */
    function processDelayedWithdrawals() public nonReentrant onlyOperator {

        // Delayed withdrawals that do not count as validator principal are handled as rewards
        uint256 balance = address(this).balance - withdrawnValidatorPrincipal;
        if (balance == 0) {
            revert NoBalanceToProcess();
        }
        stakingNodesManager.processRewards{value: balance}(nodeId, RewardsType.ConsensusLayer);
        emit NonBeaconChainETHWithdrawalsProcessed(balance);
    }


    //--------------------------------------------------------------------------------------
    //----------------------------------  VERIFICATION AND DELEGATION   --------------------
    //--------------------------------------------------------------------------------------
    
    /**
     * @dev Validates the withdrawal credentials for a withdrawal.
     * This activates the activation of the staked funds within EigenLayer.
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
    ) external onlyOperator {

        IEigenPod(address(eigenPod)).verifyWithdrawalCredentials(
            beaconTimestamp,
            stateRootProof,
            validatorIndices,
            validatorFieldsProofs,
            validatorFields
        );

        for (uint256 i = 0; i < validatorIndices.length; i++) {
            // If the validator is already exited, the effectiveBalanceGwei is 0.
            // if the validator has not been exited, the effectiveBalanceGwei is whatever is staked
            // (32ETH in the absence of slasing, and less than that if slashed)
            uint256 effectiveBalanceGwei = validatorFields[i].getEffectiveBalanceGwei();

            emit VerifyWithdrawalCredentialsCompleted(validatorIndices[i], beaconTimestamp, effectiveBalanceGwei);
            
            // If the effectiveBalanceGwei is not 0, then the full stake of the validator
            // is verified as part of this process and shares are credited to this StakingNode instance.
            // This assumes StakingNodesManager.sol always stakes the full 32 ETH in one go.
            // effectiveBalanceGwei *may* be less than DEFAULT_VALIDATOR_STAKE if the validator was slashed.
            unverifiedStakedETH -= DEFAULT_VALIDATOR_STAKE;

            emit ValidatorRestaked(validatorIndices[i], beaconTimestamp, effectiveBalanceGwei);
        }
    }

    
    /**
     * @dev Sets the proof submitter for the EigenPod associated with this StakingNode.
     * This function can only be called by the StakingNodesManager.
     * @param submitter The address of the new proof submitter.
     */
    function setProofSubmitter(address submitter) external onlyOperator {
        eigenPod.setProofSubmitter(submitter);
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
    ) public override onlyDelegator {

        IDelegationManager delegationManager = IDelegationManager(address(stakingNodesManager.delegationManager()));
        delegationManager.delegateTo(operator, approverSignatureAndExpiry, approverSalt);

        emit Delegated(operator, approverSalt);
    }

    /**
     * @notice Undelegates the authority previously delegated to an operator.
     * @dev This function revokes the delegation by calling the `undelegate` method on the `DelegationManager`.
     * It emits an `Undelegated` event with the address of the operator from whom the delegation is being removed.
     */
    function undelegate() public onlyDelegator {
   
        IDelegationManager delegationManager = IDelegationManager(address(stakingNodesManager.delegationManager()));

        address operator = delegationManager.delegatedTo(address(this));
        emit Undelegated(operator);

        delegationManager.undelegate(address(this));
 
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  WITHDRAWALS  -------------------------------------
    //--------------------------------------------------------------------------------------

    /**
     * @dev Queues a validator Principal withdrawal for processing. DelegationManager calls EigenPodManager.decreasesShares
     * which decreases the `podOwner`'s shares by `shares`, down to a minimum of zero.
     * @param sharesAmount The amount of shares to be queued for withdrawals.
     * @return fullWithdrawalRoots An array of keccak256 hashes of each withdrawal created.
     */
    function queueWithdrawals(
        uint256 sharesAmount
    ) external onlyStakingNodesWithdrawer returns (bytes32[] memory fullWithdrawalRoots) {

        IDelegationManager delegationManager = IDelegationManager(address(stakingNodesManager.delegationManager()));

        IDelegationManager.QueuedWithdrawalParams[] memory params = new IDelegationManager.QueuedWithdrawalParams[](1);
        IStrategy[] memory strategies = new IStrategy[](1);

        // Assumption: 1 Share of beaconChainETHStrategy = 1 ETH.
        uint256[] memory shares = new uint256[](1);

        strategies[0] = beaconChainETHStrategy;
        shares[0] = sharesAmount;
        // The delegationManager requires the withdrawer == msg.sender (the StakingNode in this case).
        params[0] = IDelegationManager.QueuedWithdrawalParams({
            strategies: strategies,
            shares: shares,
            withdrawer: address(this)
        });

        fullWithdrawalRoots = delegationManager.queueWithdrawals(params);
        
        // After running queueWithdrawals, eigenPodManager.podOwnerShares(address(this)) decreases by `sharesAmount`.
        // Therefore queuedSharesAmount increase by `sharesAmount`.

        queuedSharesAmount += sharesAmount;
        emit QueuedWithdrawals(sharesAmount, fullWithdrawalRoots);
    }

    /**
     * @dev Triggers the completion of particular queued withdrawals.
     *      Withdrawals can only be completed if
     *      max(delegationManager.minWithdrawalDelayBlocks(), delegationManager.strategyWithdrawalDelayBlocks(beaconChainETHStrategy))
     *      number of blocks have passed since withdrawal was queued.
     * @param withdrawals The Withdrawals to complete. This withdrawalRoot (keccak hash of the Withdrawal) must match the 
     *                    the withdrawal created as part of the queueWithdrawals call.
     * @param middlewareTimesIndexes The middlewareTimesIndex parameter has to do
     *       with the Slasher, which currently does nothing. As of M2, this parameter
     *       has no bearing on anything and can be ignored
     */
    function completeQueuedWithdrawals(
        IDelegationManager.Withdrawal[] memory withdrawals,
        uint256[] memory middlewareTimesIndexes
        ) external onlyStakingNodesWithdrawer {

        uint256 totalWithdrawalAmount = 0;

        bool[] memory receiveAsTokens = new bool[](withdrawals.length);
        IERC20[][] memory tokens = new IERC20[][](withdrawals.length);
        for (uint256 i = 0; i < withdrawals.length; i++) {

            // Set receiveAsTokens to true to receive ETH when completeQueuedWithdrawals runs.
            ///IMPORTANT: beaconChainETHStrategy shares are non-transferrable, so if `receiveAsTokens = false`
            // and `withdrawal.withdrawer != withdrawal.staker`, any beaconChainETHStrategy shares
            // in the `withdrawal` will be _returned to the staker_, rather than transferred to the withdrawer,
            // unlike shares in any other strategies, which will be transferred to the withdrawer.
            receiveAsTokens[i] = true;

            // tokens array must match length of the withdrawals[i].strategies
            // but does not need actual values in the case of the beaconChainETHStrategy
            tokens[i] = new IERC20[](withdrawals[i].strategies.length);

            for (uint256 j = 0; j < withdrawals[i].shares.length; j++) {
                totalWithdrawalAmount += withdrawals[i].shares[j];
            }
        }

        IDelegationManager delegationManager = IDelegationManager(address(stakingNodesManager.delegationManager()));

        uint256 initialETHBalance = address(this).balance;

        // NOTE:  completeQueuedWithdrawals can only be called by withdrawal.withdrawer for each withdrawal
        // The Eigenlayer beaconChainETHStrategy  queued withdrawal completion flow follows the following steps:
        // 1. The flow starts in the DelegationManager where queued withdrawals are managed.
        // 2. For beaconChainETHStrategy, the DelegationManager calls _withdrawSharesAsTokens interacts with the EigenPodManager.withdrawSharesAsTokens
        // 3. Finally, the EigenPodManager calls withdrawRestakedBeaconChainETH on the EigenPod of this StakingNode to finalize the withdrawal.
        // 4. the EigenPod decrements withdrawableRestakedExecutionLayerGwei and send the ETH to address(this)
        delegationManager.completeQueuedWithdrawals(withdrawals, tokens, middlewareTimesIndexes, receiveAsTokens);

        uint256 finalETHBalance = address(this).balance;
        uint256 actualWithdrawalAmount = finalETHBalance - initialETHBalance;
        if (actualWithdrawalAmount != totalWithdrawalAmount) {
            revert MismatchInExpectedETHBalanceAfterWithdrawals(actualWithdrawalAmount, totalWithdrawalAmount);
        }

        // Shares are no longer queued
        queuedSharesAmount -= actualWithdrawalAmount;

        // Withdraw validator principal resides in the StakingNode until StakingNodesManager retrieves it.
        withdrawnValidatorPrincipal += actualWithdrawalAmount;

        emit CompletedQueuedWithdrawals(withdrawals, totalWithdrawalAmount);
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  ETH BALANCE ACCOUNTING  --------------------------
    //--------------------------------------------------------------------------------------

    /**
     * @dev Record total staked ETH for this StakingNode
     */
    function allocateStakedETH(uint256 amount) external payable onlyStakingNodesManager {
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
    function deallocateStakedETH(uint256 amount) external payable onlyStakingNodesManager {
        if (amount > withdrawnValidatorPrincipal) {
            revert InsufficientWithdrawnValidatorPrincipal(amount, withdrawnValidatorPrincipal);
        }

        emit DeallocatedStakedETH(amount, withdrawnValidatorPrincipal);

        withdrawnValidatorPrincipal -= amount;

        (bool success, ) = address(stakingNodesManager).call{value: amount}("");
        if (!success) {
            revert TransferFailed();
        }
    }
    function getETHBalance() public view returns (uint256) {

        IEigenPodManager eigenPodManager = IEigenPodManager(IStakingNodesManager(stakingNodesManager).eigenPodManager());
        // TODO: unverifiedStakedETH MUST be initialized to the correct value 
        // ad deploy time
        // Example: If ALL validators have been verified it MUST be 0
        // If NONE of the validators have been verified it MUST be equal to former allocatedETH
        int256 totalETHBalance =
            int256(withdrawnValidatorPrincipal + unverifiedStakedETH + queuedSharesAmount)
            + eigenPodManager.podOwnerShares(address(this));

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
     * @notice Retrieves the amount of ETH that has been withdrawn from validators and is held by this StakingNode.
     * @return The amount of withdrawn validator principal in wei.
     */
    function getWithdrawnValidatorPrincipal() public view returns (uint256) {
        return withdrawnValidatorPrincipal;
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
    modifier notZeroAddress(address _address) {
        if (_address == address(0)) {
            revert ZeroAddress();
        }
        _;
    }    
}