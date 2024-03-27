// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {depositRootGenerator} from "./external/ethereum/DepositRootGenerator.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {IDepositContract} from "./external/ethereum/IDepositContract.sol";
import {IDelegationManager} from "./external/eigenlayer/v0.1.0/interfaces/IDelegationManager.sol";
import {IDelayedWithdrawalRouter} from "./external/eigenlayer/v0.1.0/interfaces/IDelayedWithdrawalRouter.sol";
import {IRewardsDistributor,IRewardsReceiver} from "./interfaces/IRewardsDistributor.sol";
import {IEigenPodManager,IEigenPod} from "./external/eigenlayer/v0.1.0/interfaces/IEigenPodManager.sol";
import {IStrategyManager} from "./external/eigenlayer/v0.1.0/interfaces/IStrategyManager.sol";
import {IStakingNode} from "./interfaces/IStakingNode.sol";
import {IStakingNodesManager} from "./interfaces/IStakingNodesManager.sol";
import {IynETH} from "./interfaces/IynETH.sol";

interface StakingNodesManagerEvents {
    event StakingNodeCreated(address indexed nodeAddress, address indexed podAddress);   
    event ValidatorRegistered(uint256 nodeId, bytes signature, bytes pubKey, bytes32 depositRoot, bytes withdrawalCredentials);
    event MaxNodeCountUpdated(uint256 maxNodeCount);
    event ValidatorRegistrationPausedSet(bool isPaused);
    event WithdrawnETHProcessed(uint256 nodeId, uint256 value, uint256 withdrawnValidatorPrincipal, uint256 rewards);
    event RegisteredStakingNodeImplementationContract(address upgradeableBeaconAddress, address implementationContract);
    event UpgradedStakingNodeImplementationContract(address implementationContract, uint256 nodesCount);
    event NodeInitialized(address nodeAddress, uint64 initializedVersion);
}

contract StakingNodesManager is
    IStakingNodesManager,
    Initializable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    StakingNodesManagerEvents {

    //--------------------------------------------------------------------------------------
    //----------------------------------  ERRORS  ------------------------------------------
    //--------------------------------------------------------------------------------------

    error DepositAllocationUnbalanced(uint256 nodeId, uint256 nodeBalance, uint256 averageBalance, uint256 newNodeBalance, uint256 newAverageBalance);
    error DepositRootChanged(bytes32 _depositRoot, bytes32 onchainDepositRoot);
    error ValidatorAlreadyUsed(bytes publicKey);
    error DepositDataRootMismatch(bytes32 depositDataRoot, bytes32 expectedDepositDataRoot);
    error DirectETHDepositsNotAllowed();
    error InvalidNodeId(uint256 nodeId);
    error ZeroAddress();
    error NotStakingNode(address caller, uint256 nodeId);
    error TooManyStakingNodes(uint256 maxNodeCount);
    error BeaconImplementationAlreadyExists();
    error NoBeaconImplementationExists();
    error DepositorNotYnETH();
    error TransferFailed();
    error NoValidatorsProvided();
    error ValidatorRegistrationPaused();

    //--------------------------------------------------------------------------------------
    //----------------------------------  ROLES  -------------------------------------------
    //--------------------------------------------------------------------------------------

    /// @notice  Role is allowed to set system parameters
    bytes32 public constant STAKING_ADMIN_ROLE = keccak256("STAKING_ADMIN_ROLE");

    /// @notice  Role controls all staking nodes
    bytes32 public constant STAKING_NODES_ADMIN_ROLE = keccak256("STAKING_NODES_ADMIN_ROLE");

    /// @notice  Role is able to register validators
    bytes32 public constant VALIDATOR_MANAGER_ROLE = keccak256("VALIDATOR_MANAGER_ROLE");

    /// @notice Role is able to create staking nodes
    bytes32 public constant STAKING_NODE_CREATOR_ROLE = keccak256("STAKING_NODE_CREATOR_ROLE");

    /// @notice  Role is allowed to set the pause state
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    //--------------------------------------------------------------------------------------
    //----------------------------------  CONSTANTS  ---------------------------------------
    //--------------------------------------------------------------------------------------

    uint256 constant DEFAULT_VALIDATOR_STAKE = 32 ether;

    //--------------------------------------------------------------------------------------
    //----------------------------------  VARIABLES  ---------------------------------------
    //--------------------------------------------------------------------------------------

    IEigenPodManager public eigenPodManager;
    IDepositContract public depositContractEth2;
    IDelegationManager public delegationManager;
    IDelayedWithdrawalRouter public delayedWithdrawalRouter;
    IStrategyManager public strategyManager;
    
    UpgradeableBeacon public upgradeableBeacon;

    IynETH public ynETH;
    IRewardsDistributor public rewardsDistributor;

    /**
    /**
     * @notice Each node in the StakingNodesManager manages an EigenPod. 
     * An EigenPod represents a collection of validators and their associated staking activities within the EigenLayer protocol. 
     * The StakingNode contract, which each node is an instance of, interacts with the EigenPod to perform various operations such as:
     * - Creating the EigenPod upon the node's initialization if it does not already exist.
     * - Delegating staking operations to the EigenPod, including processing rewards and managing withdrawals.
     * - Verifying withdrawal credentials and managing expedited withdrawals before restaking.
     * 
     * This design allows for delegating to multiple operators simultaneously while also being gas efficient.
     * Grouping multuple validators per EigenPod allows delegation of all their stake with 1 delegationManager.delegateTo(operator) call.
     */
    IStakingNode[] public nodes;
    uint256 public maxNodeCount;

    Validator[] public validators;
    mapping(bytes pubkey => bool) usedValidators;

    bool public validatorRegistrationPaused;

    //--------------------------------------------------------------------------------------
    //----------------------------------  INITIALIZATION  ----------------------------------
    //--------------------------------------------------------------------------------------

    constructor() {
       _disableInitializers();
    }

    /// @notice Configuration for contract initialization.
    struct Init {
        // roles
        address admin;
        address stakingAdmin;
        address stakingNodesAdmin;
        address validatorManager;
        address stakingNodeCreatorRole;
        address pauser;

        // internal
        uint256 maxNodeCount;
        IynETH ynETH;
        IRewardsDistributor rewardsDistributor; 

        // external contracts
        IDepositContract depositContract;
        IEigenPodManager eigenPodManager;
        IDelegationManager delegationManager;
        IDelayedWithdrawalRouter delayedWithdrawalRouter;
        IStrategyManager strategyManager;
    }
    
    function initialize(Init calldata init)
    external
    notZeroAddress(address(init.ynETH))
    notZeroAddress(address(init.rewardsDistributor))
    initializer
    {
        __AccessControl_init();
        __ReentrancyGuard_init();

        initializeRoles(init);
        initializeExternalContracts(init);

        rewardsDistributor = init.rewardsDistributor;
        maxNodeCount = init.maxNodeCount;
        ynETH = init.ynETH;

    }

    function initializeRoles(Init calldata init)
        internal
        notZeroAddress(init.admin)
        notZeroAddress(init.stakingAdmin)
        notZeroAddress(init.stakingNodesAdmin)
        notZeroAddress(init.validatorManager)
        notZeroAddress(init.stakingNodeCreatorRole)
        notZeroAddress(init.pauser) {
        _grantRole(DEFAULT_ADMIN_ROLE, init.admin);
        _grantRole(STAKING_ADMIN_ROLE, init.stakingAdmin);
        _grantRole(VALIDATOR_MANAGER_ROLE, init.validatorManager);
        _grantRole(STAKING_NODES_ADMIN_ROLE, init.stakingNodesAdmin);
        _grantRole(STAKING_NODE_CREATOR_ROLE, init.stakingNodeCreatorRole);
        _grantRole(PAUSER_ROLE, init.pauser);
    }

    function initializeExternalContracts(Init calldata init)
        internal
        notZeroAddress(address(init.depositContract))
        notZeroAddress(address(init.eigenPodManager))
        notZeroAddress(address(init.delegationManager))
        notZeroAddress(address(init.delayedWithdrawalRouter))
        notZeroAddress(address(init.strategyManager)) {
        // Ethereum
        depositContractEth2 = init.depositContract;    

        // Eigenlayer
        eigenPodManager = init.eigenPodManager;    
        delegationManager = init.delegationManager;
        delayedWithdrawalRouter = init.delayedWithdrawalRouter;
        strategyManager = init.strategyManager;
    }

    receive() external payable {
        if (msg.sender != address(ynETH)) {
            revert DepositorNotYnETH();
        }
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  VALIDATOR REGISTRATION  --------------------------
    //--------------------------------------------------------------------------------------

    function registerValidators(
        bytes32 _depositRoot,
        ValidatorData[] calldata newValidators
    ) public onlyRole(VALIDATOR_MANAGER_ROLE) nonReentrant {

        if (validatorRegistrationPaused) {
            revert ValidatorRegistrationPaused();
        }

        if (newValidators.length == 0) {
            revert NoValidatorsProvided();
        }

        // check deposit root matches the deposit contract deposit root
        // to prevent front-running from rogue operators 
        bytes32 onchainDepositRoot = depositContractEth2.get_deposit_root();
        if (_depositRoot != onchainDepositRoot) {
            revert DepositRootChanged({_depositRoot: _depositRoot, onchainDepositRoot: onchainDepositRoot});
        }

        validateDepositDataAllocation(newValidators);

        uint256 totalDepositAmount = newValidators.length * DEFAULT_VALIDATOR_STAKE;
        ynETH.withdrawETH(totalDepositAmount); // Withdraw ETH from depositPool

        uint256 validatorsLength = newValidators.length;
        for (uint256 i = 0; i < validatorsLength; i++) {

            ValidatorData calldata validator = newValidators[i];
            if (usedValidators[validator.publicKey]) {
                revert ValidatorAlreadyUsed(validator.publicKey);
            }
            usedValidators[validator.publicKey] = true;

            _registerValidator(validator, DEFAULT_VALIDATOR_STAKE);
        }
    }

    /**
     * @notice Validates the allocation of deposit data across nodes to ensure the distribution does not increase the disparity in balances.
     * @dev This function checks if the proposed allocation of deposits (represented by `_depositData`) across the nodes would lead to a more
     * equitable distribution of validator stakes. It calculates the current and new average balances of nodes, and ensures that for each node,
     * the absolute difference between its balance and the average balance does not increase as a result of the new deposits
     * @param newValidators An array of `ValidatorData` structures representing the validator stakes to be allocated across the nodes.
     */
    function validateDepositDataAllocation(ValidatorData[] calldata newValidators) public view {

        for (uint256 i = 0; i < newValidators.length; i++) {
            uint256 nodeId = newValidators[i].nodeId;

            if (nodeId >= nodes.length) {
                revert InvalidNodeId(nodeId);
            }
        }
    }

    /// @notice Creates validator object and deposits into beacon chain
    /// @param validator Data structure to hold all data needed for depositing to the beacon chain
    function _registerValidator(
        ValidatorData calldata validator, 
        uint256 _depositAmount
    ) internal {

        uint256 nodeId = validator.nodeId;
        bytes memory withdrawalCredentials = getWithdrawalCredentials(nodeId);
        bytes32 depositDataRoot = depositRootGenerator.generateDepositRoot(validator.publicKey, validator.signature, withdrawalCredentials, _depositAmount);
        if (depositDataRoot != validator.depositDataRoot) {
            revert DepositDataRootMismatch(depositDataRoot, validator.depositDataRoot);
        }

        // Deposit to the Beacon Chain
        depositContractEth2.deposit{value: _depositAmount}(validator.publicKey, withdrawalCredentials, validator.signature, depositDataRoot);
        validators.push(Validator({publicKey: validator.publicKey, nodeId: validator.nodeId}));

        // notify node of ETH _depositAmount
        IStakingNode(nodes[nodeId]).allocateStakedETH(_depositAmount);

        emit ValidatorRegistered(
            nodeId,
            validator.signature,
            validator.publicKey,
            depositDataRoot,
            withdrawalCredentials
        );
    }

    function generateDepositRoot(
        bytes calldata publicKey,
        bytes calldata signature,
        bytes memory withdrawalCredentials,
        uint256 depositAmount
    ) public pure returns (bytes32) {
        return depositRootGenerator.generateDepositRoot(publicKey, signature, withdrawalCredentials, depositAmount);
    }

    function getWithdrawalCredentials(uint256 nodeId) public view returns (bytes memory) {

        address eigenPodAddress = address(IStakingNode(nodes[nodeId]).eigenPod());
        return generateWithdrawalCredentials(eigenPodAddress);
    }

    /// @notice Generates withdraw credentials for a validator
    /// @param _address associated with the validator for the withdraw credentials
    /// @return the generated withdraw key for the node
    function generateWithdrawalCredentials(address _address) public pure returns (bytes memory) {   
        return abi.encodePacked(bytes1(0x01), bytes11(0x0), _address);
    }

    /// @notice Toggles the pause state for validator registration.
    /// @param isPaused Boolean indicating the desired pause state for validator registration.
    function setValidatorRegistrationPaused(bool isPaused) external onlyRole(PAUSER_ROLE) {
        validatorRegistrationPaused = isPaused;
        emit ValidatorRegistrationPausedSet(isPaused);
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  STAKING NODE CREATION  ---------------------------
    //--------------------------------------------------------------------------------------

    function createStakingNode()
        public
        notZeroAddress((address(upgradeableBeacon)))
        onlyRole(STAKING_NODE_CREATOR_ROLE) 
        returns (IStakingNode) {

        uint256 nodeCount = nodes.length;

        if (nodeCount >= maxNodeCount) {
            revert TooManyStakingNodes(maxNodeCount);
        }

        BeaconProxy proxy = new BeaconProxy(address(upgradeableBeacon), "");
        IStakingNode node = IStakingNode(payable(proxy));


        initializeStakingNode(node, nodeCount);

        IEigenPod eigenPod = node.createEigenPod();

        nodes.push(node);

        emit StakingNodeCreated(address(node), address(eigenPod));

        return node;
    }

    function initializeStakingNode(IStakingNode node, uint256 nodeCount) virtual internal {

        uint64 initializedVersion = node.getInitializedVersion();
        if (initializedVersion == 0) {
            node.initialize(
                IStakingNode.Init(IStakingNodesManager(address(this)), nodeCount)
            );

            // update to the newly upgraded version.
            initializedVersion = node.getInitializedVersion();
            emit NodeInitialized(address(node), initializedVersion);
        }
         // NOTE: for future versions add additional if clauses that initialize the node 
         // for the next version while keeping the previous initializers
    }

    function registerStakingNodeImplementationContract(address _implementationContract)
        public
        onlyRole(STAKING_ADMIN_ROLE)
        notZeroAddress(_implementationContract) {

        if (address(upgradeableBeacon) != address(0)) {
            revert BeaconImplementationAlreadyExists();
        }

        upgradeableBeacon = new UpgradeableBeacon(_implementationContract, address(this));     

        emit RegisteredStakingNodeImplementationContract(address(upgradeableBeacon), _implementationContract);
    }

    function upgradeStakingNodeImplementation(address _implementationContract)
        public
        onlyRole(STAKING_ADMIN_ROLE)
        notZeroAddress(_implementationContract) {
        if (address(upgradeableBeacon) == address(0)) {
            revert NoBeaconImplementationExists();
        }
        upgradeableBeacon.upgradeTo(_implementationContract);

        uint256 nodeCount = nodes.length;

        // reinitialize all nodes
        for (uint256 i = 0; i < nodeCount; i++) {
            initializeStakingNode(nodes[i], nodeCount);
        }

        emit UpgradedStakingNodeImplementationContract(_implementationContract, nodeCount);
    }

    /// @notice Sets the maximum number of staking nodes allowed
    /// @param _maxNodeCount The maximum number of staking nodes
    function setMaxNodeCount(uint256 _maxNodeCount) public onlyRole(STAKING_ADMIN_ROLE) {
        maxNodeCount = _maxNodeCount;
        emit MaxNodeCountUpdated(_maxNodeCount);
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  WITHDRAWALS  -------------------------------------
    //--------------------------------------------------------------------------------------

    function processWithdrawnETH(uint256 nodeId, uint256 withdrawnValidatorPrincipal) external payable {
        if (address(nodes[nodeId]) != msg.sender) {
            revert NotStakingNode(msg.sender, nodeId);
        }

        uint256 rewards = msg.value - withdrawnValidatorPrincipal;

        IRewardsReceiver consensusLayerReceiver = rewardsDistributor.consensusLayerReceiver();
        (bool sent, ) = address(consensusLayerReceiver).call{value: rewards}("");
        if (!sent) {
            revert TransferFailed();
        }

        emit WithdrawnETHProcessed(nodeId, msg.value, withdrawnValidatorPrincipal, rewards);

        ynETH.processWithdrawnETH{value: withdrawnValidatorPrincipal}();
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  VIEWS  -------------------------------------------
    //--------------------------------------------------------------------------------------

    function getAllValidators() public view returns (Validator[] memory) {
        return validators;
    }

    function getAllNodes() public view returns (IStakingNode[] memory) {
        return nodes;
    }

    function nodesLength() public view returns (uint256) {
        return nodes.length;
    }

    function isStakingNodesAdmin(address _address) public view returns (bool) {
        return hasRole(STAKING_NODES_ADMIN_ROLE, _address);
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
