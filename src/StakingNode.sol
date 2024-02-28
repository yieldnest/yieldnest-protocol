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
     event WithdrawalStarted(uint256 amount, address strategy, uint96 nonce);
     event RewardsProcessed(uint256 rewardsAmount);
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


    //--------------------------------------------------------------------------------------
    //----------------------------------  CONSTANTS  ---------------------------------------
    //--------------------------------------------------------------------------------------

    IStrategy public constant beaconChainETHStrategy = IStrategy(0xbeaC0eeEeeeeEEeEeEEEEeeEEeEeeeEeeEEBEaC0);
    uint256 public constant GWEI_TO_WEI = 1e9;

    //--------------------------------------------------------------------------------------
    //----------------------------------  VARIABLES  ---------------------------------------
    //--------------------------------------------------------------------------------------

    IStakingNodesManager public stakingNodesManager;
    IStrategyManager public strategyManager;
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
        // TODO: should we charge fees here or not?
        // Except for Consensus Layer rewards the principal may exit this way as well.
       if (msg.sender != address(stakingNodesManager.delayedWithdrawalRouter())) {
            revert ETHDepositorNotDelayedWithdrawalRouter();
       }
       if (pendingWithdrawnValidatorPrincipal > msg.value) {
            revert WithdrawalAmountTooLow(msg.value, pendingWithdrawnValidatorPrincipal);
       }
       allocatedETH -= pendingWithdrawnValidatorPrincipal;
       pendingWithdrawnValidatorPrincipal = 0;
       
       stakingNodesManager.processWithdrawnETH{value: msg.value}(nodeId, pendingWithdrawnValidatorPrincipal);
       emit RewardsProcessed(msg.value);
    }

    constructor() {
    }

    function initialize(Init memory init) external {
        require(address(stakingNodesManager) == address(0), "already initialized");
        require(address(init.stakingNodesManager) != address(0), "No zero addresses");

        stakingNodesManager = init.stakingNodesManager;
        strategyManager = init.strategyManager;
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

        pendingWithdrawnValidatorPrincipal = withdrawnValidatorPrincipal;
        // only claim if we have active unclaimed withdrawals

        // the ETH funds are sent to address(this) and trigger the receive() function
        IDelayedWithdrawalRouter delayedWithdrawalRouter = stakingNodesManager.delayedWithdrawalRouter();
        if (delayedWithdrawalRouter.getUserDelayedWithdrawals(address(this)).length > 0) {
            delayedWithdrawalRouter.claimDelayedWithdrawals(address(this), maxNumWithdrawals);
        }
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  VERIFICATION AND DELEGATION   --------------------
    //--------------------------------------------------------------------------------------

    function delegate(address operator) public virtual onlyAdmin {

        IDelegationManager delegationManager = stakingNodesManager.delegationManager();

        delegationManager.delegateTo(operator);

        emit Delegated(operator, 0);
    }
    
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
            eigenPod.verifyWithdrawalCredentialsAndBalance(
                oracleBlockNumber[i],
                validatorIndex[i],
                proofs[i],
                validatorFields[i]
            );
        }
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  ETH BALANCE ACCOUNTING  --------------------------
    //--------------------------------------------------------------------------------------

    /// @dev Record total staked ETH for this StakingNode
    function allocateStakedETH( uint amount) external payable onlyStakingNodesManager {
        allocatedETH += amount;
    }

    function getETHBalance() public view returns (uint) {

        // 1 Beacon Chain ETH strategy share = 1 ETH
        // TODO: handle the withdrawal situation - this means that ETH will reside in the eigenpod at some point

        // NOTE: when verifyWithdrawalCredentials is enabled
        // the eigenpod will be credited with shares measured as:
        // strategyManager.stakerStrategyShares(address(this), beaconChainETHStrategy);
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
}
