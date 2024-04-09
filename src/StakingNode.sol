/// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {ReentrancyGuardUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import {BeaconChainProofs} from "lib/eigenlayer-contracts/src/contracts/libraries/BeaconChainProofs.sol";
import {IDelegationManager } from "lib/eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IEigenPod } from "lib/eigenlayer-contracts/src/contracts/interfaces/IEigenPod.sol";
import {ISignatureUtils} from "lib/eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";
import {IStrategy} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IBeacon} from "lib/openzeppelin-contracts/contracts/proxy/beacon/IBeacon.sol";
import {IEigenPodManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IEigenPodManager.sol";
import {IStakingNodesManager} from "src/interfaces/IStakingNodesManager.sol";
import {IStakingNode} from "src/interfaces/IStakingNode.sol";

interface StakingNodeEvents {
     event EigenPodCreated(address indexed nodeAddress, address indexed podAddress);   
     event Delegated(address indexed operator, bytes32 approverSalt);
     event Undelegated(address indexed operator);
     event WithdrawalsProcessed(uint256 claimedAmount, uint256 totalValidatorPrincipal, uint256 allocatedETH);
     event ETHReceived(address sender, uint256 value);
     event WithdrawnNonBeaconChainETH(uint256 amount);
}

/**
 * @title StakingNode
 * @dev Implements staking node functionality for the YieldNest protocol, enabling ETH staking, delegation, and rewards management.
 * Each StakingNode owns exactl one EigenPod which acts as a delegation unit, as it can be associated with exactly one operator.
 */
contract StakingNode is IStakingNode, StakingNodeEvents, ReentrancyGuardUpgradeable {

    //--------------------------------------------------------------------------------------
    //----------------------------------  ERRORS  ------------------------------------------
    //--------------------------------------------------------------------------------------

    error NotStakingNodesAdmin();
    error ETHDepositorNotDelayedWithdrawalRouter();
    error WithdrawalPrincipalAmountTooHigh(uint256 withdrawnValidatorPrincipal, uint256 allocatedETH);
    error ClaimAmountTooLow(uint256 expected, uint256 actual);
    error ZeroAddress();
    error NotStakingNodesManager();
    error MismatchedOracleBlockNumberAndValidatorIndexLengths(uint256 oracleBlockNumberLength, uint256 validatorIndexLength);
    error MismatchedValidatorIndexAndProofsLengths(uint256 validatorIndexLength, uint256 proofsLength);
    error MismatchedProofsAndValidatorFieldsLengths(uint256 proofsLength, uint256 validatorFieldsLength);
    error UnexpectedETHBalance(uint256 claimedAmount, uint256 expectedETHBalance);

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

    /// @dev Monitors the ETH balance that was committed to validators allocated to this StakingNode
    uint256 public allocatedETH;


    /// @dev Allows only a whitelisted address to configure the contract
    modifier onlyAdmin() {
        if(!stakingNodesManager.isStakingNodesAdmin(msg.sender)) revert NotStakingNodesAdmin();
        _;
    }

    modifier onlyStakingNodesManager() {
        if(msg.sender != address(stakingNodesManager)) revert NotStakingNodesManager();
        _;
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  INITIALIZATION  ----------------------------------
    //--------------------------------------------------------------------------------------

    receive() external payable {
        // Consensus Layer rewards and the validator principal will be sent this way.
       if (msg.sender != address(stakingNodesManager.delayedWithdrawalRouter())) {
            revert ETHDepositorNotDelayedWithdrawalRouter();
       }
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
     * @notice  Allows the StakingNode to withdraw ETH from the EigenPod before restaking.
     * @dev  This allows StakingNode to retrieve rewards from the Consensus Layer that accrue over time as 
     *       validators sweep them to the withdrawal address
     */
    function withdrawNonBeaconChainETHBalanceWei() external onlyAdmin {
        uint256 eigenPodBalance = address(eigenPod).balance;
        emit WithdrawnNonBeaconChainETH(eigenPodBalance);
        eigenPod.withdrawNonBeaconChainETHBalanceWei(address(this), eigenPodBalance);
    }

    /**
     * @notice Processes withdrawals by verifying the node's balance and transferring ETH to the StakingNodesManager.
     * @dev This function checks if the node's current balance matches the expected balance and then transfers the ETH to the StakingNodesManager.
     * @param totalValidatorPrincipal The total principal amount of the validators.
     * @param expectedETHBalance The expected balance of the node after withdrawals.
     */
    function processWithdrawals(
        uint256 totalValidatorPrincipal,
        uint256 expectedETHBalance
    ) public nonReentrant onlyAdmin {

        uint256 balance = address(this).balance;

        // check for any race conditions with balances by passing in the expected balance
        if (balance < expectedETHBalance) {
            revert UnexpectedETHBalance(balance, expectedETHBalance);
        }

        // check the desired balance of validator principal is available here
        if (balance < totalValidatorPrincipal) {
            revert WithdrawalPrincipalAmountTooHigh(totalValidatorPrincipal, balance);
        }

        // substract withdrawn validator principal from the allocated balance
        allocatedETH -= totalValidatorPrincipal;

        // push the expectedETHBalance here to the StakingNodesManager
        // balance - expectedETHBalance will have to be processed separately in another transaction
        // since its breakdown of rewards vs principal is unknown at runtime
        stakingNodesManager.processWithdrawnETH{value: expectedETHBalance}(nodeId, totalValidatorPrincipal);
        emit WithdrawalsProcessed(balance, totalValidatorPrincipal, allocatedETH);
    }


    //--------------------------------------------------------------------------------------
    //----------------------------------  VERIFICATION AND DELEGATION   --------------------
    //--------------------------------------------------------------------------------------

    function delegate(address operator) public override onlyAdmin {

        IDelegationManager delegationManager = IDelegationManager(address(stakingNodesManager.delegationManager()));

        // Only supports empty approverSignatureAndExpiry and approverSalt
        // this applies when no IDelegationManager.OperatorDetails.delegationApprover is specified by operator
        // TODO: add support for operators that require signatures
        ISignatureUtils.SignatureWithExpiry memory approverSignatureAndExpiry;
        bytes32 approverSalt;

        delegationManager.delegateTo(operator, approverSignatureAndExpiry, approverSalt);

        emit Delegated(operator, approverSalt);
    }    

    /// @dev Validates the withdrawal credentials for a withdrawal
    /// This activates the activation of the staked funds within EigenLayer
    /// @param oracleTimestamp The timestamp of the oracle that signed the block
    /// @param stateRootProof The state root proof
    /// @param validatorIndices The indices of the validators
    /// @param validatorFieldsProofs The validator fields proofs
    /// @param validatorFields The validator fields
    function verifyWithdrawalCredentials(
        uint64 oracleTimestamp,
        BeaconChainProofs.StateRootProof calldata stateRootProof,
        uint40[] calldata validatorIndices,
        bytes[] calldata validatorFieldsProofs,
        bytes32[][] calldata validatorFields
    ) external onlyAdmin {
        IEigenPod(address(eigenPod)).verifyWithdrawalCredentials(
            oracleTimestamp,
            stateRootProof,
            validatorIndices,
            validatorFieldsProofs,
            validatorFields
        );

        for (uint256 i = 0; i < validatorIndices.length; i++) {

            // TODO: check if this is correct
            uint64 validatorBalanceGwei = BeaconChainProofs.getEffectiveBalanceGwei(validatorFields[i]);

            allocatedETH -= (validatorBalanceGwei * 1e9);
        }
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  WITHDRAWAL AND UNDELEGATION   --------------------
    //--------------------------------------------------------------------------------------


    /*
    *  Withdrawal Flow:
    *
    *  1. queueWithdrawals() - Admin queues withdrawals
    *  2. undelegate() - Admin undelegates
    *  3. verifyAndProcessWithdrawals() - Admin verifies and processes withdrawals
    *  4. completeWithdrawal() - Admin completes withdrawal
    *
    */

    function queueWithdrawals(uint256 shares) public onlyAdmin {
    
        IDelegationManager delegationManager = IDelegationManager(address(stakingNodesManager.delegationManager()));

        IDelegationManager.QueuedWithdrawalParams[] memory queuedWithdrawalParams = new IDelegationManager.QueuedWithdrawalParams[](1);
        queuedWithdrawalParams[0] = IDelegationManager.QueuedWithdrawalParams({
            strategies: new IStrategy[](1),
            shares: new uint256[](1),
            withdrawer: address(this)
        });
        queuedWithdrawalParams[0].strategies[0] = IStrategy(address(beaconChainETHStrategy));
        queuedWithdrawalParams[0].shares[0] = shares;
        
        delegationManager.queueWithdrawals(queuedWithdrawalParams);
    }

    function undelegate() public override onlyAdmin {
        
        IDelegationManager delegationManager = IDelegationManager(address(stakingNodesManager.delegationManager()));
        delegationManager.undelegate(address(this));
    }

    function verifyAndProcessWithdrawals(
        uint64 oracleTimestamp,
        BeaconChainProofs.StateRootProof calldata stateRootProof,
        BeaconChainProofs.WithdrawalProof[] calldata withdrawalProofs,
        bytes[] calldata validatorFieldsProofs,
        bytes32[][] calldata validatorFields,
        bytes32[][] calldata withdrawalFields
    ) external onlyAdmin {
    
        IEigenPod(address(eigenPod)).verifyAndProcessWithdrawals(
            oracleTimestamp,
            stateRootProof,
            withdrawalProofs,
            validatorFieldsProofs,
            validatorFields,
            withdrawalFields
        );
    }

    function completeWithdrawal(
        uint256 shares,
        uint32 startBlock
    ) external onlyAdmin {

        IDelegationManager delegationManager = IDelegationManager(address(stakingNodesManager.delegationManager()));

        uint256[] memory sharesArray = new uint256[](1);
        sharesArray[0] = shares;

        IStrategy[] memory strategiesArray = new IStrategy[](1);
        strategiesArray[0] = IStrategy(address(beaconChainETHStrategy));

        IDelegationManager.Withdrawal memory withdrawal = IDelegationManager.Withdrawal({
            staker: address(this),
            delegatedTo: delegationManager.delegatedTo(address(this)),
            withdrawer: address(this),
            nonce: 0, // TODO: fix
            startBlock: startBlock,
            strategies: strategiesArray,
            shares:  sharesArray
        });

        uint256 balanceBefore = address(this).balance;

        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = IERC20(0x0000000000000000000000000000000000000000);

        // middlewareTimesIndexes is 0, since it's unused
        // https://github.com/Layr-Labs/eigenlayer-contracts/blob/5fd029069b47bf1632ec49b71533045cf00a45cd/src/contracts/core/DelegationManager.sol#L556
        delegationManager.completeQueuedWithdrawal(withdrawal, tokens, 0, true);

        uint256 balanceAfter = address(this).balance;
        uint256 fundsWithdrawn = balanceAfter - balanceBefore;

        // TODO: revise if rewards may be captured in here as well
        stakingNodesManager.processWithdrawnETH{value: fundsWithdrawn}(nodeId, fundsWithdrawn);
    }


    /// M2 ABOVE

    //--------------------------------------------------------------------------------------
    //----------------------------------  ETH BALANCE ACCOUNTING  --------------------------
    //--------------------------------------------------------------------------------------

    /// @dev Record total staked ETH for this StakingNode
    function allocateStakedETH(uint256 amount) external payable onlyStakingNodesManager {
        allocatedETH += amount;
    }

    function getETHBalance() public view returns (uint256) {

        // NOTE: when verifyWithdrawalCredentials is enabled
        // the eigenpod will be credited with shares. Those shares represent 1 share = 1 ETH
        // To get the shares call: strategyManager.stakerStrategyShares(address(this), beaconChainETHStrategy)
        // This computation will need to be updated to factor in that.
        return allocatedETH;
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