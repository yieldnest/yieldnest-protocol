// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {Initializable} from "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import {IStrategyManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IDelegationManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategy} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IEigenStrategyManager} from "src/interfaces/IEigenStrategyManager.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ITokenStakingNodesManager} from "src/interfaces/ITokenStakingNodesManager.sol";
import {ITokenStakingNode} from "src/interfaces/ITokenStakingNode.sol";
import {IynEigen} from "src/interfaces/IynEigen.sol";
import {IwstETH} from "src/external/lido/IwstETH.sol";
import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";

/** @title EigenStrategyManager
 *  @dev This contract handles the strategy management for ynEigen asset allocations.
 */
contract EigenStrategyManager is 
        IEigenStrategyManager,
        Initializable,
        AccessControlUpgradeable,
        ReentrancyGuardUpgradeable
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
    //----------------------------------  CONSTANTS  ---------------------------------------
    //--------------------------------------------------------------------------------------

    IwstETH public constant wstETH = IwstETH(0x7f39C581f595B53C5CC47f706bDE9B7F4aeaDe64);
    IERC4626 public constant woETH = IERC4626(0xDcEe70654261AF21C44c093C300eD3Bb97b78192);

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
        notZeroAddress(address(init.strategyController))
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
    ) external onlyRole(STRATEGY_CONTROLLER_ROLE) nonReentrant {
        require(assets.length == amounts.length, "Assets and amounts length mismatch");

        ITokenStakingNode node = tokenStakingNodesManager.getNodeById(nodeId);
        require(address(node) != address(0), "Invalid node ID");

        IStrategy[] memory strategiesForNode = new IStrategy[](assets.length);
        for (uint256 i = 0; i < assets.length; i++) {
            IERC20 asset = assets[i];
            require(amounts[i] > 0, "Staking amount must be greater than zero");
            IStrategy strategy = strategies[asset];
            require(address(strategy) != address(0), "No strategy for asset");
            strategiesForNode[i] = strategies[assets[i]];
        }
        // Transfer assets to node
        ynEigen.retrieveAssets(assets, amounts);

        IERC20[] memory depositAssets = new IERC20[](assets.length);
        uint256[] memory depositAmounts = new uint256[](amounts.length);

        for (uint256 i = 0; i < assets.length; i++) {
            (IERC20 depositAsset, uint256 depositAmount) = toEigenLayerDeposit(assets[i], amounts[i]);
            depositAssets[i] = depositAsset;
            depositAmounts[i] = depositAmount;

            // Transfer each asset to the node
            depositAsset.transfer(address(node), depositAmount);
        }

        node.depositAssetsToEigenlayer(depositAssets, depositAmounts, strategiesForNode);
    }

    function toEigenLayerDeposit(
        IERC20 asset,
        uint256 amount
    ) internal returns (IERC20 depositAsset, uint256 depositAmount) {
        if (address(asset) == address(wstETH)) {
            // Adjust for wstETH
            depositAsset = IERC20(wstETH.stETH());
            depositAmount = wstETH.unwrap(amount); 
        } else if (address(asset) == address(woETH)) {
            // Adjust for woeth
            depositAsset = IERC20(woETH.asset()); 
            // calling redeem with receiver and owner as address(this)
            depositAmount = woETH.redeem(amount, address(this), address(this)); 
        } else {
            // No adjustment needed
            depositAsset = asset;
            depositAmount = amount;
        }   
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

        stakedBalances = new uint256[](assets.length);
        // Add balances contained in each TokenStakingNode, including those managed by strategies.

        ITokenStakingNode[] memory nodes = tokenStakingNodesManager.getAllNodes();
        uint256 nodesCount = nodes.length;
        uint256 assetsCount = assets.length;
        for (uint256 j = 0; j < assetsCount; j++) {      

            IERC20 asset = assets[j];
            for (uint256 i; i < nodesCount; i++ ) {
                ITokenStakingNode node = nodes[i];
                uint256 balanceNode = asset.balanceOf(address(node));
                stakedBalances[j] += balanceNode;

                uint256 strategyBalance = toUserAssetAmount(
                    asset,
                    strategies[asset].userUnderlyingView((address(node)))
                );
                stakedBalances[j] += strategyBalance;
            }
        }
    }

    /**
     * @notice Converts the user's underlying asset amount to the equivalent user asset amount.
     * @dev This function handles the conversion for wrapped staked ETH (wstETH) and wrapped other ETH (woETH),
     *      returning the equivalent amount in the respective wrapped token.
     * @param asset The ERC20 token for which the conversion is being made.
     * @param userUnderlyingView The amount of the underlying asset.
     * @return The equivalent amount in the user asset denomination.
     */
    function toUserAssetAmount(IERC20 asset, uint256 userUnderlyingView) public view returns (uint256) {
        if (address(asset) == address(wstETH)) {
            // Adjust for wstETH using view method, converting stETH to wstETH
            return wstETH.getWstETHByStETH(userUnderlyingView);
        }
        if (address(asset) == address(woETH)) { 
            // Adjust for woETH using view method, converting oETH to woETH
            return woETH.previewDeposit(userUnderlyingView);
        }
        return userUnderlyingView;
    }

    /**
     * @notice Retrieves the total staked balance of a specific asset across all nodes.
     * @param asset The ERC20 token for which the staked balance is to be retrieved.
     * @return stakedBalances The total staked balance of the specified asset.
     */
    function getStakedAssetBalance(IERC20 asset) public view returns (uint256 stakedBalance) {
        ITokenStakingNode[] memory nodes = tokenStakingNodesManager.getAllNodes();
        uint256 nodesCount = nodes.length;
        for (uint256 i; i < nodesCount; i++ ) {
            ITokenStakingNode node = nodes[i];
            stakedBalance += getStakedAssetBalanceForNode(asset, node);
        }
    }

    /**
     * @notice Retrieves the staked balance of a specific asset for a given node.
     * @param asset The ERC20 token for which the staked balance is to be retrieved.
     * @param node The specific node for which the staked balance is to be retrieved.
     * @return stakedBalance The staked balance of the specified asset for the given node.
     */
    function getStakedAssetBalanceForNode(
        IERC20 asset,
        ITokenStakingNode node
    ) public view returns (uint256 stakedBalance) {
        uint256 balanceNode = asset.balanceOf(address(node));
        stakedBalance += balanceNode;

        uint256 strategyBalance = toUserAssetAmount(
            asset,
            strategies[asset].userUnderlyingView((address(node)))
        );
        stakedBalance += strategyBalance;
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
