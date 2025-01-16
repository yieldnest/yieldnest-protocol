// SPDX-License-Identifier: BSD-3-Clause License
pragma solidity ^0.8.24;

import {TimelockController} from "@openzeppelin-v5/contracts/governance/TimelockController.sol";

import {IDelegationManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategyManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";

import {ITokenStakingNodesManager} from "src/interfaces/ITokenStakingNodesManager.sol";
import {IRedeemableAsset} from "src/interfaces/IRedeemableAsset.sol";
import {IynEigen} from "src/interfaces/IynEigen.sol";
import {IRateProvider} from "src/interfaces/IRateProvider.sol";
import {IAssetRegistry} from "src/interfaces/IAssetRegistry.sol";
import {IYieldNestStrategyManager} from "src/interfaces/IYieldNestStrategyManager.sol";
import {ynEigen} from "src/ynEIGEN/ynEigen.sol";
import {TokenStakingNode} from "src/ynEIGEN/TokenStakingNode.sol";
import {EigenStrategyManager} from "src/ynEIGEN/EigenStrategyManager.sol";
import {AssetRegistry} from "src/ynEIGEN/AssetRegistry.sol";
import {TokenStakingNodesManager} from "src/ynEIGEN/TokenStakingNodesManager.sol";
import {TokenStakingNode} from "src/ynEIGEN/TokenStakingNode.sol";
import {AssetRegistry} from "src/ynEIGEN/AssetRegistry.sol";
import {ynEigenDepositAdapter} from "src/ynEIGEN/ynEigenDepositAdapter.sol";
import {ynEigenViewer} from "src/ynEIGEN/ynEigenViewer.sol";
import {YnEigenInit, YnEigenProxies} from "./YnEigenStructs.sol";
import {LSDWrapper} from "src/ynEIGEN/LSDWrapper.sol";
import {RedemptionAssetsVault} from "src/ynEIGEN/RedemptionAssetsVault.sol";
import {WithdrawalQueueManager} from "src/WithdrawalQueueManager.sol";

import {IwstETH} from "src/external/lido/IwstETH.sol";
import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {TransparentUpgradeableProxy} from
    "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

interface IYnEigenFactory {
    event YnEigenDeployed(
        ynEigen ynEigen,
        EigenStrategyManager eigenStrategyManager,
        TokenStakingNodesManager tokenStakingNodesManager,
        TokenStakingNode tokenStakingNode,
        AssetRegistry assetRegistry,
        ynEigenDepositAdapter ynEigenDepositAdapter,
        IRateProvider rateProvider,
        TimelockController timelock,
        ynEigenViewer viewer
    );
}

contract YnEigenFactory is IYnEigenFactory {
    function _deployProxy(address implementation, address controller) internal returns (address proxy) {
        proxy = address(new TransparentUpgradeableProxy(implementation, controller, ""));
    }

    function deploy(YnEigenInit calldata init) external returns (YnEigenProxies memory _proxies) {

        // Deploy proxies
        _proxies.ynToken = ynEigen(_deployProxy(init.implementations.ynEigen, init.timelock));
        _proxies.eigenStrategyManager = EigenStrategyManager(_deployProxy(init.implementations.eigenStrategyManager, init.timelock));
        _proxies.tokenStakingNodesManager = TokenStakingNodesManager(_deployProxy(init.implementations.tokenStakingNodesManager, init.timelock));
        _proxies.tokenStakingNode = TokenStakingNode(init.implementations.tokenStakingNode);
        _proxies.assetRegistry = AssetRegistry(_deployProxy(init.implementations.assetRegistry, init.timelock));
        _proxies.ynEigenDepositAdapterInstance = ynEigenDepositAdapter(_deployProxy(init.implementations.depositAdapter, init.timelock));
        _proxies.rateProvider = IRateProvider(_deployProxy(init.implementations.rateProvider, init.timelock));
        _proxies.redemptionAssetsVault = RedemptionAssetsVault(_deployProxy(init.implementations.redemptionAssetsVault, init.timelock));
        _proxies.withdrawalQueueManager = WithdrawalQueueManager(_deployProxy(init.implementations.withdrawalQueueManager, init.timelock));
        _proxies.lsdWrapper = LSDWrapper(_deployProxy(init.implementations.lsdWrapper, init.timelock));
        _proxies.timelock = TimelockController(payable(init.timelock));

        // Initialize ynToken
        _proxies.ynToken.initialize(
            ynEigen.Init({
                name: init.name,
                symbol: init.symbol,
                admin: init.actors.ADMIN,
                pauser: init.actors.PAUSE_ADMIN,
                unpauser: init.actors.UNPAUSE_ADMIN,
                yieldNestStrategyManager: address(_proxies.eigenStrategyManager),
                assetRegistry: IAssetRegistry(address(_proxies.assetRegistry)),
                pauseWhitelist: new address[](0)
            })
        );

        // Initialize eigenStrategyManager
        _proxies.eigenStrategyManager.initialize(
            EigenStrategyManager.Init({
                assets: init.assets,
                strategies: init.strategies,
                ynEigen: IynEigen(address(_proxies.ynToken)),
                strategyManager: IStrategyManager(init.chainAddresses.STRATEGY_MANAGER),
                delegationManager: IDelegationManager(init.chainAddresses.DELEGATION_MANAGER),
                tokenStakingNodesManager: ITokenStakingNodesManager(address(_proxies.tokenStakingNodesManager)),
                admin: init.actors.ADMIN,
                pauser: init.actors.PAUSE_ADMIN,
                unpauser: init.actors.UNPAUSE_ADMIN,
                strategyController: init.actors.STRATEGY_CONTROLLER,
                strategyAdmin: init.actors.EIGEN_STRATEGY_ADMIN,
                wstETH: IwstETH(init.chainAddresses.WSTETH_ADDRESS),
                woETH: IERC4626(init.chainAddresses.WOETH_ADDRESS)
            })
        );

        // Initialize assetRegistry
        _proxies.assetRegistry.initialize(
            AssetRegistry.Init({
                assets: init.assets,
                rateProvider: IRateProvider(address(_proxies.rateProvider)),
                yieldNestStrategyManager: IYieldNestStrategyManager(address(_proxies.eigenStrategyManager)),
                ynEigen: IynEigen(address(_proxies.ynToken)),
                admin: init.actors.ADMIN,
                pauser: init.actors.PAUSE_ADMIN,
                unpauser: init.actors.UNPAUSE_ADMIN,
                assetManagerRole: init.actors.ASSET_MANAGER_ADMIN
            })
        );

        // Initialize tokenStakingNodesManager
        _proxies.tokenStakingNodesManager.initialize(
            TokenStakingNodesManager.Init({
                admin: address(this), // Placeholder; changed post tokenStakingNode registration
                stakingAdmin: address(this), // Placeholder; changed post tokenStakingNode registration
                strategyManager: IStrategyManager(init.chainAddresses.STRATEGY_MANAGER),
                delegationManager: IDelegationManager(init.chainAddresses.DELEGATION_MANAGER),
                yieldNestStrategyManager: address(_proxies.eigenStrategyManager),
                maxNodeCount: init.maxNodeCount,
                pauser: init.actors.PAUSE_ADMIN,
                unpauser: init.actors.UNPAUSE_ADMIN,
                tokenStakingNodeOperator: init.actors.TOKEN_STAKING_NODE_OPERATOR,
                tokenStakingNodeCreatorRole: init.actors.STAKING_NODE_CREATOR,
                tokenStakingNodesDelegator: init.actors.STAKING_NODES_DELEGATOR_ADMIN
            })
        );

        // initialize eigenStrategyManager
        {
            _proxies.eigenStrategyManager.initializeV2(address(_proxies.redemptionAssetsVault), address(_proxies.lsdWrapper), init.actors.ADMIN);
        }

        // initialize RedemptionAssetsVault
        {
            RedemptionAssetsVault.Init memory _init = RedemptionAssetsVault.Init({
                admin: init.actors.ADMIN,
                redeemer: address(_proxies.withdrawalQueueManager),
                ynEigen: _proxies.ynToken,
                assetRegistry: _proxies.assetRegistry
            });
            _proxies.redemptionAssetsVault.initialize(_init);
        }

        // initialize WithdrawalQueueManager
        {
            WithdrawalQueueManager.Init memory _init = WithdrawalQueueManager.Init({
                name: "ynLSDe Withdrawal Manager",
                symbol: "ynLSDeWM",
                redeemableAsset: IRedeemableAsset(address(_proxies.ynToken)),
                redemptionAssetsVault: _proxies.redemptionAssetsVault,
                admin: init.actors.ADMIN,
                withdrawalQueueAdmin: init.actors.ADMIN,
                redemptionAssetWithdrawer: init.actors.ADMIN,
                requestFinalizer:  init.actors.ADMIN,
                // withdrawalFee: 500, // 0.05%
                withdrawalFee: 0,
                feeReceiver: init.actors.ADMIN
            });
            _proxies.withdrawalQueueManager.initialize(_init);
        }

        // Register tokenStakingNode
        _proxies.tokenStakingNodesManager.registerTokenStakingNode(address(_proxies.tokenStakingNode));

        // Set roles post tokenStakingNode registration
        _proxies.tokenStakingNodesManager.grantRole(_proxies.tokenStakingNodesManager.DEFAULT_ADMIN_ROLE(), init.actors.ADMIN);
        _proxies.tokenStakingNodesManager.grantRole(_proxies.tokenStakingNodesManager.STAKING_ADMIN_ROLE(), init.timelock);
        _proxies.tokenStakingNodesManager.revokeRole(_proxies.tokenStakingNodesManager.STAKING_ADMIN_ROLE(), address(this));
        _proxies.tokenStakingNodesManager.revokeRole(_proxies.tokenStakingNodesManager.DEFAULT_ADMIN_ROLE(), address(this));

        // ynEigenDepositAdapter
        _proxies.ynEigenDepositAdapterInstance.initialize(
            ynEigenDepositAdapter.Init({
                ynEigen: address(_proxies.ynToken),
                wstETH: init.chainAddresses.WSTETH_ADDRESS,
                woETH: init.chainAddresses.WOETH_ADDRESS,
                admin: init.actors.ADMIN
            })
        );

        // ynEigenViewer
        {
            ynEigenViewer viewerImplementation = new ynEigenViewer(
                address(_proxies.assetRegistry), address(_proxies.ynToken), address(_proxies.tokenStakingNodesManager), address(_proxies.rateProvider)
            );
            _proxies.viewer = ynEigenViewer(_deployProxy(address(viewerImplementation), init.actors.YN_SECURITY_COUNCIL));
        }

        emit YnEigenDeployed(
            _proxies.ynToken,
            _proxies.eigenStrategyManager,
            _proxies.tokenStakingNodesManager,
            _proxies.tokenStakingNode,
            _proxies.assetRegistry,
            _proxies.ynEigenDepositAdapterInstance,
            _proxies.rateProvider,
            _proxies.timelock,
            _proxies.viewer
        );
    }
}
