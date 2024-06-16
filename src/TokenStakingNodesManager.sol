// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {Math} from "lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {BeaconProxy} from "lib/openzeppelin-contracts/contracts/proxy/beacon/BeaconProxy.sol";
import {UpgradeableBeacon} from "lib/openzeppelin-contracts/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {AccessControlUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IStrategy} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IStrategyManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {ITokenStakingNodesManager} from "src/interfaces/ITokenStakingNodesManager.sol";
import {IDelegationManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {ILSDStakingNode} from "src/interfaces/ILSDStakingNode.sol";
import {YieldNestOracle} from "src/YieldNestOracle.sol";
import {ynBase} from "src/ynBase.sol";

interface ITokenStakingNodesManagerEvents {

    event AssetRetrieved(IERC20 asset, uint256 amount, uint256 nodeId, address sender);
    event LSDStakingNodeCreated(uint256 nodeId, address nodeAddress);
    event MaxNodeCountUpdated(uint256 maxNodeCount); 
    event DepositsPausedUpdated(bool paused);

    event RegisteredStakingNodeImplementationContract(address upgradeableBeaconAddress, address implementationContract);
    event UpgradedStakingNodeImplementationContract(address implementationContract, uint256 nodesCount);
    event NodeInitialized(address nodeAddress, uint64 initializedVersion);
}

contract TokenStakingNodesManager is AccessControlUpgradeable, ITokenStakingNodesManager, ITokenStakingNodesManagerEvents {
    using SafeERC20 for IERC20;

    //--------------------------------------------------------------------------------------
    //----------------------------------  ERRORS  ------------------------------------------
    //--------------------------------------------------------------------------------------

    error UnsupportedAsset(IERC20 asset);
    error Unauthorized();
    error InsufficientFunds();
    error Paused();
    error ZeroAmount();
    error ZeroAddress();
    error BeaconImplementationAlreadyExists();
    error NoBeaconImplementationExists();
    error TooManyStakingNodes(uint256 maxNodeCount);
    error NotLSDStakingNode(address sender, uint256 nodeId);
    error LengthMismatch(uint256 assetsCount, uint256 stakedAssetsCount);

    //--------------------------------------------------------------------------------------
    //----------------------------------  ROLES  -------------------------------------------
    //--------------------------------------------------------------------------------------

    bytes32 public constant STAKING_ADMIN_ROLE = keccak256("STAKING_ADMIN_ROLE");
    bytes32 public constant TOKEN_RESTAKING_MANAGER_ROLE = keccak256("TOKEN_RESTAKING_MANAGER_ROLE");
    bytes32 public constant TOKEN_STAKING_NODE_CREATOR_ROLE = keccak256("TOKEN_STAKING_NODE_CREATOR_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant UNPAUSER_ROLE = keccak256("UNPAUSER_ROLE");

    //--------------------------------------------------------------------------------------
    //----------------------------------  VARIABLES  ---------------------------------------
    //--------------------------------------------------------------------------------------

    IStrategyManager public strategyManager;
    IDelegationManager public delegationManager;

    UpgradeableBeacon public upgradeableBeacon;

    /// @notice Mapping of ERC20 tokens to their corresponding EigenLayer strategy contracts.
    mapping(IERC20 => IStrategy) public strategies;
    
    /**
     * @notice Array of LSD Staking Node contracts.
     * @dev These nodes are crucial for the delegation process within the YieldNest protocol. Each node represents a unique staking entity
     * that can delegate LSD tokens to various operators for yield optimization. 
     */
    ILSDStakingNode[] public nodes;
    uint256 public maxNodeCount;

    //--------------------------------------------------------------------------------------
    //----------------------------------  EVENTS  ------------------------------------------
    //--------------------------------------------------------------------------------------

    event NodeAdded(address indexed node);
    event NodeRemoved(address indexed node);
    event FundsTransferredToNode(address indexed node, uint256 amount);
    event FundsReceivedFromNode(address indexed node, uint256 amount);

    //--------------------------------------------------------------------------------------
    //----------------------------------  INITIALIZATION  ----------------------------------
    //--------------------------------------------------------------------------------------

    constructor() {
       _disableInitializers();
    }

    struct Init {
        IERC20[] assets;
        IStrategy[] strategies;
        IStrategyManager strategyManager;
        IDelegationManager delegationManager;
        uint256 maxNodeCount;
        address admin;
        address pauser;
        address unpauser;
        address stakingAdmin;
        address lsdRestakingManager;
        address lsdStakingNodeCreatorRole;
        address[] pauseWhitelist;
    }

    function initialize(Init calldata init)
        public
        notZeroAddress(address(init.strategyManager))
        notZeroAddress(address(init.oracle))
        notZeroAddress(address(init.admin))
        notZeroAddress(address(init.stakingAdmin))
        notZeroAddress(address(init.lsdRestakingManager))
        notZeroAddress(init.lsdStakingNodeCreatorRole)
        initializer {
        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, init.admin);
        _grantRole(STAKING_ADMIN_ROLE, init.stakingAdmin);
        _grantRole(TOKEN_RESTAKING_MANAGER_ROLE, init.lsdRestakingManager);
        _grantRole(TOKEN_STAKING_NODE_CREATOR_ROLE, init.lsdStakingNodeCreatorRole);
        _grantRole(PAUSER_ROLE, init.pauser);
        _grantRole(UNPAUSER_ROLE, init.unpauser);

        for (uint256 i = 0; i < init.assets.length; i++) {
            if (address(init.assets[i]) == address(0) || address(init.strategies[i]) == address(0)) {
                revert ZeroAddress();
            }
            strategies[init.assets[i]] = init.strategies[i];
        }

        strategyManager = init.strategyManager;
        delegationManager = init.delegationManager;
        maxNodeCount = init.maxNodeCount;
    }


    //--------------------------------------------------------------------------------------
    //----------------------------------  STAKING NODE CREATION  ---------------------------
    //--------------------------------------------------------------------------------------

    /**
     * @notice Creates a new LSD Staking Node using the Upgradeable Beacon pattern.
     * @dev This function creates a new BeaconProxy instance pointing to the current implementation set in the upgradeableBeacon.
     * It initializes the staking node, adds it to the nodes array, and emits an event.
     * Reverts if the maximum number of staking nodes has been reached.
     * @return ILSDStakingNode The interface of the newly created LSD Staking Node.
     */
    function createLSDStakingNode()
        public
        notZeroAddress((address(upgradeableBeacon)))
        onlyRole(TOKEN_STAKING_NODE_CREATOR_ROLE)
        returns (ILSDStakingNode) {

        uint256 nodeId = nodes.length;

        if (nodeId >= maxNodeCount) {
            revert TooManyStakingNodes(maxNodeCount);
        }

        BeaconProxy proxy = new BeaconProxy(address(upgradeableBeacon), "");
        ILSDStakingNode node = ILSDStakingNode(payable(proxy));

        initializeLSDStakingNode(node, nodeId);

        nodes.push(node);

        emit LSDStakingNodeCreated(nodeId, address(node));

        return node;
    }

    /**
     * @notice Initializes a newly created LSD Staking Node.
     * @dev This function checks the current initialized version of the node and performs initialization if it hasn't been done.
     * For future versions, additional conditional blocks should be added to handle version-specific initialization.
     * @param node The ILSDStakingNode instance to be initialized.
     * @param nodeId The ID of the staking node.
     */
    function initializeLSDStakingNode(ILSDStakingNode node, uint256 nodeId) virtual internal {

         uint64 initializedVersion = node.getInitializedVersion();
         if (initializedVersion == 0) {
             node.initialize(
               ILSDStakingNode.Init(ITokenStakingNodesManager(address(this)), nodeId)
             );

             // update version to latest
             initializedVersion = node.getInitializedVersion();
             emit NodeInitialized(address(node), initializedVersion);
         }

         // NOTE: for future versions add additional if clauses that initialize the node 
         // for the next version while keeping the previous initializers
    }

    /**
     * @notice Registers a new LSD Staking Node implementation contract.
     * @dev This function sets a new implementation contract for the LSD Staking Node by creating a new UpgradeableBeacon.
     * It can only be called once to boostrap the first implementation.
     * @param _implementationContract The address of the new LSD Staking Node implementation contract.
     */
    function registerLSDStakingNodeImplementationContract(address _implementationContract)
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
     * @notice Upgrades the LSD Staking Node implementation to a new version.
     * @dev This function upgrades the implementation contract of the LSD Staking Nodes by setting a new implementation address in the upgradeable beacon.
     * It then reinitializes all existing staking nodes to ensure they are compatible with the new implementation.
     * This function can only be called by an account with the STAKING_ADMIN_ROLE.
     * @param _implementationContract The address of the new implementation contract.
     */
    function upgradeLSDStakingNodeImplementation(address _implementationContract)  
        public 
        onlyRole(STAKING_ADMIN_ROLE) 
        notZeroAddress(_implementationContract) {

        if (address(upgradeableBeacon) == address(0)) {
            revert NoBeaconImplementationExists();
        }

        upgradeableBeacon.upgradeTo(_implementationContract);

        uint256 nodeCount = nodes.length;

        // Reinitialize all nodes to ensure compatibility with the new implementation.
        for (uint256 i = 0; i < nodeCount; i++) {
            initializeLSDStakingNode(nodes[i], nodeCount);
        }

        emit UpgradedStakingNodeImplementationContract(address(_implementationContract), nodeCount);
    }

    /// @notice Sets the maximum number of staking nodes allowed
    /// @param _maxNodeCount The maximum number of staking nodes
    function setMaxNodeCount(uint256 _maxNodeCount) public onlyRole(STAKING_ADMIN_ROLE) {
        maxNodeCount = _maxNodeCount;
        emit MaxNodeCountUpdated(_maxNodeCount);
    }

    function hasLSDRestakingManagerRole(address account) external view returns (bool) {
        return hasRole(TOKEN_RESTAKING_MANAGER_ROLE, account);
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  VIEWS  -------------------------------------------
    //--------------------------------------------------------------------------------------

    function getAllNodes() public view returns (ILSDStakingNode[] memory) {
        return nodes;
    }

    function nodesLength() public view returns (uint256) {
        return nodes.length;
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
