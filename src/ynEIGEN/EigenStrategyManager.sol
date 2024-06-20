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
import {ILSDStakingNode} from "src/interfaces/ILSDStakingNode.sol";
import {IynEigen} from "src/interfaces/IynEigen.sol";

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

    IwstETH public constant wstETH = IERC20(0x7f39C581F595B53c5cC47F706BDE9B7F4AEADe64);
    IERC4626 public constant woETH = IERC20(0xdcee70654261af21c44c093c300ed3bb97b78192);

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
    ) external onlyRole(STRATEGY_CONTROLLER_ROLE) nonReentrant {
        require(assets.length == amounts.length, "Assets and amounts length mismatch");

        ILSDStakingNode node = tokenStakingNodesManager.getNodeById(nodeId);
        require(address(node) != address(0), "Invalid node ID");

        IStrategy[] memory strategiesForNode = new IStrategy[](assets.length);
        for (uint256 i = 0; i < assets.length; i++) {
            require(amounts[i] > 0, "Staking amount must be greater than zero");
            IStrategy strategy = address(strategies[asset]);
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
            depositAsset = woETH.asset(); 
            depositAmount = woETH.redeem(amount); 
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

                uint256 strategyBalance = toUserAssetAmount(
                    asset,
                    strategies[asset].userUnderlyingView((address(node)))
                );
                stakedBalances[j] += strategyBalance;
            }
        }
    }

    function toUserAssetAmount(IERC20 asset, uint256 userUnderlyingView) public view returns (uint256) {
        uint256 underlyingAmount;
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
