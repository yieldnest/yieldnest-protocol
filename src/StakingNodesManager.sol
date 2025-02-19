// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {Initializable} from "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {BeaconProxy} from "lib/openzeppelin-contracts/contracts/proxy/beacon/BeaconProxy.sol";
import {AccessControlUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import {depositRootGenerator} from "src/external/ethereum/DepositRootGenerator.sol";
import {UpgradeableBeacon} from "lib/openzeppelin-contracts/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {IDepositContract} from "src/external/ethereum/IDepositContract.sol";
import {IDelegationManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IRewardsCoordinator} from "lib/eigenlayer-contracts/src/contracts/interfaces/IRewardsCoordinator.sol";
import {IRewardsDistributor,IRewardsReceiver, RewardsType} from "src/interfaces/IRewardsDistributor.sol";
import {IEigenPodManager,IEigenPod} from "lib/eigenlayer-contracts/src/contracts/interfaces/IEigenPodManager.sol";
import {IStrategyManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IStakingNode} from "src/interfaces/IStakingNode.sol";
import {IStakingNodesManager} from "src/interfaces/IStakingNodesManager.sol";
import {IynETH} from "src/interfaces/IynETH.sol";
import {IRedemptionAssetsVault} from "src/interfaces/IRedemptionAssetsVault.sol";


interface StakingNodesManagerEvents {
    event StakingNodeCreated(address indexed nodeAddress, address indexed podAddress);   
    event ValidatorRegistered(uint256 nodeId, bytes signature, bytes pubKey, bytes32 depositRoot, bytes withdrawalCredentials);
    event MaxNodeCountUpdated(uint256 maxNodeCount);
    event ValidatorRegistrationPausedSet(bool isPaused);
    event WithdrawnETHRewardsProcessed(uint256 nodeId, RewardsType rewardsType, uint256 rewards);
    event RegisteredStakingNodeImplementationContract(address upgradeableBeaconAddress, address implementationContract);
    event UpgradedStakingNodeImplementationContract(address implementationContract, uint256 nodesCount);
    event NodeInitialized(address nodeAddress, uint64 initializedVersion);
    event PrincipalWithdrawalProcessed(uint256 nodeId, uint256 amountToReinvest, uint256 amountToQueue, uint256 rewardsAmount);
    event ETHReceived(address sender, uint256 amount);
    event TotalETHStakedUpdated(uint256 totalETHStaked);
}

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
contract StakingNodesManager is
    IStakingNodesManager,
    Initializable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    StakingNodesManagerEvents {

    //--------------------------------------------------------------------------------------
    //----------------------------------  ERRORS  ------------------------------------------
    //--------------------------------------------------------------------------------------

    error ValidatorAlreadyUsed(bytes publicKey);
    error DepositDataRootMismatch(bytes32 depositDataRoot, bytes32 expectedDepositDataRoot);
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
    error InvalidRewardsType(RewardsType rewardsType);
    error ValidatorUnused(bytes publicKey);
    error ValidatorNotWithdrawn(bytes publicKey, IEigenPod.VALIDATOR_STATUS status);
    error NodeNotSynchronized();

    //--------------------------------------------------------------------------------------
    //----------------------------------  ROLES  -------------------------------------------
    //--------------------------------------------------------------------------------------

    /// @notice  Role is allowed to set system parameters
    bytes32 public constant STAKING_ADMIN_ROLE = keccak256("STAKING_ADMIN_ROLE");

    /// @notice  Role controls all staking nodes
    bytes32 public constant STAKING_NODES_OPERATOR_ROLE = keccak256("STAKING_NODES_OPERATOR_ROLE");

    /// @notice Role is able to delegate staking operations
    bytes32 public constant STAKING_NODES_DELEGATOR_ROLE = keccak256("STAKING_NODES_DELEGATOR_ROLE");

    /// @notice  Role is able to register validators
    bytes32 public constant VALIDATOR_MANAGER_ROLE = keccak256("VALIDATOR_MANAGER_ROLE");

    /// @notice Role is able to create staking nodes
    bytes32 public constant STAKING_NODE_CREATOR_ROLE = keccak256("STAKING_NODE_CREATOR_ROLE");

    /// @notice  Role is allowed to set the pause state
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /// @notice Role is able to unpause the system
    bytes32 public constant UNPAUSER_ROLE = keccak256("UNPAUSER_ROLE");

    /// @notice Role is able to manage withdrawals
    bytes32 public constant WITHDRAWAL_MANAGER_ROLE = keccak256("WITHDRAWAL_MANAGER_ROLE");

    /// @notice Role is able to manage specific withdrawals for staking nodes
    bytes32 public constant STAKING_NODES_WITHDRAWER_ROLE = keccak256("STAKING_NODES_WITHDRAWER_ROLE");

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
    /// @dev redemptionAssetsVault replaces the slot formerly used by: IDelayedWithdrawalRouter public delayedWithdrawalRouter;
    address private ___deprecated_delayedWithdrawalRouter;
    IStrategyManager public strategyManager;
    
    UpgradeableBeacon public upgradeableBeacon;

    IynETH public ynETH;
    IRewardsDistributor public rewardsDistributor;

    IStakingNode[] public nodes;
    uint256 public maxNodeCount;

    Validator[] public validators;
    mapping(bytes pubkey => bool) usedValidators;

    bool public validatorRegistrationPaused;
    IRedemptionAssetsVault public redemptionAssetsVault;
    uint256 public totalETHStaked;

    IRewardsCoordinator public rewardsCoordinator;

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
        address stakingNodesOperator;
        address stakingNodesDelegator;
        address validatorManager;
        address stakingNodeCreatorRole;
        address pauser;
        address unpauser;

        // internal
        uint256 maxNodeCount;
        IynETH ynETH;
        IRewardsDistributor rewardsDistributor; 

        // external contracts
        IDepositContract depositContract;
        IEigenPodManager eigenPodManager;
        IDelegationManager delegationManager;
        IStrategyManager strategyManager;
    }

    struct Init2 {
        IRedemptionAssetsVault redemptionAssetsVault;
        address withdrawalManager;
        address stakingNodesWithdrawer;
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
        notZeroAddress(init.stakingNodesOperator)
        notZeroAddress(init.validatorManager)
        notZeroAddress(init.stakingNodeCreatorRole)
        notZeroAddress(init.pauser)
        notZeroAddress(init.unpauser) {
        _grantRole(DEFAULT_ADMIN_ROLE, init.admin);
        _grantRole(STAKING_ADMIN_ROLE, init.stakingAdmin);
        _grantRole(STAKING_NODES_DELEGATOR_ROLE, init.stakingNodesDelegator);
        _grantRole(VALIDATOR_MANAGER_ROLE, init.validatorManager);
        _grantRole(STAKING_NODES_OPERATOR_ROLE, init.stakingNodesOperator);
        _grantRole(STAKING_NODE_CREATOR_ROLE, init.stakingNodeCreatorRole);
        _grantRole(PAUSER_ROLE, init.pauser);
        _grantRole(UNPAUSER_ROLE, init.unpauser);
    }

    function initializeExternalContracts(Init calldata init)
        internal
        notZeroAddress(address(init.depositContract))
        notZeroAddress(address(init.eigenPodManager))
        notZeroAddress(address(init.delegationManager))
        notZeroAddress(address(init.strategyManager)) {
        // Ethereum
        depositContractEth2 = init.depositContract;    

        // Eigenlayer
        eigenPodManager = init.eigenPodManager;    
        delegationManager = init.delegationManager;
        strategyManager = init.strategyManager;
    }

    // TODO: hardcode these values instead of setting them as parameters
    function initializeV2(Init2 calldata init)
        external
        notZeroAddress(address(init.redemptionAssetsVault))
        notZeroAddress(init.withdrawalManager)
        notZeroAddress(address(init.stakingNodesWithdrawer))
        reinitializer(2)
        onlyRole(DEFAULT_ADMIN_ROLE) {
        
        // TODO: review role access here for what can execute this
        redemptionAssetsVault = init.redemptionAssetsVault;
        _grantRole(WITHDRAWAL_MANAGER_ROLE, init.withdrawalManager);
        _grantRole(STAKING_NODES_WITHDRAWER_ROLE, init.stakingNodesWithdrawer);

        // Zero out deprecated variable
        ___deprecated_delayedWithdrawalRouter = address(0);
    }

    function initializeV3(
        IRewardsCoordinator _rewardsCoordinator
    ) external reinitializer(3) {
        if (address(_rewardsCoordinator) == address(0)) revert ZeroAddress();
        rewardsCoordinator = _rewardsCoordinator;
        // TODO: commenting this for now because getETHBalance() is not available in current deployed version of  stakingNode on holesky
        // uint256 updatedTotalETHStaked = 0;
        // IStakingNode[] memory _nodes = getAllNodes();
        // for (uint256 i = 0; i < _nodes.length; i++) {
        //     updatedTotalETHStaked += _nodes[i].getETHBalance();
        // }
        // emit TotalETHStakedUpdated(updatedTotalETHStaked);
        // totalETHStaked = updatedTotalETHStaked;
    }

    receive() external payable {
        emit ETHReceived(msg.sender, msg.value);
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  VALIDATOR REGISTRATION  --------------------------
    //--------------------------------------------------------------------------------------

    /**
     * @notice Registers new validators to the system.
     * @dev This function can only be called by an account with the `VALIDATOR_MANAGER_ROLE`.
     * @param newValidators An array of `ValidatorData` containing the data of the validators to be registered.
     */
    function registerValidators(
        ValidatorData[] calldata newValidators
    ) public onlyRole(VALIDATOR_MANAGER_ROLE) nonReentrant {

        if (validatorRegistrationPaused) {
            revert ValidatorRegistrationPaused();
        }

        if (newValidators.length == 0) {
            revert NoValidatorsProvided();
        }

        validateNodes(newValidators);

        uint256 totalDepositAmount = newValidators.length * DEFAULT_VALIDATOR_STAKE;
        ynETH.withdrawETH(totalDepositAmount); // Withdraw ETH from depositPool

        uint256 newValidatorCount = newValidators.length;
        for (uint256 i = 0; i < newValidatorCount; i++) {

            ValidatorData calldata validator = newValidators[i];
            if (usedValidators[validator.publicKey]) {
                revert ValidatorAlreadyUsed(validator.publicKey);
            }
            usedValidators[validator.publicKey] = true;

            _registerValidator(validator, DEFAULT_VALIDATOR_STAKE);
        }

        // After registering validators, update the total ETH staked
        updateTotalETHStaked();
    }

    /**
     * @notice Validates the correct number of nodes
     * @param newValidators An array of `ValidatorData` structures
     */
    function validateNodes(ValidatorData[] calldata newValidators) public view {

        uint256 nodeCount = nodes.length;

        for (uint256 i = 0; i < newValidators.length; i++) {
            uint256 nodeId = newValidators[i].nodeId;

            if (nodeId >= nodeCount) {
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

    /**
     * @notice Generates a deposit root hash using the provided validator information and deposit amount.
     * @param publicKey The public key of the validator.
     * @param signature The signature of the validator.
     * @param withdrawalCredentials The withdrawal credentials for the validator.
     * @param depositAmount The amount of ETH to be deposited.
     * @return The generated deposit root hash as a bytes32 value.
     */
    function generateDepositRoot(
        bytes calldata publicKey,
        bytes calldata signature,
        bytes memory withdrawalCredentials,
        uint256 depositAmount
    ) public pure returns (bytes32) {
        return depositRootGenerator.generateDepositRoot(publicKey, signature, withdrawalCredentials, depositAmount);
    }

    /**
     * @notice Retrieves the withdrawal credentials for a given node.
     * @param nodeId The ID of the node for which to retrieve the withdrawal credentials.
     * @return The withdrawal credentials as a byte array.
     */
    function getWithdrawalCredentials(uint256 nodeId) public view returns (bytes memory) {
        address eigenPodAddress = address(IStakingNode(nodes[nodeId]).eigenPod());
        return generateWithdrawalCredentials(eigenPodAddress);
    }

    /**
     * @notice Generates withdraw credentials for a validator
     * @param _address Address associated with the validator for the withdraw credentials
     * @return The generated withdraw key for the node
     */
    function generateWithdrawalCredentials(address _address) public pure returns (bytes memory) {   
        return abi.encodePacked(bytes1(0x01), bytes11(0x0), _address);
    }

    /**
     * @notice Pauses validator registration.
     */
    function pauseValidatorRegistration() external onlyRole(PAUSER_ROLE) {
        validatorRegistrationPaused = true;
        emit ValidatorRegistrationPausedSet(true);
    }

    /**
     * @notice Unpauses validator registration.
     */
    function unpauseValidatorRegistration() external onlyRole(UNPAUSER_ROLE) {
        validatorRegistrationPaused = false;
        emit ValidatorRegistrationPausedSet(false);
    }
    //--------------------------------------------------------------------------------------
    //----------------------------------  STAKING NODE CREATION  ---------------------------
    //--------------------------------------------------------------------------------------

    /**
     * @notice Creates a new staking node using a BeaconProxy.
     * @dev This function requires the caller to have the STAKING_NODE_CREATOR_ROLE.
     * It checks if the maximum number of staking nodes has been reached and reverts if so.
     * A new BeaconProxy is created and initialized, and a new EigenPod is created for the node.
     * @return node The newly created IStakingNode instance.
     */
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

    /**
     * @notice Initializes a staking node with the necessary version-specific initializations.
     * @dev This function handles the versioned initialization of a staking node. It checks the current
     * initialized version of the node and performs the necessary initialization steps. If the node
     * is at version 0, it initializes it to version 1. If the node is at version 1, it initializes
     * it to version 2. This function should be extended with additional conditions for future versions.
     * @param node The staking node to initialize.
     * @param nodeCount The index of the node in the nodes array, used for initialization parameters.
     */
    function initializeStakingNode(IStakingNode node, uint256 nodeCount) virtual internal {
        uint64 initializedVersion = node.getInitializedVersion();
        if (initializedVersion == 0) {
            node.initialize(
                IStakingNode.Init(IStakingNodesManager(address(this)), nodeCount)
            );

            // Update to the newly upgraded version.
            initializedVersion = node.getInitializedVersion();
            emit NodeInitialized(address(node), initializedVersion);
        }

        if (initializedVersion == 1) {
            node.initializeV2(0);
            initializedVersion = node.getInitializedVersion();
        }

        if (initializedVersion == 2) {
            node.initializeV3();
            initializedVersion = node.getInitializedVersion();
        }

        if (initializedVersion == 3) {
            node.initializeV4();
            initializedVersion = node.getInitializedVersion();
        }

        // NOTE: For future versions, add additional if clauses that initialize the node 
        // for the next version while keeping the previous initializers.
    }

    /**
     * @notice Registers a new implementation contract for staking nodes by creating a new upgradeable beacon.
     * @dev This function can only be called by an account with the STAKING_ADMIN_ROLE. It will fail if a beacon implementation already exists.
     * @param _implementationContract The address of the new implementation contract for staking nodes.
     */
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

    /**
     * @notice Upgrades the staking node implementation to a new contract.
     * @dev This function can only be called by an account with the STAKING_ADMIN_ROLE. It will fail if no beacon implementation exists.
     * @param _implementationContract The address of the new implementation contract for staking nodes.
     */
    function upgradeStakingNodeImplementation(address _implementationContract)
        public
        onlyRole(STAKING_ADMIN_ROLE)
        notZeroAddress(_implementationContract) {
        _upgradeStakingNodeImplementation(_implementationContract);
    }


    function _upgradeStakingNodeImplementation(address _implementationContract) internal {
        if (address(upgradeableBeacon) == address(0)) {
            revert NoBeaconImplementationExists();
        }
        upgradeableBeacon.upgradeTo(_implementationContract);

        uint256 nodeCount = nodes.length;

        // Reinitialize all nodes
        for (uint256 i = 0; i < nodeCount; i++) {
            initializeStakingNode(nodes[i], nodeCount);
        }

        emit UpgradedStakingNodeImplementationContract(_implementationContract, nodeCount);

    }
    
    /**
     * @notice Sets the maximum number of staking nodes allowed
     * @param _maxNodeCount The maximum number of staking nodes
     */
    function setMaxNodeCount(uint256 _maxNodeCount) public onlyRole(STAKING_ADMIN_ROLE) {
        maxNodeCount = _maxNodeCount;
        emit MaxNodeCountUpdated(_maxNodeCount);
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  WITHDRAWALS  -------------------------------------
    //--------------------------------------------------------------------------------------

    /**
     * @notice Processes and forwards rewards to the appropriate rewards receiver based on the type of rewards.
     * @dev This function can only be called by the staking node itself.
     * @param nodeId The ID of the staking node sending the rewards.
     * @param rewardsType The type of rewards being processed (ConsensusLayer or ExecutionLayer).
     */
    function processRewards(uint256 nodeId, RewardsType rewardsType) external payable {
        if (address(nodes[nodeId]) != msg.sender) {
            revert NotStakingNode(msg.sender, nodeId);
        }
        _processRewards(nodeId, rewardsType, msg.value);
    }

    function _processRewards(uint256 nodeId, RewardsType rewardsType, uint256 rewards) internal {
        IRewardsReceiver receiver;

        if (rewardsType == RewardsType.ConsensusLayer) {
            receiver = rewardsDistributor.consensusLayerReceiver();
        } else if (rewardsType == RewardsType.ExecutionLayer) {
            receiver = rewardsDistributor.executionLayerReceiver();
        } else {
            revert InvalidRewardsType(rewardsType);
        }

        (bool sent, ) = address(receiver).call{value: rewards}("");
        if (!sent) {
            revert TransferFailed();
        }

        emit WithdrawnETHRewardsProcessed(nodeId, rewardsType, rewards);
    }

    /**
     * @notice Processes an array of principal withdrawals.
     * @param actions Array of WithdrawalAction containing details for each withdrawal.
     */
    function processPrincipalWithdrawals(
        WithdrawalAction[] memory actions
    ) public onlyRole(WITHDRAWAL_MANAGER_ROLE)  {
        for (uint256 i = 0; i < actions.length; i++) {
            _processPrincipalWithdrawalForNode(actions[i]);
        }

        // After processing all withdrawals, update the total ETH staked across all nodes
        // This ensures the global ETH staked counter stays in sync with individual node balances
        updateTotalETHStaked();
    }

    /**
     * @notice Processes principal withdrawals for a single node, specifying how much goes back into ynETH and how much goes to the withdrawal queue.
     * @param action The WithdrawalAction containing details for the withdrawal.
     */
    function _processPrincipalWithdrawalForNode(WithdrawalAction memory action) internal {
        uint256 nodeId = action.nodeId;
        uint256 amountToReinvest = action.amountToReinvest;
        uint256 amountToQueue = action.amountToQueue;

        // The rewardsAmount is trusted off-chain input provided in the WithdrawalAction struct.
        // It represents the portion of the withdrawn amount that is considered as rewards.
        // This value is determined off-chain by analyzing the difference between
        // the initial stake and the total withdrawn amount.
        //
        // This design trade-off is a result of how Eigenlayer M3 pepe no long providees
        // clear separation between principal and rewards amount and they both exit through the 
        // Queued Withdrawals mechanism.
        // 
        // SECURITY NOTE:
        // The accuracy and integrity of this value relies on the off-chain process
        // that calculates it. There's an implicit trust that the WITHDRAWAL_MANAGER_ROLE
        // will provide correct and verified data and that principal is not counted as Rewards
        // and applied a fee.
        uint256 rewardsAmount = action.rewardsAmount;

        // Calculate the total amount to be processed by summing reinvestment, rewards and queuing amounts
        uint256 totalAmount = amountToReinvest + amountToQueue + rewardsAmount;

        // Retrieve the staking node object using the nodeId
        IStakingNode node = nodes[nodeId];

        // Deallocate the specified total amount of ETH from the staking node
        node.deallocateStakedETH(totalAmount);


        // If there is an amount specified to reinvest, process it through ynETH
        if (amountToReinvest > 0) {
            ynETH.processWithdrawnETH{value: amountToReinvest}();
        }

        // If there is an amount specified to queue, send it to the withdrawal assets vault
        if (amountToQueue > 0) {
            (bool success, ) = address(redemptionAssetsVault).call{value: amountToQueue}("");
            if (!success) {
                revert TransferFailed();
            }
        }

        // If there is an amount of rewards specified, handle that
        if (rewardsAmount > 0) {

            // IMPORTANT: Impact on totalAssets()
            // After charging the rewards fee, the totalAssets() of the system may decrease.
            // Steps:
            // 1. The full rewardsAmount is removed from the staking node's balance (which is part of totalAssets).
            // 2. Only the remainingRewards (after fees) are reinvested back to the system.
            // 3. The fees are sent to a separate fee receiver and are no longer part of the system's totalAssets.

            (bool sent, ) = address(rewardsDistributor.consensusLayerReceiver()).call{value: rewardsAmount}("");
            if (!sent) {
                revert TransferFailed();
            }
            // process rewards immediately to avoid large totalAssets() fluctuations
            rewardsDistributor.processRewards();
        }

        // Emit an event to log the processed principal withdrawal details
        emit PrincipalWithdrawalProcessed(nodeId, amountToReinvest, amountToQueue, rewardsAmount);
    }
    /**
     * @notice Updates the total amount of ETH staked across all nodes in the system
     * @dev Iterates through all staking nodes, checks their synchronization status,
     *      and sums up their ETH balances to calculate the new total.
     *      Reverts if any node is not properly synchronized.
     * @custom:throws NodeNotSynchronized if any node is not synchronized with the delegation manager
     */
    function updateTotalETHStaked() public {
        uint256 updatedTotalETHStaked = 0;
        IStakingNode[] memory allNodes = getAllNodes();
        for (uint256 i = 0; i < allNodes.length; i++) {
            updatedTotalETHStaked += allNodes[i].getETHBalance();
        }

        emit TotalETHStakedUpdated(updatedTotalETHStaked);
        
        totalETHStaked = updatedTotalETHStaked;
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  VIEWS  -------------------------------------------
    //--------------------------------------------------------------------------------------

    /**
     * @notice Retrieves all registered validators.
     * @return An array of Validator structs representing all registered validators.
     */
    function getAllValidators() public view returns (Validator[] memory) {
        return validators;
    }

    /**
     * @notice Retrieves all staking nodes.
     * @return An array of IStakingNode contracts representing all staking nodes.
     */
    function getAllNodes() public view returns (IStakingNode[] memory) {
        return nodes;
    }

    /**
     * @notice Gets the total number of staking nodes.
     * @return The number of staking nodes.
     */
    function nodesLength() public view returns (uint256) {
        return nodes.length;
    }

    /**
     * @notice Checks if the given address has the STAKING_NODES_OPERATOR_ROLE.
     * @param _address The address to check.
     * @return True if the address has the STAKING_NODES_OPERATOR_ROLE, false otherwise.
     */
    function isStakingNodesOperator(address _address) public view returns (bool) {
        return hasRole(STAKING_NODES_OPERATOR_ROLE, _address);
    }

    /**
     * @notice Checks if the given address has the STAKING_NODES_DELEGATOR_ROLE.
     * @param _address The address to check.
     * @return True if the address has the STAKING_NODES_DELEGATOR_ROLE, false otherwise.
     */
    function isStakingNodesDelegator(address _address) public view returns (bool) {
        return hasRole(STAKING_NODES_DELEGATOR_ROLE, _address);
    }

    /**
     * @notice Checks if the given address has the STAKING_NODES_WITHDRAWER_ROLE.
     * @param _address The address to check.
     * @return True if the address has the STAKING_NODES_WITHDRAWER_ROLE, false otherwise.
     */
    function isStakingNodesWithdrawer(address _address) public view returns (bool) {
        return hasRole(STAKING_NODES_WITHDRAWER_ROLE, _address);
    }

    /**
     * @notice Calculates the total amount of ETH deposited across all staking nodes and includes available redemption assets.
     * @dev This function sums the ETH balances of all staking nodes and optionally includes the ETH available in the redemption assets vault.
     *      Including the redemption assets can expose the system to a donation attack if not properly bootstrapped.
     * @return totalETHDeposited The total amount of ETH deposited in the system.
     */
    function totalDeposited() external view returns (uint256) {

        // Get the total ETH staked across all nodes from the cached totalETHStaked variable
        uint256 totalETHDeposited = totalETHStaked;

        // NOTE: Counting the availableRedemptionAssets towards totalDeposited
        //  opens up ynETH to donation attack for a non boostrapped system.
        if (address(redemptionAssetsVault) != address(0)) {
            totalETHDeposited += redemptionAssetsVault.availableRedemptionAssets();
        }

        return totalETHDeposited;
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
