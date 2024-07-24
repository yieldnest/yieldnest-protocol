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

interface IEigenStrategyManagerEvents {
    event StrategyAdded(address indexed asset, address indexed strategy);
    event StakedAssetsToNode(uint256 indexed nodeId, IERC20[] assets, uint256[] amounts);
    event DepositedToEigenlayer(IERC20[] depositAssets, uint256[] depositAmounts, IStrategy[] strategiesForNode);
}

/** @title EigenStrategyManager
 *  @dev This contract handles the strategy management for ynEigen asset allocations.
 */
contract EigenStrategyManager is 
        IEigenStrategyManager,
        IEigenStrategyManagerEvents,
        Initializable,
        AccessControlUpgradeable,
        ReentrancyGuardUpgradeable
    {

    //--------------------------------------------------------------------------------------
    //----------------------------------  ERRORS  ------------------------------------------
    //--------------------------------------------------------------------------------------

    error ZeroAddress();
    error InvalidNodeId(uint256 nodeId);
    error InvalidStakingAmount(uint256 amount);
    error StrategyNotFound(address asset);
    error LengthMismatch(uint256 length1, uint256 length2);
    error AssetAlreadyExists(address asset);
    error NoStrategyDefinedForAsset(address asset);
    error StrategyAlreadySetForAsset(address asset);
    

    //--------------------------------------------------------------------------------------
    //----------------------------------  ROLES  -------------------------------------------
    //--------------------------------------------------------------------------------------

    /// @notice  Role is allowed to set the pause state
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /// @notice Role allowed to unset the pause state
    bytes32 public constant UNPAUSER_ROLE = keccak256("UNPAUSER_ROLE");

    /// @notice Controls the strategy actions
    bytes32 public constant STRATEGY_CONTROLLER_ROLE = keccak256("STRATEGY_CONTROLLER_ROLE");

    /// @notice Role allowed to manage strategies
    bytes32 public constant STRATEGY_ADMIN_ROLE = keccak256("STRATEGY_ADMIN_ROLE");

    //--------------------------------------------------------------------------------------
    //----------------------------------  CONSTANTS  ---------------------------------------
    //--------------------------------------------------------------------------------------

    IwstETH public constant wstETH = IwstETH(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
    IERC4626 public constant woETH = IERC4626(0xDcEe70654261AF21C44c093C300eD3Bb97b78192);
    IERC20 public constant oETH = IERC20(0x856c4Efb76C1D1AE02e20CEB03A2A6a08b0b8dC3);
    IERC20 public constant stETH = IERC20(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);

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
        ITokenStakingNodesManager tokenStakingNodesManager;
        address admin;
        address strategyController;
        address unpauser;
        address pauser;
        address strategyAdmin;
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
        _grantRole(STRATEGY_ADMIN_ROLE, init.strategyAdmin);

        for (uint256 i = 0; i < init.assets.length; i++) {
            if (address(init.assets[i]) == address(0) || address(init.strategies[i]) == address(0)) {
                revert ZeroAddress();
            }
            if (strategies[init.assets[i]] != IStrategy(address(0))) {
                revert AssetAlreadyExists(address(init.assets[i]));
            }
            strategies[init.assets[i]] = init.strategies[i];
            emit StrategyAdded(address(init.assets[i]), address(init.strategies[i]));
        }

        ynEigen = init.ynEigen;

        strategyManager = init.strategyManager;
        delegationManager = init.delegationManager;
        tokenStakingNodesManager = init.tokenStakingNodesManager;
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
        uint256 assetsLength = assets.length;
        uint256 amountsLength = amounts.length;

        if (assetsLength != amountsLength) {
            revert LengthMismatch(assetsLength, amountsLength);
        }

        ITokenStakingNode node = tokenStakingNodesManager.getNodeById(nodeId);
        if (address(node) == address(0)) {
            revert InvalidNodeId(nodeId);
        }

        IStrategy[] memory strategiesForNode = new IStrategy[](assetsLength);
        for (uint256 i = 0; i < assetsLength; i++) {
            IERC20 asset = assets[i];
            if (amounts[i] == 0) {
                revert InvalidStakingAmount(amounts[i]);
            }
            IStrategy strategy = strategies[asset];
            if (address(strategy) == address(0)) {
                revert StrategyNotFound(address(asset));
            }
            strategiesForNode[i] = strategy;
        }
        // Transfer assets to node
        ynEigen.retrieveAssets(assets, amounts);

        IERC20[] memory depositAssets = new IERC20[](assetsLength);
        uint256[] memory depositAmounts = new uint256[](amountsLength);

        for (uint256 i = 0; i < assetsLength; i++) {
            (IERC20 depositAsset, uint256 depositAmount) = toEigenLayerDeposit(assets[i], amounts[i]);
            depositAssets[i] = depositAsset;
            depositAmounts[i] = depositAmount;

            // Transfer each asset to the node
            depositAsset.transfer(address(node), depositAmount);
        }

        emit StakedAssetsToNode(nodeId, assets, amounts);

        node.depositAssetsToEigenlayer(depositAssets, depositAmounts, strategiesForNode);

        emit DepositedToEigenlayer(depositAssets, depositAmounts, strategiesForNode);
    }

    function toEigenLayerDeposit(
        IERC20 asset,
        uint256 amount
    ) internal returns (IERC20 depositAsset, uint256 depositAmount) {
        if (address(asset) == address(wstETH)) {
            // Adjust for wstETH
            depositAsset = stETH;
            depositAmount = wstETH.unwrap(amount); 
        } else if (address(asset) == address(woETH)) {
            // Adjust for woeth
            depositAsset = oETH; 
            // calling redeem with receiver and owner as address(this)
            depositAmount = woETH.redeem(amount, address(this), address(this)); 
        } else {
            // No adjustment needed
            depositAsset = asset;
            depositAmount = amount;
        }   
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  ADMIN  -------------------------------------------
    //--------------------------------------------------------------------------------------

    /**
     * @notice Adds a new strategy for a specific asset.
     * @param asset The asset for which the strategy is to be added.
     * @param strategy The strategy contract address to be associated with the asset.
     */
    function addStrategy(IERC20 asset, IStrategy strategy)
        external
        onlyRole(STRATEGY_ADMIN_ROLE)
        notZeroAddress(address(asset))
        notZeroAddress(address(strategy)) {
        if (address(strategies[asset]) != address(0)){
            revert StrategyAlreadySetForAsset(address(asset));
        }

        strategies[asset] = strategy;
        emit StrategyAdded(address(asset), address(strategy));
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
     * @return stakedBalance The total staked balance of the specified asset.
     */
    function getStakedAssetBalance(IERC20 asset) public view returns (uint256 stakedBalance) {
        if (address(strategies[asset]) == address(0)) {
            revert NoStrategyDefinedForAsset(address(asset));
        }

        ITokenStakingNode[] memory nodes = tokenStakingNodesManager.getAllNodes();
        uint256 nodesCount = nodes.length;
        for (uint256 i; i < nodesCount; i++ ) {
            ITokenStakingNode node = nodes[i];
            stakedBalance += _getStakedAssetBalanceForNode(asset, node);
        }
    }

    /**
     * @notice Retrieves the staked balance of a specific asset for a given node.
     * @param asset The ERC20 token for which the staked balance is to be retrieved.
     * @param nodeId The specific nodeId for which the staked balance is to be retrieved.
     * @return stakedBalance The staked balance of the specified asset for the given node.
     */
    function getStakedAssetBalanceForNode(
        IERC20 asset,
        uint256 nodeId
    ) public view returns (uint256 stakedBalance) {
        if (address(strategies[asset]) == address(0)) {
            revert NoStrategyDefinedForAsset(address(asset));
        }

        ITokenStakingNode node = tokenStakingNodesManager.getNodeById(nodeId);
        return _getStakedAssetBalanceForNode(asset, node);
    }

    function _getStakedAssetBalanceForNode(
        IERC20 asset,
        ITokenStakingNode node
    ) internal view returns (uint256 stakedBalance) {
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
