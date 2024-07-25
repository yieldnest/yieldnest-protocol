// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {TransparentUpgradeableProxy} from "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IEigenPodManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IEigenPodManager.sol";
import {IDelegationManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IDelayedWithdrawalRouter} from "lib/eigenlayer-contracts/src/contracts/interfaces/IDelayedWithdrawalRouter.sol";
import {IStrategyManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IStrategy} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IDepositContract} from "src/external/ethereum/IDepositContract.sol";
import {IWETH} from "src/external/tokens/IWETH.sol";

import {ITokenStakingNodesManager} from "src/interfaces/ITokenStakingNodesManager.sol";

import {IynEigen} from "src/interfaces/IynEigen.sol";
import {IRateProvider} from "src/interfaces/IRateProvider.sol";
import {IAssetRegistry} from "src/interfaces/IAssetRegistry.sol";
import {IEigenStrategyManager} from "src/interfaces/IEigenStrategyManager.sol";
import {IYieldNestStrategyManager} from "src/interfaces/IYieldNestStrategyManager.sol";
import {IYieldNestStrategyManager} from "src/interfaces/IYieldNestStrategyManager.sol";
import {ynEigen} from "src/ynEIGEN/ynEigen.sol";
import {TokenStakingNode} from "src/ynEIGEN/TokenStakingNode.sol";
import {LSDRateProvider} from "src/ynEIGEN/LSDRateProvider.sol";
import {EigenStrategyManager} from "src/ynEIGEN/EigenStrategyManager.sol";
import {AssetRegistry} from "src/ynEIGEN/AssetRegistry.sol";
import {TokenStakingNodesManager} from "src/ynEIGEN/TokenStakingNodesManager.sol";


import {ContractAddresses} from "script/ContractAddresses.sol";
import {ActorAddresses} from "script/Actors.sol";
import {BaseScript} from "script/BaseScript.s.sol";

import {IwstETH} from "src/external/lido/IwstETH.sol";
import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";


import {console} from "lib/forge-std/src/console.sol";

contract DeployYnLSD is BaseScript {

    IDelegationManager public delegationManager;
    IDelayedWithdrawalRouter public delayedWithdrawalRouter;
    IStrategyManager public strategyManager;
    IEigenPodManager public eigenPodManager;

    ynEigen ynLSDe;
    LSDRateProvider lsdRateProvider;
    EigenStrategyManager eigenStrategyManager;
    TokenStakingNodesManager tokenStakingNodesManager;
    AssetRegistry assetRegistry;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // ynETH.sol ROLES
        ActorAddresses.Actors memory actors = getActors();

        address _broadcaster = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        // solhint-disable-next-line no-console
        console.log("Default Signer Address:", _broadcaster);
        // solhint-disable-next-line no-console
        console.log("Current Block Number:", block.number);
        // solhint-disable-next-line no-console
        console.log("Current Chain ID:", block.chainid);

        ContractAddresses contractAddresses = new ContractAddresses();
        ContractAddresses.ChainAddresses memory chainAddresses = contractAddresses.getChainAddresses(block.chainid);
        eigenPodManager = IEigenPodManager(chainAddresses.eigenlayer.EIGENPOD_MANAGER_ADDRESS);
        delegationManager = IDelegationManager(chainAddresses.eigenlayer.DELEGATION_MANAGER_ADDRESS);
        delayedWithdrawalRouter = IDelayedWithdrawalRouter(chainAddresses.eigenlayer.DELAYED_WITHDRAWAL_ROUTER_ADDRESS); // Assuming DEPOSIT_2_ADDRESS is used for DelayedWithdrawalRouter
        strategyManager = IStrategyManager(chainAddresses.eigenlayer.STRATEGY_MANAGER_ADDRESS);

        // Deploy implementations
        {
            ynEigen ynLSDeImplementation = new ynEigen();
            TransparentUpgradeableProxy ynLSDeProxy = new TransparentUpgradeableProxy(address(ynLSDeImplementation), actors.admin.PROXY_ADMIN_OWNER, "");
            ynLSDe = ynEigen(address(ynLSDeProxy));
        }

        {
            LSDRateProvider lsdRateProviderImplementation = new LSDRateProvider();
            TransparentUpgradeableProxy lsdRateProviderProxy = new TransparentUpgradeableProxy(address(lsdRateProviderImplementation), actors.admin.PROXY_ADMIN_OWNER, "");
            lsdRateProvider = LSDRateProvider(address(lsdRateProviderProxy));
        }

        IERC20[] memory assets;
        IStrategy[] memory strategies;

        if (block.chainid == 1) {

            uint256 assetCount = 3;
            assets = new IERC20[](assetCount);
            assets[0] = IERC20(chainAddresses.lsd.WSTETH_ADDRESS);
            assets[1] = IERC20(chainAddresses.lsd.SFRXETH_ADDRESS);
            assets[2] = IERC20(chainAddresses.lsd.WOETH_ADDRESS);

            strategies = new IStrategy[](assetCount);
            strategies[0] = IStrategy(chainAddresses.lsdStrategies.STETH_STRATEGY_ADDRESS);
            strategies[1] = IStrategy(chainAddresses.lsdStrategies.SFRXETH_STRATEGY_ADDRESS);
            strategies[2] = IStrategy(chainAddresses.lsdStrategies.OETH_STRATEGY_ADDRESS);

        } else if (block.chainid == 17000) {

            uint256 assetCount = 4;
            assets = new IERC20[](assetCount);
            assets[0] = IERC20(chainAddresses.lsd.WSTETH_ADDRESS);
            assets[1] = IERC20(chainAddresses.lsd.SFRXETH_ADDRESS);
            assets[2] = IERC20(chainAddresses.lsd.RETH_ADDRESS);
            assets[3] = IERC20(chainAddresses.lsd.METH_ADDRESS);

            strategies = new IStrategy[](assetCount);
            strategies[0] = IStrategy(chainAddresses.lsdStrategies.STETH_STRATEGY_ADDRESS);
            strategies[1] = IStrategy(chainAddresses.lsdStrategies.SFRXETH_STRATEGY_ADDRESS);
            strategies[2] = IStrategy(chainAddresses.lsdStrategies.RETH_STRATEGY_ADDRESS);
            strategies[3] = IStrategy(chainAddresses.lsdStrategies.METH_STRATEGY_ADDRESS);
        } else {
            revert(string(string.concat("Chain ID ", vm.toString(block.chainid), " not supported")));
        }

        {
            EigenStrategyManager eigenStrategyManagerImplementation = new EigenStrategyManager();
            TransparentUpgradeableProxy eigenStrategyManagerProxy = new TransparentUpgradeableProxy(address(eigenStrategyManagerImplementation), actors.admin.PROXY_ADMIN_OWNER, "");
            eigenStrategyManager = EigenStrategyManager(address(eigenStrategyManagerProxy));
        }

        {
            TokenStakingNodesManager tokenStakingNodesManagerImplementation = new TokenStakingNodesManager();
            TransparentUpgradeableProxy tokenStakingNodesManagerProxy = new TransparentUpgradeableProxy(address(tokenStakingNodesManagerImplementation), actors.admin.PROXY_ADMIN_OWNER, "");
            tokenStakingNodesManager = TokenStakingNodesManager(address(tokenStakingNodesManagerProxy));
        }

        {
            AssetRegistry assetRegistryImplementation = new AssetRegistry();
            TransparentUpgradeableProxy assetRegistryProxy = new TransparentUpgradeableProxy(address(assetRegistryImplementation), actors.admin.PROXY_ADMIN_OWNER, "");
            assetRegistry = AssetRegistry(address(assetRegistryProxy));
        }

        // Initialize ynLSDe
        {
            address[] memory lsdPauseWhitelist = new address[](0);

            ynEigen.Init memory ynlsdeInit = ynEigen.Init({
                name: "Eigenlayer YieldNest LSD",
                symbol: "ynLSDe",
                admin: actors.admin.ADMIN,
                pauser: actors.ops.PAUSE_ADMIN,
                unpauser: actors.admin.UNPAUSE_ADMIN,
                yieldNestStrategyManager: address(eigenStrategyManager),
                assetRegistry: IAssetRegistry(address(assetRegistry)),
                pauseWhitelist: lsdPauseWhitelist
            });
            ynLSDe.initialize(ynlsdeInit);
        }

        {
            AssetRegistry.Init memory assetRegistryInit = AssetRegistry.Init({
                assets: assets,
                rateProvider: IRateProvider(address(lsdRateProvider)),
                yieldNestStrategyManager: IYieldNestStrategyManager(address(eigenStrategyManager)),
                ynEigen: IynEigen(address(ynLSDe)),
                admin: actors.admin.ADMIN,
                pauser: actors.ops.PAUSE_ADMIN,
                unpauser: actors.admin.UNPAUSE_ADMIN,
                assetManagerRole: actors.admin.ASSET_MANAGER
            });
            assetRegistry.initialize(assetRegistryInit);
        }

        {
            EigenStrategyManager.Init memory eigenStrategyManagerInit = EigenStrategyManager.Init({
                assets: assets,
                strategies: strategies,
                ynEigen: IynEigen(address(ynLSDe)),
                strategyManager: IStrategyManager(address(chainAddresses.eigenlayer.STRATEGY_MANAGER_ADDRESS)),
                delegationManager: IDelegationManager(address(chainAddresses.eigenlayer.DELEGATION_MANAGER_ADDRESS)),
                tokenStakingNodesManager: ITokenStakingNodesManager(address(tokenStakingNodesManager)),
                admin: actors.admin.ADMIN,
                strategyController: actors.ops.STRATEGY_CONTROLLER,
                unpauser: actors.admin.UNPAUSE_ADMIN,
                pauser: actors.ops.PAUSE_ADMIN,
                strategyAdmin: actors.admin.EIGEN_STRATEGY_ADMIN,
                wstETH: IwstETH(chainAddresses.lsd.WSTETH_ADDRESS),
                woETH: IERC4626(chainAddresses.lsd.WOETH_ADDRESS)
            });
            eigenStrategyManager.initialize(eigenStrategyManagerInit);
        }

    //     {
    //         LSDStakingNode lsdStakingNodeImplementation = new LSDStakingNode();
    //         ynlsd.registerLSDStakingNodeImplementationContract(address(lsdStakingNodeImplementation));
            
    //         ynLSDDeployment memory deployment = ynLSDDeployment({
    //             ynlsd: ynlsd,
    //             lsdStakingNodeImplementation: lsdStakingNodeImplementation,
    //             yieldNestOracle: yieldNestOracle
    //         });
            
    //         saveynLSDDeployment(deployment);
    //     }
    }
}
