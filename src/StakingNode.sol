pragma solidity ^0.8.0;

// Development imports.
import "forge-std/console.sol";

// Third-party OZ deps
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IBeacon} from "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";

// Third-party Eigenlayer deps.
import {IEigenPodManager} from "./interfaces/eigenlayer-init-mainnet/IEigenPodManager.sol";
import {IDelegationManager} from "./interfaces/eigenlayer-init-mainnet/IDelegationManager.sol";
import {IStrategyManager} from "./interfaces/eigenlayer-init-mainnet/IStrategyManager.sol";
import {BeaconChainProofs} from "./interfaces/eigenlayer-init-mainnet/BeaconChainProofs.sol";

// Internal deps.
import {IStakingNodesManager} from "./interfaces/IStakingNodesManager.sol";
import {IStakingNode} from "./interfaces/IStakingNode.sol";

/******************************\
|                              |
|          Interfaces          |
|                              |
\******************************/

// TODO add natspec
interface StakingNodeEvents {
     event EigenPodCreated(address indexed nodeAddress, address indexed podAddress);   
     event Delegated(address indexed operator, bytes32 approverSalt);
     event WithdrawalStarted(uint256 amount, address strategy, uint96 nonce);
     event RewardsProcessed(uint256 rewardsAmount);
}

/******************************\
|                              |
|           Contracts          |
|                              |
\******************************/

/// @title StakingNode
/// @notice TODO
contract StakingNode is IStakingNode, StakingNodeEvents, ReentrancyGuardUpgradeable {

    /******************************\
    |                              |
    |             Errors           |
    |                              |
    \******************************/
    
    error NotStakingNodesAdmin();
    error StrategyIndexMismatch(address strategy, uint index);

    
    /******************************\
    |                              |
    |            Structs           |
    |                              |
    \******************************/

    /// @notice Configuration for contract initialization.
    /// @dev Only used in memory (i.e. layout doesn't matter!)
    /// @param stakingNodesManager The address of the StakingNodesManager contract.
    /// @param nodeId The id of this StakingNode.
    struct Init {
        address stakingNodesManager;
        uint nodeId;
    }

    /******************************\
    |                              |
    |           Constants          |
    |                              |
    \******************************/

    /// @notice The Beacon Chain eth strategy contract.
    // @note wtf is this?
    IStrategy private constant beaconChainETHStrategy = IStrategy(0xbeaC0eeEeeeeEEeEeEEEEeeEEeEeeeEeeEEBEaC0);

    /// @notice gwei * 1e9 = wei
    uint256 private constant GWEI_TO_WEI = 1e9;

    /******************************\
    |                              |
    |       Storage variables      |
    |                              |
    \******************************/

    /// @notice The StakingNodesManager contract.
    IStakingNodesManager public stakingNodesManager;

    /// @notice The Eigenod contract.
    IEigenPod public eigenPod;

    /// @notice This staking node's id.
    /// @dev This functions as a "immutable" var, only set in the initialize function.
    uint public nodeId;

    /// @dev The total amount of ETH that was committed to validators allocated to this StakingNode.
    uint256 public allocatedETH;

    /******************************\
    |                              |
    |          Constructor         |
    |                              |
    \******************************/

    /// @notice The constructor.
    /// @dev calling _disableInitializers() to prevent the implementation from
    ///      being initialized.
    constructor() {
        _disableInitializers();
    }

    /// @notice Inititalizes the contract.
    /// @param init The init params.
    function initialize(Init memory init) 
        external 
        notZeroAddress(init.stakingNodesManager) 
        initializer
    {
        // Store configuration values.
        nodeId = init.nodeId;

        // Store all of the addresses of interacting contracts.
        stakingNodesManager = IStrategyManager(init.stakingNodesManager);

        // Create the eigenPod.
        _createEigenPod();
    }

    /******************************\
    |                              |
    |         Core functions       |
    |                              |
    \******************************/


    /// @notice Kicks off a delayed withdraw of the ETH before any restaking has 
    ///         been done (EigenPod.hasRestaked() == false)
    /// @dev This allows StakingNode to retrieve rewards from the Consensus Layer that accrue over time as 
    ///      validators sweep them to the withdrawal address.
    function withdrawBeforeRestaking() 
        external
        onlyAdmin 
    {
        eigenPod.withdrawBeforeRestaking();
    }

    /// @notice Retrieves and processes withdrawals that have been queued in the EigenPod, transferring 
    ///         them to the StakingNode.
    /// @dev Ideally, you should call this with "maxNumWithdrawals" set to the total number of unclaimed
    ///      withdrawals. However, if the queue becomes too large to handle in one transaction, you can 
    ///      specify a smaller number.
    /// @param maxNumWithdrawals The upper limit of queued withdrawals to process in a single transaction.
    /// @param withdrawnValidatorPrincipal The amount of ETH we expect to receive from withdrawn validators
    function claimDelayedWithdrawals(uint256 maxNumWithdrawals, uint withdrawnValidatorPrincipal) 
        external
        onlyAdmin 
    {
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

    /// @notice Delegate assets of this contract to another address
    /// @param operator The address of the operator to delegate to
    function delegate(address operator) public virtual onlyAdmin {
        IDelegationManager delegationManager = stakingNodesManager.delegationManager();
        delegationManager.delegateTo(operator);
        emit Delegated(operator, 0); 
    }
    
    /// @notice Enables the Eigenlayer protocol to validate the withdrawal credentials of validators.
    //          Upon successful verification, Eigenlayer issues shares corresponding to the staked ETH in the StakingNode.
    /// @param oracleBlockNumber List of block numbers.
    /// @param validatorIndex List of validator indexes.
    /// @param proofs List of beacon chain proofs.
    /// @param validatorFields List of validator fields per validator.
    function verifyWithdrawalCredentials(
        uint64[] calldata oracleBlockNumber,
        uint40[] calldata validatorIndex,
        BeaconChainProofs.ValidatorFieldsAndBalanceProofs[] calldata proofs,
        bytes32[][] calldata validatorFields
    ) external virtual onlyAdmin { //@audit why is it virtual
        if (oracleBlockNumber.length != validatorIndex.length ||
            validatorIndex.length != proofs.length ||
            validatorIndex.length != validatorFields.length)
            revert LengthMismatch();
        
        for (uint i = 0; i < validatorIndex.length; i++) {
            eigenPod.verifyWithdrawalCredentialsAndBalance(
                oracleBlockNumber[i],
                validatorIndex[i],
                proofs[i],
                validatorFields[i]
            );
        }
    }

    /// @notice Updates the ETH amount "allocated" in this StakingNode
    /// @dev Only callable by the StakingNodesManager contract
    /// @param The amount of ETH to add
    function allocateStakedETH() 
        payable
        external
        onlyStakingNodesManager 
    {
        allocatedETH += msg.value;
    }

    receive() 
        payable
        external 
        nonReentrant 
    {
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


    /******************************\
    |                              |
    |      Internal functions      |
    |                              |
    \******************************/

    /// @notice Creates an eigenPod for this StakingNode.
    function _createEigenPod() 
        internal {
        // Get a reference to the eignePod manager.
        IEigenPodManager eigenPodManager = IEigenPodManager(stakingNodesManager.eigenPodManager());

        // Create a new eigenPod, it will be "registered" under the msg.sender, which
        // is the address of this StakingNode contract. If there already was an eigenPod
        // registered under this address, the createPod function will revert.
        eigenPodManager.createPod();

        // Retrieve and store the just created EigenPod contract.
        eigenPod = eigenPodManager.getPod(address(this));

        emit StakingNode_EigenPodCreated(address(eigenPod));
    }
    
    /******************************\
    |                              |
    |        View functions        |
    |                              |
    \******************************/

    /// @notice Retrieve the version number of the highest/newest initialize
    ///         function that was executed.
    /// @param uint64 The version number
    function getInitializedVersion() external view returns (uint64) {
        return _getInitializedVersion();
    }

    /// @notice Returns the address of the current implementation contract.
    ///         Retrieved from the UpgradeableBeacon contract
    /// @dev Slot is defined here: https://github.com/OpenZeppelin/openzeppelin-contracts/blob/afb20119b33072da041c97ea717d3ce4417b5e01/contracts/proxy/ERC1967/ERC1967Upgrade.sol#L142
    /// @return address The address of the current implementation contract.
    function implementation() public view returns (address) {
        bytes32 slot = bytes32(uint256(keccak256('eip1967.proxy.beacon')) - 1);
        address upgradeableBeacon;
        assembly { upgradeableBeacon := sload(slot) }
        return IBeacon(upgradeableBeacon).implementation();
    }

    /// @notice Return the current allocated ETH balance of this StakingNode.
    /// @return uint The (theoretical) ETH balance of this contract 
    function getETHBalance() 
        public 
        view
        returns (uint) 
    {
        return allocatedETH;
    }

    /******************************\
    |                              |
    |           Modifiers          |
    |                              |
    \******************************/

    /// @notice Ensures that the given address is not the zero address.
    /// @param addr The address to check.
    modifier notZeroAddress(address _addr) {
        if (_addr == address(0)) revert ZeroAddress();
        _;
    }

    /// @dev Allows only a whitelisted address to configure the contract
    modifier onlyAdmin() {
        if(!stakingNodesManager.isStakingNodesAdmin(msg.sender)) revert NotStakingNodesAdmin();
        _;
    }

    modifier onlyStakingNodesManager() {
        require(msg.sender == address(stakingNodesManager), "Only StakingNodesManager can call this function");
        _;
    }

}
