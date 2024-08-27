// SPDX-License-Identifier: BSD-3-Clause License
pragma solidity ^0.8.24;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

import {IDelegationManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategyManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";

import {ITokenStakingNodesManager} from "src/interfaces/ITokenStakingNodesManager.sol";

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
import {YnEigenInit} from "./YnEigenStructs.sol";

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

    function deploy(YnEigenInit calldata init)
        external
        returns (
            ynEigen ynToken,
            EigenStrategyManager eigenStrategyManager,
            TokenStakingNodesManager tokenStakingNodesManager,
            TokenStakingNode tokenStakingNode,
            AssetRegistry assetRegistry,
            ynEigenDepositAdapter ynEigenDepositAdapterInstance,
            IRateProvider rateProvider,
            TimelockController timelock,
            ynEigenViewer viewer
        )
    {
        // Deploy proxies
        ynToken = ynEigen(_deployProxy(init.implementations.ynEigen, init.timelock));
        eigenStrategyManager =
            EigenStrategyManager(_deployProxy(init.implementations.eigenStrategyManager, init.timelock));
        tokenStakingNodesManager =
            TokenStakingNodesManager(_deployProxy(init.implementations.tokenStakingNodesManager, init.timelock));
        tokenStakingNode = TokenStakingNode(init.implementations.tokenStakingNode);
        assetRegistry = AssetRegistry(_deployProxy(init.implementations.assetRegistry, init.timelock));
        ynEigenDepositAdapterInstance =
            ynEigenDepositAdapter(_deployProxy(init.implementations.depositAdapter, init.timelock));
        rateProvider = IRateProvider(_deployProxy(init.implementations.rateProvider, init.timelock));
        timelock = TimelockController(payable(init.timelock));
        // proxy controller set to YNSecurityCouncil since ynEigenViewer does not run production on-chain SC logic
        viewer = ynEigenViewer(_deployProxy(address(init.implementations.viewer), init.actors.YN_SECURITY_COUNCIL));

        // Initialize ynToken
        ynToken.initialize(
            ynEigen.Init({
                name: init.name,
                symbol: init.symbol,
                admin: init.actors.ADMIN,
                pauser: init.actors.PAUSE_ADMIN,
                unpauser: init.actors.UNPAUSE_ADMIN,
                yieldNestStrategyManager: address(eigenStrategyManager),
                assetRegistry: IAssetRegistry(address(assetRegistry)),
                pauseWhitelist: new address[](0)
            })
        );

        // Initialize eigenStrategyManager
        eigenStrategyManager.initialize(
            EigenStrategyManager.Init({
                assets: init.assets,
                strategies: init.strategies,
                ynEigen: IynEigen(address(ynToken)),
                strategyManager: IStrategyManager(init.chainAddresses.STRATEGY_MANAGER),
                delegationManager: IDelegationManager(init.chainAddresses.DELEGATION_MANAGER),
                tokenStakingNodesManager: ITokenStakingNodesManager(address(tokenStakingNodesManager)),
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
        assetRegistry.initialize(
            AssetRegistry.Init({
                assets: init.assets,
                rateProvider: IRateProvider(address(rateProvider)),
                yieldNestStrategyManager: IYieldNestStrategyManager(address(eigenStrategyManager)),
                ynEigen: IynEigen(address(ynToken)),
                admin: init.actors.ADMIN,
                pauser: init.actors.PAUSE_ADMIN,
                unpauser: init.actors.UNPAUSE_ADMIN,
                assetManagerRole: init.actors.ASSET_MANAGER_ADMIN
            })
        );

        // Initialize tokenStakingNodesManager
        tokenStakingNodesManager.initialize(
            TokenStakingNodesManager.Init({
                admin: address(this), // Placeholder; changed post tokenStakingNode registration
                stakingAdmin: address(this), // Placeholder; changed post tokenStakingNode registration
                strategyManager: IStrategyManager(init.chainAddresses.STRATEGY_MANAGER),
                delegationManager: IDelegationManager(init.chainAddresses.DELEGATION_MANAGER),
                yieldNestStrategyManager: address(eigenStrategyManager),
                maxNodeCount: init.maxNodeCount,
                pauser: init.actors.PAUSE_ADMIN,
                unpauser: init.actors.UNPAUSE_ADMIN,
                tokenStakingNodeOperator: init.actors.TOKEN_STAKING_NODE_OPERATOR,
                tokenStakingNodeCreatorRole: init.actors.STAKING_NODE_CREATOR,
                tokenStakingNodesDelegator: init.actors.STAKING_NODES_DELEGATOR_ADMIN
            })
        );

        // Register tokenStakingNode
        tokenStakingNodesManager.registerTokenStakingNode(address(tokenStakingNode));

        // Reset roles post tokenStakingNode registration
        tokenStakingNodesManager.grantRole(tokenStakingNodesManager.DEFAULT_ADMIN_ROLE(), init.actors.ADMIN);
        tokenStakingNodesManager.grantRole(tokenStakingNodesManager.STAKING_ADMIN_ROLE(), init.timelock);
        tokenStakingNodesManager.revokeRole(tokenStakingNodesManager.STAKING_ADMIN_ROLE(), address(this));
        tokenStakingNodesManager.revokeRole(tokenStakingNodesManager.DEFAULT_ADMIN_ROLE(), address(this));

        // Initialize ynEigenDepositAdapter
        ynEigenDepositAdapterInstance.initialize(
            ynEigenDepositAdapter.Init({
                ynEigen: address(ynToken),
                wstETH: init.chainAddresses.WSTETH_ADDRESS,
                woETH: init.chainAddresses.WOETH_ADDRESS,
                admin: init.actors.ADMIN
            })
        );

        // Initialize ynEigenViewer
        viewer.initialize(
            address(assetRegistry), address(ynToken), address(tokenStakingNodesManager), address(rateProvider)
        );

        emit YnEigenDeployed(
            ynToken,
            eigenStrategyManager,
            tokenStakingNodesManager,
            tokenStakingNode,
            assetRegistry,
            ynEigenDepositAdapterInstance,
            rateProvider,
            timelock,
            viewer
        );
    }
}
