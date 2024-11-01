// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {TransparentUpgradeableProxy} from "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";


import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IStrategy} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";

import {IRateProvider} from "src/interfaces/IRateProvider.sol";
import {ynEigen} from "src/ynEIGEN/ynEigen.sol";
import {TokenStakingNode} from "src/ynEIGEN/TokenStakingNode.sol";
import {LSDRateProvider} from "src/ynEIGEN/LSDRateProvider.sol";
import {HoleskyLSDRateProvider} from "src/testnet/HoleksyLSDRateProvider.sol";
import {EigenStrategyManager} from "src/ynEIGEN/EigenStrategyManager.sol";
import {AssetRegistry} from "src/ynEIGEN/AssetRegistry.sol";
import {TokenStakingNodesManager} from "src/ynEIGEN/TokenStakingNodesManager.sol";
import {ynEigenDepositAdapter} from "src/ynEIGEN/ynEigenDepositAdapter.sol";
import {ynEigenViewer} from "src/ynEIGEN/ynEigenViewer.sol";
import {LSDWrapper} from "src/ynEIGEN/LSDWrapper.sol";
import {RedemptionAssetsVault} from "src/ynEIGEN/RedemptionAssetsVault.sol";
import {WithdrawalQueueManager} from "src/WithdrawalQueueManager.sol";

import {BaseYnEigenScript} from "script/ynEigen/BaseYnEigenScript.s.sol";

import {YnEigenFactory} from "./YnEigenFactory.sol";
import {YnEigenInit, YnEigenActors, YnEigenChainAddresses, YnEigenImplementations, YnEigenProxies} from "./YnEigenStructs.sol";

import {ynEigen} from "src/ynEIGEN/ynEigen.sol";
import {EigenStrategyManager} from "src/ynEIGEN/EigenStrategyManager.sol";
import {TokenStakingNodesManager} from "src/ynEIGEN/TokenStakingNodesManager.sol";
import {AssetRegistry} from "src/ynEIGEN/AssetRegistry.sol";
import {ynEigenDepositAdapter} from "src/ynEIGEN/ynEigenDepositAdapter.sol";
import {ynEigenViewer} from "src/ynEIGEN/ynEigenViewer.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IRateProvider} from "src/interfaces/IRateProvider.sol";

contract YnEigenDeployer is BaseYnEigenScript {
    // TODO: update this for new chains
    function _getTimelockDelay() internal view returns (uint256) {
        if (block.chainid == 17000) {
            // Holesky
            return 15 minutes;
        } else if (block.chainid == 1) {
            // Mainnet
            return 3 days;
        } else {
            revert UnsupportedChainId(block.chainid);
        }
    }

    // TODO: update this for new chains and assets
    function _getRateProviderImplementation() internal returns (address rateProviderImplementation) {
        bytes32 hashedSymbol = keccak256(abi.encodePacked(inputs.symbol));
        if (block.chainid == 17000) {
            // Holesky
            if (hashedSymbol == keccak256(abi.encodePacked("ynLSDe"))) {
                rateProviderImplementation = address(new HoleskyLSDRateProvider());
            } else {
                revert UnsupportedAsset(inputs.symbol, block.chainid);
            }
        } else if (block.chainid == 1) {
            // Mainnet
            if (hashedSymbol == keccak256(abi.encodePacked("ynLSDe"))) {
                rateProviderImplementation = address(new LSDRateProvider());
            } else {
                revert UnsupportedAsset(inputs.symbol, block.chainid);
            }
        } else {
            revert UnsupportedChainId(block.chainid);
        }
    }

    function _deploy() internal {
        YnEigenInit memory init;

        {
            IERC20[] memory assets = new IERC20[](inputs.assets.length);
            IStrategy[] memory strategies = new IStrategy[](inputs.assets.length);

            for (uint256 i = 0; i < inputs.assets.length; i++) {
                Asset memory asset = inputs.assets[i];
                IERC20 token = IERC20(asset.token);
                IStrategy strategy = IStrategy(asset.strategy);

                assets[i] = token;
                strategies[i] = strategy;
            }

            YnEigenActors memory ynEigenActors;

            {
                ynEigenActors = YnEigenActors({
                    ADMIN: actors.admin.ADMIN,
                    PAUSE_ADMIN: actors.ops.PAUSE_ADMIN,
                    UNPAUSE_ADMIN: actors.admin.UNPAUSE_ADMIN,
                    STAKING_NODES_DELEGATOR_ADMIN: actors.admin.STAKING_NODES_DELEGATOR,
                    ASSET_MANAGER_ADMIN: actors.admin.ASSET_MANAGER,
                    EIGEN_STRATEGY_ADMIN: actors.admin.EIGEN_STRATEGY_ADMIN,
                    STAKING_NODE_CREATOR: actors.ops.STAKING_NODE_CREATOR,
                    STRATEGY_CONTROLLER: actors.ops.STRATEGY_CONTROLLER,
                    TOKEN_STAKING_NODE_OPERATOR: actors.ops.TOKEN_STAKING_NODE_OPERATOR,
                    YN_SECURITY_COUNCIL: actors.wallets.YNSecurityCouncil
                });
            }

            YnEigenChainAddresses memory ynEigenChainAddresses;

            {
                ynEigenChainAddresses = YnEigenChainAddresses({
                    WSTETH_ADDRESS: chainAddresses.lsd.WSTETH_ADDRESS,
                    WOETH_ADDRESS: chainAddresses.lsd.WOETH_ADDRESS,
                    STRATEGY_MANAGER: chainAddresses.eigenlayer.STRATEGY_MANAGER_ADDRESS,
                    DELEGATION_MANAGER: chainAddresses.eigenlayer.DELEGATION_MANAGER_ADDRESS
                });
            }

            vm.startBroadcast();
            YnEigenImplementations memory implementations;
            {
                implementations = YnEigenImplementations({
                    ynEigen: address(new ynEigen()),
                    rateProvider: _getRateProviderImplementation(),
                    eigenStrategyManager: address(new EigenStrategyManager()),
                    tokenStakingNodesManager: address(new TokenStakingNodesManager()),
                    tokenStakingNode: address(new TokenStakingNode()),
                    assetRegistry: address(new AssetRegistry()),
                    depositAdapter: address(new ynEigenDepositAdapter()),
                    redemptionAssetsVault: address(new RedemptionAssetsVault()),
                    withdrawalQueueManager: address(new WithdrawalQueueManager()),
                    lsdWrapper: address(new LSDWrapper(
                        chainAddresses.lsd.WSTETH_ADDRESS,
                        chainAddresses.lsd.WOETH_ADDRESS,
                        chainAddresses.lsd.OETH_ADDRESS,
                        chainAddresses.lsd.STETH_ADDRESS
                    ))
                });
            }

            TimelockController timelock;
            // Deploy timelock
            {
                address[] memory _proposers = new address[](1);
                _proposers[0] = actors.wallets.YNSecurityCouncil;
                address[] memory _executors = new address[](1);
                _executors[0] = actors.wallets.YNSecurityCouncil;
                timelock = new TimelockController(
                    _getTimelockDelay(), _proposers, _executors, actors.wallets.YNSecurityCouncil
                );
            }

            init = YnEigenInit({
                name: inputs.name,
                symbol: inputs.symbol,
                maxNodeCount: 10,
                timelock: address(timelock),
                assets: assets,
                strategies: strategies,
                actors: ynEigenActors,
                chainAddresses: ynEigenChainAddresses,
                implementations: implementations
            });
        }

        {
            YnEigenFactory factory = new YnEigenFactory();

            YnEigenProxies memory proxies = factory.deploy(init);

            vm.stopBroadcast();

            ProxyAddresses memory proxyAddressesEmpty = ProxyAddresses(
                TransparentUpgradeableProxy(payable(address(0))),
                ProxyAdmin(address(0)),
                address(0)
            );
            Deployment memory deployment = Deployment({
                ynEigen: proxies.ynToken,
                assetRegistry: proxies.assetRegistry,
                eigenStrategyManager: proxies.eigenStrategyManager,
                tokenStakingNodesManager: proxies.tokenStakingNodesManager,
                tokenStakingNodeImplementation: proxies.tokenStakingNode,
                ynEigenDepositAdapterInstance: proxies.ynEigenDepositAdapterInstance,
                rateProvider: proxies.rateProvider,
                upgradeTimelock: proxies.timelock,
                viewer: proxies.viewer,
                redemptionAssetsVault: proxies.redemptionAssetsVault,
                withdrawalQueueManager: proxies.withdrawalQueueManager,
                wrapper: proxies.lsdWrapper,
                proxies: DeploymentProxies({
                    ynEigen: proxyAddressesEmpty,
                    assetRegistry: proxyAddressesEmpty,
                    eigenStrategyManager: proxyAddressesEmpty,
                    tokenStakingNodesManager: proxyAddressesEmpty,
                    rateProvider: proxyAddressesEmpty,
                    ynEigenDepositAdapter: proxyAddressesEmpty,
                    ynEigenViewer: proxyAddressesEmpty,
                    redemptionAssetsVault: proxyAddressesEmpty,
                    withdrawalQueueManager: proxyAddressesEmpty,
                    wrapper: proxyAddressesEmpty
                })
            });

            saveDeployment(deployment);
        }
    }
}
