// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {TransparentUpgradeableProxy} from
    "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IDelegationManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategyManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IStrategy} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";

import {ITokenStakingNodesManager} from "src/interfaces/ITokenStakingNodesManager.sol";

import {IynEigen} from "src/interfaces/IynEigen.sol";
import {IRateProvider} from "src/interfaces/IRateProvider.sol";
import {IAssetRegistry} from "src/interfaces/IAssetRegistry.sol";
import {IYieldNestStrategyManager} from "src/interfaces/IYieldNestStrategyManager.sol";
import {IYieldNestStrategyManager} from "src/interfaces/IYieldNestStrategyManager.sol";
import {ynEigen} from "src/ynEIGEN/ynEigen.sol";
import {TokenStakingNode} from "src/ynEIGEN/TokenStakingNode.sol";
import {LSDRateProvider} from "src/ynEIGEN/LSDRateProvider.sol";
import {HoleskyLSDRateProvider} from "src/testnet/HoleksyLSDRateProvider.sol";
import {EigenStrategyManager} from "src/ynEIGEN/EigenStrategyManager.sol";
import {AssetRegistry} from "src/ynEIGEN/AssetRegistry.sol";
import {TokenStakingNodesManager} from "src/ynEIGEN/TokenStakingNodesManager.sol";
import {ynEigenDepositAdapter} from "src/ynEIGEN/ynEigenDepositAdapter.sol";
import {ynEigenViewer} from "src/ynEIGEN/ynEigenViewer.sol";

import {BaseYnEigenScript} from "script/BaseYnEigenScript.s.sol";

import {IwstETH} from "src/external/lido/IwstETH.sol";
import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";

contract YnEigenDeployer is BaseYnEigenScript {
    IDelegationManager public delegationManager;
    IStrategyManager public strategyManager;

    ynEigen public ynToken;
    LSDRateProvider public rateProvider;
    EigenStrategyManager public eigenStrategyManager;
    TokenStakingNodesManager public tokenStakingNodesManager;
    AssetRegistry public assetRegistry;
    ynEigenDepositAdapter public ynEigenDepositAdapterInstance;
    TokenStakingNode public tokenStakingNodeImplementation;
    ynEigenViewer public viewer;
    TimelockController public timelock;

    // TODO: update this new chains
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
        vm.startBroadcast();

        delegationManager = IDelegationManager(chainAddresses.eigenlayer.DELEGATION_MANAGER_ADDRESS);
        strategyManager = IStrategyManager(chainAddresses.eigenlayer.STRATEGY_MANAGER_ADDRESS);

        // Deploy timelock
        {
            // Configure TimelockController roles:
            // - YNSecurityCouncil is set as both proposer and executor
            // This setup ensures that only the security council can propose, cancel and execute
            // And the Timelock adds the necessary delay for each upgrade.
            address[] memory _proposers = new address[](1);
            _proposers[0] = actors.wallets.YNSecurityCouncil;
            address[] memory _executors = new address[](1);
            _executors[0] = actors.wallets.YNSecurityCouncil;

            timelock = new TimelockController(
                _getTimelockDelay(),
                _proposers,
                _executors,
                actors.wallets.YNSecurityCouncil // admin
            );
        }

        // Deploy implementations
        {
            ynEigen ynEigenImplementation = new ynEigen();
            TransparentUpgradeableProxy ynEigenProxy =
                new TransparentUpgradeableProxy(address(ynEigenImplementation), address(timelock), "");
            ynToken = ynEigen(address(ynEigenProxy));
        }

        {
            address rateProviderImplementation = _getRateProviderImplementation();
            TransparentUpgradeableProxy rateProviderProxy =
                new TransparentUpgradeableProxy(address(rateProviderImplementation), address(timelock), "");
            rateProvider = LSDRateProvider(address(rateProviderProxy));
        }

        IERC20[] memory assets = new IERC20[](inputs.assets.length);
        IStrategy[] memory strategies = new IStrategy[](inputs.assets.length);

        for (uint256 i = 0; i < inputs.assets.length; i++) {
            Asset memory asset = inputs.assets[i];
            IERC20 token = IERC20(asset.token);
            IStrategy strategy = IStrategy(asset.strategy);

            assets[i] = token;
            strategies[i] = strategy;
        }

        {
            EigenStrategyManager eigenStrategyManagerImplementation = new EigenStrategyManager();
            TransparentUpgradeableProxy eigenStrategyManagerProxy =
                new TransparentUpgradeableProxy(address(eigenStrategyManagerImplementation), address(timelock), "");
            eigenStrategyManager = EigenStrategyManager(address(eigenStrategyManagerProxy));
        }

        {
            TokenStakingNodesManager tokenStakingNodesManagerImplementation = new TokenStakingNodesManager();
            TransparentUpgradeableProxy tokenStakingNodesManagerProxy =
                new TransparentUpgradeableProxy(address(tokenStakingNodesManagerImplementation), address(timelock), "");
            tokenStakingNodesManager = TokenStakingNodesManager(address(tokenStakingNodesManagerProxy));
        }

        {
            AssetRegistry assetRegistryImplementation = new AssetRegistry();
            TransparentUpgradeableProxy assetRegistryProxy =
                new TransparentUpgradeableProxy(address(assetRegistryImplementation), address(timelock), "");
            assetRegistry = AssetRegistry(address(assetRegistryProxy));
        }

        // Initialize ynToken
        {
            address[] memory pauseWhitelist = new address[](0);

            ynEigen.Init memory ynInit = ynEigen.Init({
                name: inputs.name,
                symbol: inputs.symbol,
                admin: actors.admin.ADMIN,
                pauser: actors.ops.PAUSE_ADMIN,
                unpauser: actors.admin.UNPAUSE_ADMIN,
                yieldNestStrategyManager: address(eigenStrategyManager),
                assetRegistry: IAssetRegistry(address(assetRegistry)),
                pauseWhitelist: pauseWhitelist
            });
            ynToken.initialize(ynInit);
        }

        {
            EigenStrategyManager.Init memory eigenStrategyManagerInit = EigenStrategyManager.Init({
                assets: assets,
                strategies: strategies,
                ynEigen: IynEigen(address(ynToken)),
                strategyManager: IStrategyManager(address(chainAddresses.eigenlayer.STRATEGY_MANAGER_ADDRESS)),
                delegationManager: IDelegationManager(address(chainAddresses.eigenlayer.DELEGATION_MANAGER_ADDRESS)),
                tokenStakingNodesManager: ITokenStakingNodesManager(address(tokenStakingNodesManager)),
                admin: actors.admin.ADMIN,
                strategyController: actors.ops.STRATEGY_CONTROLLER,
                unpauser: actors.admin.UNPAUSE_ADMIN,
                pauser: actors.ops.PAUSE_ADMIN,
                strategyAdmin: actors.admin.EIGEN_STRATEGY_ADMIN,
                wstETH: IwstETH(chainAddresses.ynEigen.WSTETH_ADDRESS),
                woETH: IERC4626(chainAddresses.ynEigen.WOETH_ADDRESS)
            });
            eigenStrategyManager.initialize(eigenStrategyManagerInit);
        }

        {
            AssetRegistry.Init memory assetRegistryInit = AssetRegistry.Init({
                assets: assets,
                rateProvider: IRateProvider(address(rateProvider)),
                yieldNestStrategyManager: IYieldNestStrategyManager(address(eigenStrategyManager)),
                ynEigen: IynEigen(address(ynToken)),
                admin: actors.admin.ADMIN,
                pauser: actors.ops.PAUSE_ADMIN,
                unpauser: actors.admin.UNPAUSE_ADMIN,
                assetManagerRole: actors.admin.ASSET_MANAGER
            });
            assetRegistry.initialize(assetRegistryInit);
        }

        {
            // Explanation of the use of DEFAULT_SIGNER in the script:
            // DEFAULT_SIGNER is used as a placeholder for the initial administrative roles during setup
            // to allow registering the implementation of TokenStakingNode as part of this script.
            // It will be replaced by specific actor roles at the end of the script.
            TokenStakingNodesManager.Init memory tokenStakingNodesManagerInit = TokenStakingNodesManager.Init({
                admin: actors.eoa.DEFAULT_SIGNER, // change at end of script
                stakingAdmin: actors.eoa.DEFAULT_SIGNER, // change at end of script
                strategyManager: IStrategyManager(chainAddresses.eigenlayer.STRATEGY_MANAGER_ADDRESS),
                delegationManager: IDelegationManager(chainAddresses.eigenlayer.DELEGATION_MANAGER_ADDRESS),
                yieldNestStrategyManager: address(eigenStrategyManager),
                maxNodeCount: 10,
                pauser: actors.ops.PAUSE_ADMIN,
                unpauser: actors.admin.UNPAUSE_ADMIN,
                tokenStakingNodeOperator: actors.ops.TOKEN_STAKING_NODE_OPERATOR,
                tokenStakingNodeCreatorRole: actors.ops.STAKING_NODE_CREATOR,
                tokenStakingNodesDelegator: actors.admin.STAKING_NODES_DELEGATOR
            });

            tokenStakingNodesManager.initialize(tokenStakingNodesManagerInit);
        }

        {
            tokenStakingNodeImplementation = new TokenStakingNode();
            tokenStakingNodesManager.registerTokenStakingNode(address(tokenStakingNodeImplementation));
        }

        // Post Deployment, the actual roles can be set.
        tokenStakingNodesManager.grantRole(tokenStakingNodesManager.DEFAULT_ADMIN_ROLE(), actors.admin.ADMIN);
        tokenStakingNodesManager.grantRole(tokenStakingNodesManager.STAKING_ADMIN_ROLE(), address(timelock));

        // Remove roles from DEFAULT_SIGNER. DEFAULT_ADMIN_ROLE MUST be done last.
        tokenStakingNodesManager.revokeRole(tokenStakingNodesManager.STAKING_ADMIN_ROLE(), actors.eoa.DEFAULT_SIGNER);
        tokenStakingNodesManager.revokeRole(tokenStakingNodesManager.DEFAULT_ADMIN_ROLE(), actors.eoa.DEFAULT_SIGNER);

        // ynEigenDepositAdapter
        {
            ynEigenDepositAdapter ynEigenDepositAdapterImplementation = new ynEigenDepositAdapter();
            TransparentUpgradeableProxy ynEigenDepositAdapterProxy =
                new TransparentUpgradeableProxy(address(ynEigenDepositAdapterImplementation), address(timelock), "");
            ynEigenDepositAdapterInstance = ynEigenDepositAdapter(address(ynEigenDepositAdapterProxy));
        }

        {
            ynEigenDepositAdapter.Init memory init = ynEigenDepositAdapter.Init({
                ynEigen: address(ynToken),
                wstETH: chainAddresses.ynEigen.WSTETH_ADDRESS,
                woETH: chainAddresses.ynEigen.WOETH_ADDRESS,
                admin: actors.admin.ADMIN
            });
            ynEigenDepositAdapterInstance.initialize(init);
        }

        {
            address _viewerImplementation = address(
                new ynEigenViewer(
                    address(assetRegistry), address(ynToken), address(tokenStakingNodesManager), address(rateProvider)
                )
            );

            // ProxyAdmin Owner set to YNSecurityCouncil since ynEigenViewer does not run production on-chain SC logic.
            viewer = ynEigenViewer(
                address(
                    new TransparentUpgradeableProxy(
                        _viewerImplementation, address(actors.wallets.YNSecurityCouncil), ""
                    )
                )
            );
        }

        vm.stopBroadcast();

        Deployment memory deployment = Deployment({
            ynEigen: ynToken,
            assetRegistry: assetRegistry,
            eigenStrategyManager: eigenStrategyManager,
            tokenStakingNodesManager: tokenStakingNodesManager,
            tokenStakingNodeImplementation: tokenStakingNodeImplementation,
            ynEigenDepositAdapterInstance: ynEigenDepositAdapterInstance,
            rateProvider: IRateProvider(address(rateProvider)),
            upgradeTimelock: timelock,
            viewer: viewer
        });

        saveDeployment(deployment);
    }
}
