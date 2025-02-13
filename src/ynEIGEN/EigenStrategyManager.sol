// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {SafeCast} from "lib/openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import {Initializable} from "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import {IStrategyManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IDelegationManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategy} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IYieldNestStrategyManager, IRedemptionAssetsVaultExt} from "src/interfaces/IYieldNestStrategyManager.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ITokenStakingNodesManager} from "src/interfaces/ITokenStakingNodesManager.sol";
import {ITokenStakingNode} from "src/interfaces/ITokenStakingNode.sol";
import {IynEigen} from "src/interfaces/IynEigen.sol";
import {IwstETH} from "src/external/lido/IwstETH.sol";
import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IWrapper} from "src/interfaces/IWrapper.sol";
import {IAssetRegistry} from "src/interfaces/IAssetRegistry.sol";

interface IEigenStrategyManagerEvents {
    event StrategyAdded(address indexed asset, address indexed strategy);
    event StakedAssetsToNode(uint256 indexed nodeId, IERC20[] assets, uint256[] amounts);
    event DepositedToEigenlayer(IERC20[] depositAssets, uint256[] depositAmounts, IStrategy[] strategiesForNode);
    event PrincipalWithdrawalProcessed(uint256 indexed nodeId, address indexed asset, uint256 amountToReinvest, uint256 amountToQueue);
    event StrategyBalanceUpdated(address indexed asset, address indexed strategy, uint256 nodeCount, uint128 stakedBalance, uint128 withdrawnBalance);
}

interface IynEigenVars {
    function assetRegistry() external view returns (IAssetRegistry);
}

/** @title EigenStrategyManager
 *  @dev This contract handles the strategy management for ynEigen asset allocations.
 */
contract EigenStrategyManager is 
        IYieldNestStrategyManager,
        IEigenStrategyManagerEvents,
        Initializable,
        AccessControlUpgradeable,
        ReentrancyGuardUpgradeable
    {

    using SafeERC20 for IERC20;


    //--------------------------------------------------------------------------------------
    //----------------------------------  STRUCTS  -----------------------------------------
    //--------------------------------------------------------------------------------------


    struct NodeAllocation {
        uint256 nodeId;
        IERC20[] assets;
        uint256[] amounts;
    }

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
    error AssetDoesNotMatchStrategyUnderlyingToken(address asset, address strategyUnderlyingToken);
    error NodeNotSynchronized(uint256 nodeId);
    

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

    /// @notice Role allowed to manage withdrawals
    bytes32 public constant WITHDRAWAL_MANAGER_ROLE = keccak256("WITHDRAWAL_MANAGER_ROLE");

    /// @notice Role allowed to withdraw from staking nodes
    bytes32 public constant STAKING_NODES_WITHDRAWER_ROLE = keccak256("STAKING_NODES_WITHDRAWER_ROLE");

    //--------------------------------------------------------------------------------------
    //----------------------------------  CONSTANTS  ---------------------------------------
    //--------------------------------------------------------------------------------------


    //--------------------------------------------------------------------------------------
    //----------------------------------  VARIABLES  ---------------------------------------
    //--------------------------------------------------------------------------------------
    
    IynEigen public ynEigen;
    IStrategyManager public strategyManager;
    IDelegationManager public delegationManager;
    ITokenStakingNodesManager public tokenStakingNodesManager;

    // Mapping of asset to its corresponding strategy
    mapping(IERC20 => IStrategy) public strategies;

    IwstETH public wstETH;
    IERC4626 public woETH;
    IERC20 public oETH;
    IERC20 public stETH;

    IRedemptionAssetsVaultExt public redemptionAssetsVault;
    IWrapper public wrapper;

    struct StrategyBalance {
        uint128 stakedBalance;
        uint128 withdrawnBalance;
    }
    mapping(IStrategy => StrategyBalance) public strategiesBalance;

    //--------------------------------------------------------------------------------------
    //----------------------------------  INITIALIZATION  ----------------------------------
    //--------------------------------------------------------------------------------------

    constructor() {
        _disableInitializers();
    }

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
        IwstETH wstETH;
        IERC4626 woETH;
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
        wstETH = init.wstETH;
        woETH = init.woETH;
        stETH = IERC20(wstETH.stETH());
        oETH = IERC20(woETH.asset());
    }

    function initializeV2(
        address _redemptionAssetsVault,
        address _wrapper,
        address _withdrawer
    ) external reinitializer(2) notZeroAddress(_redemptionAssetsVault) notZeroAddress(_wrapper) {
        __ReentrancyGuard_init();

        redemptionAssetsVault = IRedemptionAssetsVaultExt(_redemptionAssetsVault);
        wrapper = IWrapper(_wrapper);

        _grantRole(STAKING_NODES_WITHDRAWER_ROLE, _withdrawer);
        _grantRole(WITHDRAWAL_MANAGER_ROLE, _withdrawer);

        IERC20[] memory assets = IynEigenVars(address(ynEigen)).assetRegistry().getAssets();
        uint256 assetsLength = assets.length;
        for (uint256 i = 0; i < assetsLength; i++) {
            _updateTokenStakingNodesBalances(assets[i], IStrategy(address(0)));
        }
    }

    //--------------------------------------------------------------------------------------
    //------------------------------------ ACCOUNTING  ----------------------------------------
    //--------------------------------------------------------------------------------------

    /// @notice Updates the staked balances for all nodes for a specific asset's strategy.
    /// @dev This function should be called after any operation that changes node balances.
    /// @dev In case of slashing events, users are incentivized to call this function to adjust the exchange rate.
    /// @param asset The ERC20 token for which the balances are to be updated.
    function updateTokenStakingNodesBalances(IERC20 asset) public {
        _updateTokenStakingNodesBalances(asset, strategies[asset]);
    } 

    /// @notice Updates the staked balances for all nodes for a strategies.
    /// @dev Should be called atomically after any node-balance-changing operation.
    /// @dev On a slashing events, users will have an incentive to call this function, to decrease the exchange rate.
    /// @param asset The asset for which the balances are to be updated.
    /// @param strategy The strategy for which the balances are to be updated. If not provided, we search for the strategy associated with the asset.
    function _updateTokenStakingNodesBalances(IERC20 asset, IStrategy strategy) internal {

        ITokenStakingNode[] memory nodes = tokenStakingNodesManager.getAllNodes();
        uint256 nodesCount = nodes.length;

        uint256 _strategiesBalance;
        uint256 _strategiesWithdrawalQueueBalance;
        uint256 _strategiesWithdrawnBalance;
        if (address(strategy) == address(0)) strategy = strategies[asset];
        for (uint256 i; i < nodesCount; i++ ) {
            ITokenStakingNode node = nodes[i];

            _strategiesBalance += strategy.userUnderlyingView((address(node)));

            if (!node.isOperatorSynchronized()) {
                revert NodeNotSynchronized(i);
            }

            (uint256 queuedShares, uint256 strategyWithdrawnBalance) = node.getQueuedSharesAndWithdrawn(strategy, asset);

            if (queuedShares > 0) {
                _strategiesWithdrawalQueueBalance += strategy.sharesToUnderlyingView(queuedShares);
            }

            _strategiesWithdrawnBalance += strategyWithdrawnBalance;
        }

        StrategyBalance memory _strategyBalance = StrategyBalance({
            stakedBalance: SafeCast.toUint128(_strategiesBalance + _strategiesWithdrawalQueueBalance),
            withdrawnBalance: SafeCast.toUint128(_strategiesWithdrawnBalance)
        });


        // update only if it changed
        StrategyBalance memory previousStrategyBalance = strategiesBalance[strategy];
        if (previousStrategyBalance.stakedBalance != _strategyBalance.stakedBalance ||
            previousStrategyBalance.withdrawnBalance != _strategyBalance.withdrawnBalance) {
            strategiesBalance[strategy] = _strategyBalance;

            emit StrategyBalanceUpdated(
                address(asset),
                address(strategy),
                nodesCount,
                _strategyBalance.stakedBalance,
                _strategyBalance.withdrawnBalance
            );
        }
    }

    //--------------------------------------------------------------------------------------
    //------------------------------------ DEPOSIT  ----------------------------------------
    //--------------------------------------------------------------------------------------
    
    /**
     * @notice Stakes specified amounts of assets into a specific node on EigenLayer.
     * @param nodeId The ID of the node where assets will be staked.
     * @param assets An array of ERC20 tokens to be staked.
     * @param amounts An array of amounts corresponding to each asset to be staked.
     */
   function stakeAssetsToNode(
        uint256 nodeId,
        IERC20[] memory assets,
        uint256[] memory amounts
    ) public onlyRole(STRATEGY_CONTROLLER_ROLE) nonReentrant {
        _stakeAssetsToNode(nodeId, assets, amounts);
    }

    /**
     * @notice Stakes assets to multiple nodes on EigenLayer according to the specified allocations.
     * @param allocations An array of NodeAllocation structs, each containing a node ID, an array of assets,
     *        and an array of amounts to stake on that node.
     */
    function stakeAssetsToNodes(NodeAllocation[] calldata allocations) external onlyRole(STRATEGY_CONTROLLER_ROLE) nonReentrant {
        for (uint256 i = 0; i < allocations.length; i++) {
            NodeAllocation memory allocation = allocations[i];
            _stakeAssetsToNode(allocation.nodeId, allocation.assets, allocation.amounts);
        }
    }

    function _stakeAssetsToNode(
        uint256 nodeId,
        IERC20[] memory assets,
        uint256[] memory amounts
    ) internal {
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

        // Transfer assets to address(this)
        ynEigen.retrieveAssets(assets, amounts);

        IERC20[] memory depositAssets = new IERC20[](assetsLength);
        uint256[] memory depositAmounts = new uint256[](amountsLength);

        IWrapper _wrapper = wrapper;
        for (uint256 i = 0; i < assetsLength; i++) {
            // NOTE: approving also token that will not be transferred
            IERC20(assets[i]).forceApprove(address(_wrapper), amounts[i]);
            (uint256 depositAmount, IERC20 depositAsset) = _wrapper.unwrap(amounts[i], assets[i]);
            depositAssets[i] = depositAsset;
            depositAmounts[i] = depositAmount;

            // Transfer each asset to the node
            depositAsset.safeTransfer(address(node), depositAmount);
        }

        emit StakedAssetsToNode(nodeId, assets, amounts);

        node.depositAssetsToEigenlayer(depositAssets, depositAmounts, strategiesForNode);

        for (uint256 i = 0; i < assetsLength; i++) {
            _updateTokenStakingNodesBalances(assets[i], IStrategy(address(0)));
        }

        emit DepositedToEigenlayer(depositAssets, depositAmounts, strategiesForNode);
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

        ITokenStakingNode _node = tokenStakingNodesManager.getNodeById(_action.nodeId);
        _node.deallocateTokens(IERC20(_action.asset), _totalAmount);

        if (_action.amountToReinvest > 0) {
            IynEigen _ynEigen = ynEigen;
            IERC20(_action.asset).forceApprove(address(_ynEigen), _action.amountToReinvest);
            _ynEigen.processWithdrawn(_action.amountToReinvest, _action.asset);
        }

        if (_action.amountToQueue > 0) {
            IRedemptionAssetsVaultExt _redemptionAssetsVault = redemptionAssetsVault;
            IERC20(_action.asset).forceApprove(address(_redemptionAssetsVault), _action.amountToQueue);
            _redemptionAssetsVault.deposit(_action.amountToQueue, _action.asset);
        }

        _updateTokenStakingNodesBalances(IERC20(_action.asset), IStrategy(address(0)));

        emit PrincipalWithdrawalProcessed(_action.nodeId, _action.asset, _action.amountToReinvest, _action.amountToQueue);
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  ADMIN  -------------------------------------------
    //--------------------------------------------------------------------------------------

    /**
     * @notice Adds a new strategy for a specific asset.
     * @param asset The asset for which the strategy is to be added.
     * @param strategy The strategy contract address to be associated with the asset.
     */
    function setStrategy(IERC20 asset, IStrategy strategy)
        external
        onlyRole(STRATEGY_ADMIN_ROLE)
        notZeroAddress(address(asset))
        notZeroAddress(address(strategy)) {
        if (address(strategy.underlyingToken()) != address(asset)) {
            revert AssetDoesNotMatchStrategyUnderlyingToken(address(asset), address(strategy.underlyingToken()));
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

        uint256 assetsCount = assets.length;
        for (uint256 j = 0; j < assetsCount; j++) {      
            IERC20 asset = assets[j];
            IStrategy strategy = strategies[asset];
            StrategyBalance memory balance = strategiesBalance[strategy];
            stakedBalances[j] = wrapper.toUserAssetAmount(asset, balance.stakedBalance) + balance.withdrawnBalance;
        }

        return stakedBalances;
    }

    /**
     * @notice Retrieves the total staked balance of a specific asset across all nodes.
     * @param asset The ERC20 token for which the staked balance is to be retrieved.
     * @return stakedBalance The total staked balance of the specified asset.
     */
    function getStakedAssetBalance(IERC20 asset) external view returns (uint256 stakedBalance) {
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
    ) external view returns (uint256 stakedBalance) {
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

        IStrategy strategy = strategies[asset];
        (uint256 queuedShares, uint256 strategyWithdrawnBalance) = node.getQueuedSharesAndWithdrawn(strategy, asset);
        uint256 strategyBalance = wrapper.toUserAssetAmount(
            asset,
            strategy.userUnderlyingView((address(node))) + strategy.sharesToUnderlyingView(queuedShares)
        );

        stakedBalance += strategyBalance + strategyWithdrawnBalance;   
    }

    /**
     * @notice Checks if a given asset is supported by any strategy.
     * @param asset The ERC20 token to check.
     * @return isSupported True if there is a strategy defined for the asset, false otherwise.
     */
    function supportsAsset(IERC20 asset) public view returns (bool) {
        return address(strategies[asset]) != address(0);
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
