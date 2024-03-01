// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IBeacon} from "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";
import {IEigenPodManager} from "./external/eigenlayer/v0.1.0/interfaces/IEigenPodManager.sol";
import {IEigenPod} from "./external/eigenlayer/v0.1.0/interfaces/IEigenPod.sol";
import {IDelegationManager} from "./external/eigenlayer/v0.1.0/interfaces/IDelegationManager.sol";
import {IDelayedWithdrawalRouter} from "./external/eigenlayer/v0.1.0/interfaces/IDelayedWithdrawalRouter.sol";
import {IStrategyManager,IStrategy} from "./external/eigenlayer/v0.1.0/interfaces/IStrategyManager.sol";
import {BeaconChainProofs} from "./external/eigenlayer/v0.1.0/BeaconChainProofs.sol";
import {IStakingNodesManager} from "./interfaces/IStakingNodesManager.sol";
import {IStakingNode} from "./interfaces/IStakingNode.sol";


interface StakingNodeEvents {
     event EigenPodCreated(address indexed nodeAddress, address indexed podAddress);   
     event Delegated(address indexed operator, bytes32 approverSalt);
     event Undelegated(address indexed operator);
     event WithdrawalStarted(uint256 amount, address indexed strategy, uint96 nonce);
     event RewardsProcessed(uint256 rewardsAmount);
     event ClaimedDelayedWithdrawal(uint256 claimedAmount, uint256 withdrawnValidatorPrincipal, uint256 allocatedETH);
}

contract StakingNode is IStakingNode, StakingNodeEvents, ReentrancyGuardUpgradeable {

    //--------------------------------------------------------------------------------------
    //----------------------------------  ERRORS  ------------------------------------------
    //--------------------------------------------------------------------------------------

    error NotStakingNodesAdmin();
    error StrategyIndexMismatch(address strategy, uint index);
    error ETHDepositorNotDelayedWithdrawalRouter();
    error WithdrawalAmountTooLow(uint256 sentAmount, uint256 pendingWithdrawnValidatorPrincipal);
    error WithdrawalPrincipalAmountTooHigh(uint256 withdrawnValidatorPrincipal, uint256 allocatedETH);
    error ClaimableAnmountExceedsPrincipal(uint256 withdrawnValidatorPrincipal, uint256 claimableAmount);
    error ClaimAmountTooLow(uint256 expected, uint256 actual);
    error ZeroAddress();


    //--------------------------------------------------------------------------------------
    //----------------------------------  CONSTANTS  ---------------------------------------
    //--------------------------------------------------------------------------------------

    IStrategy public constant beaconChainETHStrategy = IStrategy(0xbeaC0eeEeeeeEEeEeEEEEeeEEeEeeeEeeEEBEaC0);
    uint256 public constant GWEI_TO_WEI = 1e9;

    //--------------------------------------------------------------------------------------
    //----------------------------------  VARIABLES  ---------------------------------------
    //--------------------------------------------------------------------------------------

    IStakingNodesManager public stakingNodesManager;
    IEigenPod public eigenPod;
    uint public nodeId;

    uint pendingWithdrawnValidatorPrincipal;

    /// @dev Monitors the ETH balance that was committed to validators allocated to this StakingNode
    uint256 public allocatedETH;


    /// @dev Allows only a whitelisted address to configure the contract
    modifier onlyAdmin() {
        if(!stakingNodesManager.isStakingNodesAdmin(msg.sender)) revert NotStakingNodesAdmin();
        _;
    }

    modifier onlyStakingNodesManager() {
        require(msg.sender == address(stakingNodesManager), "Only StakingNodesManager can call this function");
        _;
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  INITIALIZATION  ----------------------------------
    //--------------------------------------------------------------------------------------

    receive() external payable nonReentrant {
        // Consensus Layer rewards and the validator principal will be sent this way.
       if (msg.sender != address(stakingNodesManager.delayedWithdrawalRouter())) {
            revert ETHDepositorNotDelayedWithdrawalRouter();
       }
    }

    constructor() {
    }

    function initialize(Init memory init)
        external
        notZeroAddress(address(init.stakingNodesManager))
        initializer {
        require(address(stakingNodesManager) == address(0), "already initialized");
        require(address(init.stakingNodesManager) != address(0), "No zero addresses");

        stakingNodesManager = init.stakingNodesManager;
        nodeId = init.nodeId;
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  EIGENPOD CREATION   ------------------------------
    //--------------------------------------------------------------------------------------

    function createEigenPod() public returns (IEigenPod) {
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
     * @notice  Kicks off a delayed withdraw of the ETH before any restaking has been done (EigenPod.hasRestaked() == false)
     * @dev  This allows StakingNode to retrieve rewards from the Consensus Layer that accrue over time as 
     *       validators sweep them to the withdrawal address
     */
    function withdrawBeforeRestaking() external onlyAdmin {
        eigenPod.withdrawBeforeRestaking();
    }

    /// @notice Retrieves and processes withdrawals that have been queued in the EigenPod, transferring them to the StakingNode.
    /// @param maxNumWithdrawals the upper limit of queued withdrawals to process in a single transaction.
    /// @dev Ideally, you should call this with "maxNumWithdrawals" set to the total number of unclaimed withdrawals.
    ///      However, if the queue becomes too large to handle in one transaction, you can specify a smaller number.
    function claimDelayedWithdrawals(uint256 maxNumWithdrawals, uint withdrawnValidatorPrincipal) public onlyAdmin {

        if (withdrawnValidatorPrincipal > allocatedETH) {
            revert WithdrawalPrincipalAmountTooHigh(withdrawnValidatorPrincipal, allocatedETH);
        }

        IDelayedWithdrawalRouter delayedWithdrawalRouter = stakingNodesManager.delayedWithdrawalRouter();

        uint256 totalClaimable = 0;
        IDelayedWithdrawalRouter.DelayedWithdrawal[] memory claimableWithdrawals = delayedWithdrawalRouter.getClaimableUserDelayedWithdrawals(address(this));
        for (uint256 i = 0; i < claimableWithdrawals.length; i++) {
            totalClaimable += claimableWithdrawals[i].amount;
        }
        if (totalClaimable < withdrawnValidatorPrincipal) {
            revert ClaimableAnmountExceedsPrincipal(withdrawnValidatorPrincipal, totalClaimable);
        }

        // only claim if we have active unclaimed withdrawals
        // the ETH funds are sent to address(this) and trigger the receive() function
        if (totalClaimable > 0) {

            uint256 balanceBefore = address(this).balance;
            delayedWithdrawalRouter.claimDelayedWithdrawals(address(this), maxNumWithdrawals);
            uint256 balanceAfter = address(this).balance;

            uint256 claimedAmount = balanceAfter - balanceBefore;
            if (totalClaimable > claimedAmount) {
                revert ClaimAmountTooLow(totalClaimable, claimedAmount);
            }
            // substract validator principal
            allocatedETH -= withdrawnValidatorPrincipal;
            
            stakingNodesManager.processWithdrawnETH{value: claimedAmount}(nodeId, withdrawnValidatorPrincipal);
            emit ClaimedDelayedWithdrawal(claimedAmount, claimedAmount, allocatedETH);
        }
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  VERIFICATION AND DELEGATION   --------------------
    //--------------------------------------------------------------------------------------

    // This function enables the Eigenlayer protocol to validate the withdrawal credentials of validators.
    // Upon successful verification, Eigenlayer issues shares corresponding to the staked ETH in the StakingNode.
    function verifyWithdrawalCredentials(
        uint64[] calldata oracleBlockNumber,
        uint40[] calldata validatorIndex,
        BeaconChainProofs.ValidatorFieldsAndBalanceProofs[] calldata proofs,
        bytes32[][] calldata validatorFields
    ) external virtual onlyAdmin {

        require(oracleBlockNumber.length == validatorIndex.length, "Mismatched oracleBlockNumber and validatorIndex lengths");
        require(validatorIndex.length == proofs.length, "Mismatched validatorIndex and proofs lengths");
        require(validatorIndex.length == validatorFields.length, "Mismatched proofs and validatorFields lengths");

        for (uint i = 0; i < validatorIndex.length; i++) {
            // NOTE: this call reverts with 'Pausable: index is paused' on mainnet currently 
            // because the beaconChainETHStrategy strategy is currently paused.
            eigenPod.verifyWithdrawalCredentialsAndBalance(
                oracleBlockNumber[i],
                validatorIndex[i],
                proofs[i],
                validatorFields[i]
            );

            // NOTE: after the verifyWithdrawalCredentialsAndBalance call
            // address(this) will be credited with shares corresponding to the balance of ETH in the validator.
        }
    }

    function delegate(address operator) public virtual onlyAdmin {

        IDelegationManager delegationManager = stakingNodesManager.delegationManager();
        delegationManager.delegateTo(operator);

        emit Delegated(operator, 0);
    }

    function undelegate() public virtual onlyAdmin {
        
        IDelegationManager delegationManager = stakingNodesManager.delegationManager();
        delegationManager.undelegate(address(this));

        address operator = delegationManager.delegatedTo(address(this));
        emit Undelegated(operator);
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  ETH BALANCE ACCOUNTING  --------------------------
    //--------------------------------------------------------------------------------------

    /// @dev Record total staked ETH for this StakingNode
    function allocateStakedETH( uint amount) external payable onlyStakingNodesManager {
        allocatedETH += amount;
    }

    function getETHBalance() public view returns (uint) {

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
        bytes32 slot = bytes32(uint256(keccak256('eip1967.proxy.beacon')) - 1);
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
