// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {Initializable} from "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {IStrategyManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IDelegationManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategy} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IEigenStrategyManager} from "src/interfaces/IEigenStrategyManager.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ITokenStakingNodesManager} from "src/interfaces/ITokenStakingNodesManager.sol";
import {ILSDStakingNode} from "src/interfaces/ILSDStakingNode.sol";
import {IynEigen} from "src/interfaces/IynEigen.sol";

contract EigenStrategyManager is 
        IEigenStrategyManager,
        Initializable,
        AccessControlUpgradeable
    {

    //--------------------------------------------------------------------------------------
    //----------------------------------  ERRORS  ------------------------------------------
    //--------------------------------------------------------------------------------------

    error ZeroAddress();

    //--------------------------------------------------------------------------------------
    //----------------------------------  ROLES  -------------------------------------------
    //--------------------------------------------------------------------------------------

    /// @notice  Role is allowed to set the pause state
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /// @notice Role allowed to unset the pause state
    bytes32 public constant UNPAUSER_ROLE = keccak256("UNPAUSER_ROLE");

    /// @notice Controls the strategy actions
    bytes32 public constant STRATEGY_CONTROLLER_ROLE = keccak256("STRATEGY_CONTROLLER_ROLE");

    //--------------------------------------------------------------------------------------
    //----------------------------------  VARIABLES  ---------------------------------------
    //--------------------------------------------------------------------------------------
    
    IynEigen public ynEigen;
    IStrategyManager public strategyManager;
    IDelegationManager public delegationManager;
    ITokenStakingNodesManager public tokenStakingNodesManager;

    // Mapping of asset to its corresponding strategy
    mapping(IERC20 => IStrategy) public strategies;

    //--------------------------------------------------------------------------------------
    //----------------------------------  INITIALIZATION  ----------------------------------
    //--------------------------------------------------------------------------------------

    struct Init {
        IERC20[] assets;
        IStrategy[] strategies;
        IynEigen ynEigen;
        IStrategyManager strategyManager;
        IDelegationManager delegationManager;
        address admin;
        address strategyController;
        address unpauser;
        address pauser;
    }

    function initialize(Init calldata init)
        public
        notZeroAddress(address(init.strategyManager))
        notZeroAddress(address(init.admin))
        notZeroAddress(address(init.lsdRestakingManager))
        initializer {
        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, init.admin);
        _grantRole(PAUSER_ROLE, init.pauser);
        _grantRole(UNPAUSER_ROLE, init.unpauser);
        _grantRole(STRATEGY_CONTROLLER_ROLE, init.strategyController);

        for (uint256 i = 0; i < init.assets.length; i++) {
            if (address(init.assets[i]) == address(0) || address(init.strategies[i]) == address(0)) {
                revert ZeroAddress();
            }
            strategies[init.assets[i]] = init.strategies[i];
        }

        ynEigen = init.ynEigen;

        strategyManager = init.strategyManager;
        delegationManager = init.delegationManager;
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  STRATEGY  ----------------------------------------
    //--------------------------------------------------------------------------------------
    
    /**
     * @notice Stakes specified amounts of assets into a specific node on EigenLayer.
     * @param nodeId The ID of the node where assets will be staked.
     * @param assets An array of ERC20 tokens to be staked.
     * @param amounts An array of amounts corresponding to each asset to be staked.
     */
    function stakeAssetsToNode(
        uint256 nodeId,
        IERC20[] calldata assets,
        uint256[] calldata amounts
    ) external onlyRole(STRATEGY_CONTROLLER_ROLE) {
        require(assets.length == amounts.length, "Assets and amounts length mismatch");

        ILSDStakingNode node = tokenStakingNodesManager.getNodeById(nodeId);
        require(address(node) != address(0), "Invalid node ID");

        IStrategy[] memory strategiesForNode = new IStrategy[](assets.length);
        for (uint256 i = 0; i < assets.length; i++) {
            strategiesForNode[i] = strategies[assets[i]];
        }

        address[] memory destinations = new address[](assets.length);
        for (uint256 i = 0; i < assets.length; i++) {
            IERC20 asset = assets[i];
            uint256 amount = amounts[i];

            require(amount > 0, "Staking amount must be greater than zero");
            require(address(strategies[asset]) != address(0), "No strategy for asset");

            destinations[i] = address(node);
        }


        // Transfer assets to node
        ynEigen.retrieveAssets(assets, amounts, destinations);

        node.depositAssetsToEigenlayer(assets, amounts, strategiesForNode);
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  VIEWS  -------------------------------------------
    //--------------------------------------------------------------------------------------

    /**
     * @notice Retrieves the total balances of staked assets across all nodes.
     * @param assets An array of ERC20 tokens for which balances are to be retrieved.
     * @return stakedBalances An array of total balances for each asset, indexed in the same order as the `assets` array.
     */
    function getStakedAssetsBalances(IERC20[] calldata assets) public view returns (uint256[] memory stakedBalances) {

        // Add balances contained in each LSDStakingNode, including those managed by strategies.

        ILSDStakingNode[] memory nodes = tokenStakingNodesManager.getAllNodes();
        uint256 nodesCount = nodes.length;
        uint256 assetsCount = assets.length;
        for (uint256 i; i < nodesCount; i++ ) {
            
            ILSDStakingNode node = nodes[i];
            for (uint256 j = 0; j < assetsCount; j++) {
                
                IERC20 asset = assets[j];
                uint256 balanceNode = asset.balanceOf(address(node));
                stakedBalances[j] += balanceNode;

                uint256 strategyBalance = strategies[asset].userUnderlyingView((address(node)));
                stakedBalances[j] += strategyBalance;
            }
        }
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
