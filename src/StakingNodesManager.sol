// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

// Third-party imports: Foundry
import {stdMath} from "forge-std/StdMath.sol";

// Third-party imports: OZ
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

// Third-party imports: ETH2
import {DepositRootGenerator} from "./libraries/DepositRootGenerator.sol";
import {IDepositContract} from "./interfaces/IDepositContract.sol";

// Third-party imports: Eigenlayer
import {IEigenPodManager} from "./interfaces/eigenlayer-init-mainnet/IEigenPodManager.sol";
import {IDelegationManager} from "./interfaces/eigenlayer-init-mainnet/IDelegationManager.sol";
import {IDelayedWithdrawalRouter} from "./interfaces/eigenlayer-init-mainnet/IDelayedWithdrawalRouter.sol";

// Internal imports
import {IStakingNode} from "./interfaces/IStakingNode.sol";
import {IynETH} from "./interfaces/IynETH.sol";
// import {IDepositPool} from "./interfaces/IDepositPool.sol"; TODO

/// @title StakingNodesManager
/// @notice The StakingNodesManager contract is charged with de creation of StakingNode
///         contracts and the registerting of validators under these StakingNodes. Each StakingNode
///         contract has its own Eigenpod. Multiple validators will/can be registered under the 
///         same StakingNode(=Eigenpod).
///         TODO add delegationManager info
///             * This design allows for delegating to multiple operators simultaneously while also being gas efficient.
///             * Grouping multuple validators per EigenPod allows delegation of all their stake with 1 delegationManager.delegateTo(operator) call.
contract StakingNodesManager is
    Initializable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
{
    /******************************\
    |                              |
    |             Errors           |
    |                              |
    \******************************/

    error StakingNodesManager_ZeroAddress();
    error StakingNodesManager_DepositAllocationUnbalanced(uint nodeId, uint nodeBalance, uint averageBalance, uint newNodeBalance, uint newAverageBalance);
    error StakingNodesManager_DepositRootMismatch(bytes32 _depositRoot, bytes32 onchainDepositRoot);
    error StakingNodesManager_ValidatorAlreadyUsed(bytes publicKey);
    error StakingNodesManager_ValidatorDataRootMismatch(bytes32 depositDataRoot, bytes32 expectedValidatorDataRoot);
    error StakingNodesManager_DirectETHDepositsNotAllowed();
    error StakingNodesManager_NoValidatorData();
    error StakingNodesManager_NonexistentNodeId();
    error StakingNodesManager_MaxNodesCreated();
    error StakingNodesManager_ImplementationIsZero();
    error StakingNodesManager_NoImplementation();
    error StakingNodesManager_ImplementationAlreadyCurrent();
    error StakingNodesManager_MaxNodeCountAboveCurrentNodeCount(uint currentCount, uint newCount);
    error StakingNodesManager_MaxNodeCountAlreadyCurrent();
    error StakingNodesManager_CallerNotStakingNode();
    error StakingNodesManager_CallerNotYnEth();
    error StakingNodesManager_ImplementationUpgradeReinitializeFailed(address stakingNode, bytes upgradeCallData);

    /******************************\
    |                              |
    |             Events           |
    |                              |
    \******************************/

    event StakingNodesManager_UpgradeableBeaconDeployed(address indexed beacon);
    event StakingNodesManager_ImplementationUpdated(address indexed oldImpl, address indexed newImpl);
    event StakingNodesManager_StakingNodeCreated(uint indexed id, address indexed node, address indexed eigendPod);
    event StakingNodesManager_ValidatorRegistered(uint indexed nodeId, bytes signature, bytes publicKey, bytes32 depositDataRoot);
    event StakingNodesManager_ForwardedEthToYnEth(uint indexed nodeId, uint indexed ethAmount);
    event StakingNodesManager_MaxNodeCountUpdated(uint indexed oldCount, uint indexed newCount);

    /******************************\
    |                              |
    |            Structs           |
    |                              |
    \******************************/

    /// @notice Configuration for contract initialization.
    /// @dev Only used in memory (i.e. layout doesn't matter!)
    /// @param admin The address of the account that gets the DEFAULT_ADMIN_ROLE.
    /// @param stakingAdmin The address of the account that gets the STAKING_ADMIN_ROLE.
    /// @param stakingNodesAdmin The address of the account that gets the STAKING_NODES_ADMIN_ROLE.
    /// @param validatorManager The address of the account that gets the VALIDATOR_MANAGER_ROLE.
    /// @param maxNodeCount The initial maxNodeCount.
    /// @param depositContract The (ETH2) DepositContract.
    /// @param ynETH The ynETH contract.
    /// @param strategyManager The StrategyManager contract.
    /// @param eigenPodManager The EigenPodManager contract.
    /// @param delegationManager The DelegationManager contract.
    /// @param delayedWithdrawalRouter The DelayedWithdrawalRouter contract.
    struct Init {
        address admin;
        address stakingAdmin;
        address stakingNodesAdmin;
        address validatorManager;
        uint maxNodeCount;
        address depositContract;
        address ynETH;
        address strategyManager;
        address eigenPodManager;
        address delegationManager;
        address delayedWithdrawalRouter;
    }

    /// @notice Configuration for contract initialization.
    /// @dev Only used in memory (i.e. layout doesn't matter!)
    /// @param publicKey The public key of this validator.
    /// @param admin The signature over the depositDataRoot. TODO is this right?
    /// @param nodeId The id of the StakingNode where this validator is "added" to.
    /// @param depositDataRoot The depositoData root in the ETH2 contract. TODO is this right?
    struct ValidatorData {
        bytes publicKey;
        bytes signature;
        uint nodeId;
        bytes32 depositDataRoot;
    }

    /******************************\
    |                              |
    |           Constants          |
    |                              |
    \******************************/

    /// @notice Role is allowed to set system parameters and upgrade the implementation
    ///         of the StakingNodes.
    bytes32 private constant STAKING_ADMIN_ROLE = keccak256("STAKING_ADMIN_ROLE");

    /// @notice Role controls all staking stakingNodes and is charged with deploying new StakingNodes.
    bytes32 private constant STAKING_NODES_ADMIN_ROLE = keccak256("STAKING_NODES_ADMIN_ROLE");

    /// @notice Role is able to register validators.
    bytes32 public constant VALIDATOR_MANAGER_ROLE = keccak256("VALIDATOR_MANAGER_ROLE");

    /// @notice The amount of ETH a validator needs to stake to become a validator.
    uint private constant DEFAULT_VALIDATOR_STAKE = 32 ether;

    /******************************\
    |                              |
    |       Storage variables      |
    |                              |
    \******************************/

    /// @notice The ETH2 Deposit contract.
    IDepositContract public eth2DepositContract;

    /// @notice The ynETH contract.
    IynETH public ynETH;

    /// @notice The StrategyManager contract.
    address public strategyManager;

    /// @notice The DelegationManager contract.
    IEigenpodManager public eigenPodManager; //@audit not used

    /// @notice The DelegationManager contract.
    IDelegationManager public delegationManager; //@audit not used

    /// @notice The DelegationManager contract.
    IDelayedWithdrawalRouter public delayedWithdrawalRouter;

    /// @notice The OZ upgradeable beacon contract, this is used to determine the implementation 
    ///         contract of each StakingNode deployed by this StakingNodesManager contract.
    UpgradeableBeacon public upgradableBeacon;

    /// @notice List of validator pubkeys.
    bytes[] public validators;

    /// @notice List of all of the created StakingNode contracts.
    IStakingNode[] public stakingNodes;

    /// @notice Mapping to easily check if an address is one of the deployed staking nodes.
    mapping(address stakingNode => bool exists) public isStakingNode;

    /// @notice The maximum allowed number of StakingNode contracts that this contract can create.
    uint public maxNodeCount;

    /// @notice Mapping from validator pubkey to "exists".
    mapping(bytes pubkey => bool exists) public usedValidators;

    /******************************\
    |                              |
    |          Constructor         |
    |                              |
    \******************************/

    /// @notice The constructor.
    /// @dev calling _disableInitializers() to prevent the implementation from being initializable.
    constructor() {
       _disableInitializers();
    }
    
    /// @notice Inititalizes the contract.
    /// @param init The init params.
    function initialize(Init memory init) 
        external 
        notZeroAddress(init.admin)
        notZeroAddress(init.stakingAdmin)
        notZeroAddress(init.stakingNodesAdmin)
        notZeroAddress(init.validatorManager)
        notZeroAddress(init.depositContract)
        notZeroAddress(init.ynETH)
        notZeroAddress(init.strategyManager)
        notZeroAddress(init.eigenPodManager)
        notZeroAddress(init.delegationManager)
        notZeroAddress(init.delayedWithdrawalRouter)
        initializer 
    {
        // Initialize all the parent contracts.
        __AccessControl_init();
        __ReentrancyGuard_init();

        // Assign all the roles.
        _grantRole(DEFAULT_ADMIN_ROLE, init.admin);
        _grantRole(STAKING_ADMIN_ROLE, init.stakingAdmin);
        _grantRole(STAKING_NODES_ADMIN_ROLE, init.stakingNodesAdmin);
        _grantRole(VALIDATOR_MANAGER_ROLE, init.validatorManager);

        // Store configuration values.
        maxNodeCount = init.maxNodeCount;

        // Store all of the addresses of interacting contracts.
        eth2DepositContract = IDepositContract(init.depositContract);
        ynETH = IynETH(init.ynETH);
        eigenPodManager = IEigenpodManager(init.eigenPodManager);
        delegationManager = IDelegationManager(init.delegationManager);
        delayedWithdrawalRouter = IDelayedWithdrawalRouter(init.delayedWithdrawalRouter);
        strategyManager = init.strategyManager;
    }

    /******************************\
    |                              |
    |         Core functions       |
    |                              |
    \******************************/

    /// @notice Updates the implementation contract for all StakingNode contracts.
    /// @dev Only callable by an account with the VALIDATOR_MANAGER_ROLE.
    /// @dev The implementation set here will become the implementation of all already
    ///      deployed and to-be-deployed StakingNode contracts.
    /// @dev The first time this function is called it will deploy an UpgradeableBeacon
    ///      contract.
    function updateNodeImplementation(address _implementation, bytes calldata _upgradeCalldata) 
        external 
        onlyRole(STAKING_ADMIN_ROLE) 
    {
        if (_implementation == address(0)) {
            revert StakingNodesManager_ImplementationIsZero();
        }
        
        address oldImplementation;

        // If this is the very first time this function is called, deploy the UpgradeableBeacon contract.
        if (address(upgradableBeacon) == address(0)) {
            oldImplementation = address(0);

            // NOTE: the "owner" of the UpgradeableBeacon contract is this StakingNodesManager contract.
            upgradableBeacon = new UpgradeableBeacon(_implementation, address(this));     

            emit StakingNodesManager_UpgradeableBeaconDeployed(address(upgradableBeacon));

        // Otherwise, an UpgradeableBeacon contract already exists and we want to update
        // the existing implementation.
        } else {
            oldImplementation = upgradableBeacon.implementation();

            if (_implementation == oldImplementation) {
                revert StakingNodesManager_ImplementationAlreadyCurrent();
            }

            // Store the new implementation's address in the beacon.
            upgradableBeacon.upgradeTo(_implementation);
            
            // If it exists call the new initializeV<x> function on each existing StakingNode.
            for (uint i = 0; i < stakingNodes.length; i++) {
                _initStakingNode(stakingNodes[i]);
            }
        }

        emit StakingNodesManager_ImplementationUpdated(oldImplementation, _implementation);
    }

    /// @notice Deploys a new StakingNode and adds it to the list of StakingNodes 
    ///         in this contract.
    /// @return IStakingNode The created StakingNode contract.
    function createStakingNode() 
        external 
        onlyRole(STAKING_NODES_ADMIN_ROLE) 
        returns (IStakingNode) 
    {
        if (stakingNodes.length >= maxNodeCount) {
            revert StakingNodesManager_MaxNodesCreated();
        }
        if (address(upgradeableBeacon) == address(0)) {
            revert StakingNodesManager_NoImplementation();
        }

        uint nodeId = stakingNodes.length;

        // Deploy the Stakingnode contract.
        BeaconProxy stakingNodeProxy = new BeaconProxy(address(upgradableBeacon), "");
        StakingNode stakingNode = StakingNode(payable(stakingNodeProxy));

        // Initialize the StakingNode contract.
        _initStakingNode(stakingNode);

        // Register the StakingNode in the internal accounting.
        stakingNodes.push(stakingNode);
        isStakingNode[address(stakingNodeProxy)] = true;

        emit StakingNodesManager_StakingNodeCreated(
            nodeId, 
            address(stakingNodeProxy), 
            address(stakingNodeProxy.eigenPod())
        );

        return node;
    }

    /// @notice Register a list of validators to specific StakingNodes.
    /// @dev Only callable by an account with the VALIDATOR_MANAGER_ROLE.
    /// @param _depositRoot The expected onchain deposit root.
    /// @param _validatorDatas The list of deposit data (that should result in the root)
    function registerValidators(ValidatorData[] calldata _validatorDatas)
        external 
        onlyRole(VALIDATOR_MANAGER_ROLE) 
        nonReentrant //@audit is nonReentrant necessary?
    {
        if (_validatorDatas.length == 0) {
            revert StakingNodesManager_NoValidatorData();
        }
        
        // Validation over the entire group of ValidatorDatas.
        validateValidatorDataAllocation(_validatorDatas);

        // Each _validatorData represents a single validator that decided to stake 32 ETH to
        // become a validator. This 32 ETH was deposited into ynETH by each validator.
        // So move all those funds from the ynETH contract into this contract, so that,
        // in a moment, we can deposit the funds into the ETH2 Deposit contract.
        ynETH.withdrawETH(_validatorDatas.length * DEFAULT_VALIDATOR_STAKE);

        // Validate and then register each of the validators.
        for (uint i = 0 ; i < _validatorDatas.length; i++) {
            ValidatorData calldata validatorData = _validatorDatas[i];

            if (validatorData.nodeId > stakingNodes.length - 1) {
                revert StakingNodesManager_NonexistentNodeId();
            }
            if (usedValidators[validatorData.publicKey]) {
                revert StakingNodesManager_ValidatorAlreadyUsed(validatorData.publicKey);
            }

            // This generates the depositroot and ensures it matches the expected one in validatorData.depositDataRoot. 
            bytes memory withdrawalCredentials = validateDepositRoot(validatorData);
        
            // Deposit the 32 ETH into the ETH2 Deposit contract.
            eth2DepositContract.deposit{value: DEFAULT_VALIDATOR_STAKE}(
                validatorData.publicKey, 
                withdrawalCredentials, 
                validatorData.signature, 
                validatorData.depositDataRoot
            );

            // Inside the StakingNode update the "allocated eth" balance to include
            // the 32 ETH that just got deposited into the ETH2 Deposit contract.
            IStakingNode(stakingNodes[validatorData.nodeId]).allocateStakedETH(DEFAULT_VALIDATOR_STAKE);

            // Register the validator in the internal accounting.
            validators.push(validatorData.publicKey);
            usedValidators[validatorData.publicKey] = true;

            emit StakingNodesManager_ValidatorRegistered(
                validatorData.nodeId,
                validatorData.signature,
                validatorData.publicKey,
                depositDataRoot
            );
        }
    }

    /// @notice Forward ETH from a StakingNode contract to the ynETH contract.
    /// @dev Only callable by a StakingNode contract.
    function processWithdrawnETH() 
        payable
        external  
        onlyStakingNode
    {
        Address.sendValue(payable(address(ynETH), msg.value));
    }

    /// @notice Receive ETH from the ynETH contract.
    /// @dev Can only be called by the ynETH contract.
    /// @dev This happens when StakingNodesManager.registerValidators calls ynETh.withdrawETH, 
    ///      which calls this function.
    receive() 
        external payable 
        onlyYnEth
    {}

    /******************************\
    |                              |
    |    Configuration functions   |
    |                              |
    \******************************/

    /// @notice Sets the maximum number of staking stakingNodes allowed
    /// @dev Only callable by an account with the STAKING_ADMIN_ROLE.
    /// @param _maxNodeCount The new maximum number of staking stakingNodes.
    function updateMaxNodeCount(uint _maxNodeCount) 
        external 
        onlyRole(STAKING_ADMIN_ROLE) 
    {
        if (_maxNodeCount > node.length) {
            revert StakingNodesManager_MaxNodeCountAboveCurrentNodeCount(node.length, _maxNodeCount);
        }
        if (_maxNodeCount == maxNodeCount) {
            revert StakingNodesManager_MaxNodeCountAlreadyCurrent();
        }
        emit StakingNodesManager_MaxNodeCountUpdated(maxNodeCount, _maxNodeCount);
        maxNodeCount = _maxNodeCount;
    }

    /******************************\
    |                              |
    |      Internal functions      |
    |                              |
    \******************************/
    
    function _initStakingNode(IStakingNode _stakingNode) private {
        uint64 highestInitializedVersion = _stakingNode.getInitializedVersion();
        
        if (highestInitializedVersion < 1) {
            stakingNode.initialize(
                StakingNode.Init({
                    stakingNodesManager: address(this),
                    nodeId: nodeId
                })
            );
        }

        // Some examples:
        // if (highestInitializedVersion < 2) {
        //     stakingNode.initializeV2()
        // }

        // if (highestInitializedVersion < 3) {
        //     stakingNode.initializeV3()
        // }

        if (_stakingNode.getInitializedVersion()) {
    }
    
    /*************************************\
    |                                     |
    | View functions also used internally |
    |                                     |
    \*************************************/
    
    /// @notice Validates the deposit root of a single ValidatorData struct
    /// @param _validatorData A single struct representing the deposit of a validator
    function validateDepositRoot(ValidatorData calldata _validatorData, uint _depositAmount) 
        public view 
        returns (bytes memory withdrawalCredentials)
    {
        // Generates the Eigenlayer withdraw credentials of this StakingNode.
        address eigenPod = address(IStakingNode(stakingNodes[_validatorData.nodeId]).eigenPod());
        
        // Format into the right "bytes" value.
        withdrawalCredentials = generateWithdrawalCredentials(eigenPod);
        
        // Generate the depositRoot of this validator data.
        bytes32 depositDataRoot = depositRootGenerator.generateDepositRoot(
            _validatorData.publicKey, 
            _validatorData.signature, 
            withdrawalCredentials, 
            _depositAmount
        );

        // Ensure the depositRoot matches the expected one.
        if (depositDataRoot != _validatorData.depositDataRoot) { 
            revert StakingNodesManager_ValidatorDataRootMismatch(depositDataRoot, _validatorData.depositDataRoot);
        }
    }

    /// @notice Validates the allocation of deposit data across stakingNodes to ensure the distribution does not
    ///         increase the disparity in balances.
    /// @dev This function checks if the proposed allocation of deposits (represented by `_validatorData`) 
    ///      across the stakingNodes would lead to a more equitable distribution of validator stakes. It calculates 
    ///      the current and new average balances of stakingNodes, and ensures that for each node, the absolute
    ///      difference between its balance and the average balance does not increase as a result of the 
    ///      new deposits.
    /// @param _validatorDatas The list of deposit data structs representing the validator deposits into the
    ///                      ETH2 deposit contract.
    function validateValidatorDataAllocation(ValidatorData[] calldata _validatorDatas) 
        public view 
    {
        // We are going to use 2 arrays, 
        // 1 array with the node balance info BEFORE adding the new validator deposits,
        // and 1 array which also includes all of the new validator deposits.
        uint[] memory oldNodeBalances = new uint[](stakingNodes.length);
        uint[] memory newNodeBalances = new uint[](stakingNodes.length);

        uint oldTotalBalance = 0;

        // Go through all of the existing StakingNodes and gather their (theoretical) ETH balance.
        for (uint i = 0; i < stakingNodes.length; i++) {
            // Store the total ETH balance of this StakingNode.
            oldNodeBalances[i] = IStakingNode(stakingNodes[i]).getETHBalance();
            // Initially, the new node balance equals the old node balance.
            newNodeBalances[i] = oldNodeBalances[i];
            // Update the total old balance.
            oldTotalBalance += oldNodeBalances[i];
        }

        // If there is no balance, i.e. all of the StakingNodes in the ValidatorDatas
        // are StakingNodes to which zero validators have been added!
        if (oldTotalBalance == 0) return;

        // Calculate the average balance of each node, BEFORE adding the new validator deposits.
        uint oldAverageBalance = oldTotalBalance / stakingNodes.length;
        // Initially the new total balance equals the old. 
        uint newTotalBalance = oldTotalBalance;

        // Now add the new deposits to each StakingNode.
        for (uint i = 0; i < _validatorDatas.length; i++) {
            newNodeBalances[_validatorDatas[i].nodeId] += DEFAULT_VALIDATOR_STAKE;
            newTotalBalance += DEFAULT_VALIDATOR_STAKE;
        }

        // Calculate the average balance of each node, AFTER adding the new validator deposits.
        uint newAverageBalance = newTotalBalance / stakingNodes.length;

        // Go through every StakingNode
        for (uint nodeIdx = 0; i < stakingNodes.length; i++) {
            // If the difference between the average and actual node balance has grown after 
            // adding the new deposits, revert.
            if (stdMath.abs(int256(oldNodeBalances[i]) - int256(oldAverageBalance)) < 
                stdMath.abs(int256(newNodeBalances[i]) - int256(newAverageBalance))) 
            {
                revert StakingNodesManager_DepositAllocationUnbalanced(
                    i, 
                    oldNodeBalances[i], oldAverageBalance, 
                    newNodeBalances[i], newAverageBalance
                );
            }
        }
    }

    /************************************\
    |                                    |
    | View functions not used internally |
    |                                    |
    \************************************/

    /// @notice Generates the depositRoot.
    /// @param _publicKey The public key of the validator
    /// @param _signature The signature over the TODO
    /// @param _withdrawalCredentials TODO The Eigenlayer withdrawal credentails
    /// @param _depositAmount The dposited amount (TODO always 32 ETH?)
    /// @return bytes32 The generated deposit root
    function getGeneratedDepositRoot(
        bytes calldata _publicKey,
        bytes calldata _signature,
        bytes calldata _withdrawalCredentials,
        uint _depositAmount
    ) 
        external pure
        returns (bytes32) 
    {
        return depositRootGenerator.generateDepositRoot(
            _publicKey, _signature, _withdrawalCredentials, _depositAmount
        );
    }

    /// @notice Retrieve the current StakingNode implementation contract.
    /// @return address The address of the implementation contract.
    function getImplementation() 
        external view 
        returns (address) 
    {
        if (address(upgradeableBeacon) == address(0)) revert StakingNodesManager_NoImplementation();
        return upgradeableBeacon.implementation();
    }

    /// @notice Generates Eigenlayer withdraw credentials for a given address
    /// @param _address The address associated with the validator.
    /// @return bytes The generated withdraw credentials for this address.
    function generateWithdrawalCredentials(address _address) 
        external pure
        returns (bytes memory) 
    {   
        return abi.encodePacked(bytes1(0x01), bytes11(0x0), _address);
    }

    /// @notice Retrieve the list of all validator public keys.
    /// @return bytes[] The list of validator public keys.
    function getAllValidators() 
        external view 
        returns (bytes[] memory) 
    {
        return validators;
    }

    /// @notice Retrieve the list of all StakingNode contracts.
    /// @return IStakingNode[] The list of all StakingNode contracts.
    function getAllNodes() 
        external view 
        returns (IStakingNode[] memory) 
    {
        return stakingNodes;
    }

    /// @notice Retrieve the total number of StakingNodes.
    /// @return uint The number of StakingNodes.
    function getNodesLength() 
        external view 
        returns (uint ) 
    {
        return stakingNodes.length;
    }

    /// @notice Check if the address has the StakingNodesManager Admin role.
    /// @param address The address to check.
    /// @return bool True if it has the role, false otherwise.
    function isStakingNodesAdmin(address _address) 
        external view 
        returns (bool) 
    {
        // TODO: define specific admin
        return hasRole(STAKING_NODES_ADMIN_ROLE, _address);
    }

    /******************************\
    |                              |
    |           Modifiers          |
    |                              |
    \******************************/

    /// @notice Ensure that the given address is not the zero address.
    /// @param addr The address to check.
    modifier notZeroAddress(address _address) {
        if (_address == address(0)) {
            revert StakingNodesManager_ZeroAddress();
        }
        _;
    }

    /// @notice Ensure the caller is the StakingNode contract corresponding to
    ///         the supplied nodeId.
    /// @param _nodeId The id of the StakingNode expected to call this function.
    modifier onlyStakingNode {
        if (!isStakingNode[msg.sender]) {
            revert StakingNodesManager_CallerNotStakingNode();
        }
        _;
    }

    /// @notice Ensure the caller is the RewardsDistributor contract
    modifier onlyYnEth {
        if (msg.sender != address(ynETH)) {
            revert StakingNodesManager_CallerNotYnEth();
        }
        _;
    }
}
