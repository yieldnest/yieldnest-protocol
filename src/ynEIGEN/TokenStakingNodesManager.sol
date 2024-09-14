// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {BeaconProxy} from "lib/openzeppelin-contracts/contracts/proxy/beacon/BeaconProxy.sol";
import {UpgradeableBeacon} from "lib/openzeppelin-contracts/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {AccessControlUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IStrategyManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IDelegationManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {ITokenStakingNode} from "src/interfaces/ITokenStakingNode.sol";
import {ITokenStakingNodesManager} from "src/interfaces/ITokenStakingNodesManager.sol";
import {IynEigen} from "src/interfaces/IynEigen.sol";
import {IRedemptionAssetsVault} from "src/interfaces/IRedemptionAssetsVault.sol";
import {IEigenStrategyManager} from "src/interfaces/IEigenStrategyManager.sol";

interface ITokenStakingNodesManagerEvents {

    event AssetRetrieved(IERC20 asset, uint256 amount, uint256 nodeId, address sender);
    event TokenStakingNodeCreated(uint256 nodeId, address nodeAddress);
    event MaxNodeCountUpdated(uint256 maxNodeCount); 
    event DepositsPausedUpdated(bool paused);

    event RegisteredStakingNodeImplementationContract(address upgradeableBeaconAddress, address implementationContract);
    event UpgradedStakingNodeImplementationContract(address implementationContract, uint256 nodesCount);
    event NodeInitialized(address nodeAddress, uint64 initializedVersion);
}

interface IRedemptionAssetsVaultExt is IRedemptionAssetsVault {
    function deposit(uint256 amount, address asset) external;
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
    error NodeIdOutOfRange(uint256 nodeId);

    //--------------------------------------------------------------------------------------
    //----------------------------------  ROLES  -------------------------------------------
    //--------------------------------------------------------------------------------------

    bytes32 public constant STAKING_ADMIN_ROLE = keccak256("STAKING_ADMIN_ROLE");
    bytes32 public constant TOKEN_STAKING_NODE_OPERATOR_ROLE = keccak256("TOKEN_STAKING_NODE_OPERATOR_ROLE");
    bytes32 public constant TOKEN_STAKING_NODES_DELEGATOR_ROLE = keccak256("TOKEN_STAKING_NODES_DELEGATOR_ROLE");
    bytes32 public constant TOKEN_STAKING_NODE_CREATOR_ROLE = keccak256("TOKEN_STAKING_NODE_CREATOR_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant UNPAUSER_ROLE = keccak256("UNPAUSER_ROLE");
    bytes32 public constant WITHDRAWAL_MANAGER_ROLE = keccak256("WITHDRAWAL_MANAGER_ROLE");
    bytes32 public constant STAKING_NODES_WITHDRAWER_ROLE = keccak256("STAKING_NODES_WITHDRAWER_ROLE");

    //--------------------------------------------------------------------------------------
    //----------------------------------  VARIABLES  ---------------------------------------
    //--------------------------------------------------------------------------------------

    IStrategyManager public strategyManager;
    IDelegationManager public delegationManager;
    address public yieldNestStrategyManager;

    UpgradeableBeacon public upgradeableBeacon;
    
    /**
     * @notice Array of Token Staking Node contracts.
     * @dev These nodes are crucial for the delegation process within the YieldNest protocol. Each node represents a unique staking entity
     * that can delegate tokens to various operators for yield optimization. 
     */
    ITokenStakingNode[] public nodes;
    uint256 public maxNodeCount;

    IRedemptionAssetsVaultExt public redemptionAssetsVault;

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
        IStrategyManager strategyManager;
        IDelegationManager delegationManager;
        address yieldNestStrategyManager;
        uint256 maxNodeCount;
        address admin;
        address pauser;
        address unpauser;
        address stakingAdmin;
        address tokenStakingNodeOperator;
        address tokenStakingNodeCreatorRole;
        address tokenStakingNodesDelegator;
    }

    function initialize(Init calldata init)
        public
        notZeroAddress(address(init.strategyManager))
        notZeroAddress(address(init.admin))
        notZeroAddress(address(init.stakingAdmin))
        notZeroAddress(address(init.tokenStakingNodeOperator))
        notZeroAddress(init.tokenStakingNodeCreatorRole)
        notZeroAddress(init.tokenStakingNodesDelegator)
        initializer {
        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, init.admin);
        _grantRole(STAKING_ADMIN_ROLE, init.stakingAdmin);
        _grantRole(TOKEN_STAKING_NODE_OPERATOR_ROLE, init.tokenStakingNodeOperator);
        _grantRole(TOKEN_STAKING_NODE_CREATOR_ROLE, init.tokenStakingNodeCreatorRole);
        _grantRole(TOKEN_STAKING_NODES_DELEGATOR_ROLE, init.tokenStakingNodesDelegator);
        _grantRole(PAUSER_ROLE, init.pauser);
        _grantRole(UNPAUSER_ROLE, init.unpauser);

        strategyManager = init.strategyManager;
        delegationManager = init.delegationManager;
        yieldNestStrategyManager = init.yieldNestStrategyManager;
        maxNodeCount = init.maxNodeCount;
    }


    //--------------------------------------------------------------------------------------
    //----------------------------------  STAKING NODE CREATION  ---------------------------
    //--------------------------------------------------------------------------------------

    /**
     * @notice Creates a new Token Staking Node using the Upgradeable Beacon pattern.
     * @dev This function creates a new BeaconProxy instance pointing to the current implementation set in the upgradeableBeacon.
     * It initializes the staking node, adds it to the nodes array, and emits an event.
     * Reverts if the maximum number of staking nodes has been reached.
     * @return ITokenStakingNode The interface of the newly created Token Staking Node.
     */
    function createTokenStakingNode()
        public
        notZeroAddress((address(upgradeableBeacon)))
        onlyRole(TOKEN_STAKING_NODE_CREATOR_ROLE)
        returns (ITokenStakingNode) {

        uint256 nodeId = nodes.length;

        if (nodeId >= maxNodeCount) {
            revert TooManyStakingNodes(maxNodeCount);
        }

        BeaconProxy proxy = new BeaconProxy(address(upgradeableBeacon), "");
        ITokenStakingNode node = ITokenStakingNode(payable(proxy));

        initializeTokenStakingNode(node, nodeId);

        nodes.push(node);

        emit TokenStakingNodeCreated(nodeId, address(node));

        return node;
    }

    /**
     * @notice Initializes a newly created Token Staking Node.
     * @dev This function checks the current initialized version of the node and performs initialization if it hasn't been done.
     * For future versions, additional conditional blocks should be added to handle version-specific initialization.
     * @param node The ITokenStakingNode instance to be initialized.
     * @param nodeId The ID of the staking node.
     */
    function initializeTokenStakingNode(ITokenStakingNode node, uint256 nodeId) virtual internal {

         uint64 initializedVersion = node.getInitializedVersion();
         if (initializedVersion == 0) {
             node.initialize(
               ITokenStakingNode.Init(ITokenStakingNodesManager(address(this)), nodeId)
             );

             // update version to latest
             initializedVersion = node.getInitializedVersion();
             emit NodeInitialized(address(node), initializedVersion);
         }

         // NOTE: for future versions add additional if clauses that initialize the node 
         // for the next version while keeping the previous initializers
    }

    /**
     * @notice Registers a new Token Staking Node implementation contract.
     * @dev This function sets a new implementation contract for the Token Staking Node by creating a new UpgradeableBeacon.
     * It can only be called once to boostrap the first implementation.
     * @param _implementationContract The address of the new Token Staking Node implementation contract.
     */
    function registerTokenStakingNode(address _implementationContract)
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
     * @notice Upgrades the Token Staking Node implementation to a new version.
     * @dev This function upgrades the implementation contract of the Token Staking Nodes by setting a new implementation address in the upgradeable beacon.
     * It then reinitializes all existing staking nodes to ensure they are compatible with the new implementation.
     * This function can only be called by an account with the STAKING_ADMIN_ROLE.
     * @param _implementationContract The address of the new implementation contract.
     */
    function upgradeTokenStakingNode(address _implementationContract)  
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
            initializeTokenStakingNode(nodes[i], nodeCount);
        }

        emit UpgradedStakingNodeImplementationContract(address(_implementationContract), nodeCount);
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

    function processPrincipalWithdrawals(
        WithdrawalAction[] calldata _actions
    ) public onlyRole(WITHDRAWAL_MANAGER_ROLE)  {
        uint256 _len = _actions.length;
        for (uint256 i = 0; i < _len; ++i) {
            _processPrincipalWithdrawalForNode(_actions[i]);
        }
    }

    function _processPrincipalWithdrawalForNode(WithdrawalAction calldata _action) internal {

        uint256 _totalAmount = _action.amountToReinvest + _action.amountToQueue;

        // Update the node's asset balance and pull the assets to this contract
        ITokenStakingNode _node = nodes[_action.nodeId];
        _node.deallocateTokens(IERC20(_action.asset), _totalAmount);
        IERC20(_action.asset).safeTransferFrom(address(_node), address(this), _totalAmount);

        // Update ynEigen's balance and approve it to pull the assets
        if (_action.amountToReinvest > 0) {
            IynEigen _ynEigen = IEigenStrategyManager(yieldNestStrategyManager).ynEigen();
            IERC20(_action.asset).approve(address(_ynEigen), _action.amountToReinvest);
            _ynEigen.processWithdrawn(_action.amountToReinvest, _action.asset);
        }

        // Update the redemption assets vault's balance and approve it to pull the assets
        if (_action.amountToQueue > 0) {
            IRedemptionAssetsVaultExt _redemptionAssetsVault = redemptionAssetsVault;
            IERC20(_action.asset).approve(address(_redemptionAssetsVault), _action.amountToQueue);
            _redemptionAssetsVault.deposit(_action.amountToQueue, _action.asset);
        }

        // emit PrincipalWithdrawalProcessed(_action.nodeId, _action.amountToReinvest, _action.amountToQueue); // @todo
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  TokenStakingNode Roles  --------------------------
    //--------------------------------------------------------------------------------------

    /**
     * @notice Checks if the specified account has the Token Staking Node Operator role.
     * @param account The address to check for the role.
     * @return True if the account has the Token Staking Node Operator role, false otherwise.
     */
    function hasTokenStakingNodeOperatorRole(address account) external view returns (bool) {
        return hasRole(TOKEN_STAKING_NODE_OPERATOR_ROLE, account);
    }

    /**
     * @notice Checks if the specified address has the Token Staking Node Delegator role.
     * @param _address The address to check for the role.
     * @return True if the address has the Token Staking Node Delegator role, false otherwise.
     */
    function hasTokenStakingNodeDelegatorRole(address _address) public view returns (bool) {
        return hasRole(TOKEN_STAKING_NODES_DELEGATOR_ROLE, _address);
    }

    /**
     * @notice Checks if the specified address has the EigenStrategyManager role.
     * @param caller The address to check.
     * @return True if the specified address is the EigenStrategyManager, false otherwise.
     */
    function hasYieldNestStrategyManagerRole(address caller) public view returns (bool) {
        return caller == yieldNestStrategyManager;
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  VIEWS  -------------------------------------------
    //--------------------------------------------------------------------------------------

    /**
     * @notice Retrieves all registered token staking nodes.
     * @return An array of addresses representing all the token staking nodes.
     */
    function getAllNodes() public view returns (ITokenStakingNode[] memory) {
        return nodes;
    }

    /**
     * @notice Gets the total number of registered token staking nodes.
     * @return The total number of token staking nodes.
     */
    function nodesLength() public view returns (uint256) {
        return nodes.length;
    }

    /**
     * @notice Retrieves a staking node by its ID.
     * @param nodeId The ID of the node to retrieve.
     * @return ITokenStakingNode The staking node associated with the given ID.
     * @dev Reverts if the node ID is out of range.
     */
    function getNodeById(uint256 nodeId) public view returns (ITokenStakingNode) {
        if (nodeId >= nodes.length) {
            revert NodeIdOutOfRange(nodeId);
        }
        return nodes[nodeId];
    }

    /**
     * @notice Checks if the given address has the STAKING_NODES_WITHDRAWER_ROLE.
     * @param _address The address to check.
     * @return True if the address has the STAKING_NODES_WITHDRAWER_ROLE, false otherwise.
     */
    function isStakingNodesWithdrawer(address _address) public view returns (bool) {
        return hasRole(STAKING_NODES_WITHDRAWER_ROLE, _address);
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
