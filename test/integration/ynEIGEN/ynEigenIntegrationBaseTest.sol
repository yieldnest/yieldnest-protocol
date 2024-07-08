// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {TransparentUpgradeableProxy} from "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IStrategyManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IDelayedWithdrawalRouter} from "lib/eigenlayer-contracts/src/contracts/interfaces/IDelayedWithdrawalRouter.sol";
import {IDepositContract} from "src/external/ethereum/IDepositContract.sol";
import {IEigenPodManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IEigenPodManager.sol";
import {IStrategy} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IStakingNodesManager} from "src/interfaces/IStakingNodesManager.sol";
import {IDelegationManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStakingNodesManager} from "src/interfaces/IStakingNodesManager.sol";
import {IRewardsDistributor} from "src/interfaces/IRewardsDistributor.sol";
import {IynETH} from "src/interfaces/IynETH.sol";
import {Test} from "forge-std/Test.sol";
import {ynETH} from "src/ynETH.sol";
import {ynViewer} from "src/ynViewer.sol";
import {StakingNodesManager} from "src/StakingNodesManager.sol";
import {StakingNode} from "src/StakingNode.sol";
import {RewardsReceiver} from "src/RewardsReceiver.sol";
import {RewardsDistributor} from "src/RewardsDistributor.sol";
import {ContractAddresses} from "script/ContractAddresses.sol";
import {StakingNode} from "src/StakingNode.sol";
import {Utils} from "script/Utils.sol";
import {ActorAddresses} from "script/Actors.sol";
import {TestAssetUtils} from "test/utils/TestAssetUtils.sol";
import {LSDRateProvider} from "src/ynEIGEN/LSDRateProvider.sol";

import {IynEigen} from "src/interfaces/IynEigen.sol";
import {IRateProvider} from "src/interfaces/IRateProvider.sol";
import {IAssetRegistry} from "src/interfaces/IAssetRegistry.sol";
import {IEigenStrategyManager} from "src/interfaces/IEigenStrategyManager.sol";
import {TokenStakingNodesManager} from "src/ynEIGEN/TokenStakingNodesManager.sol";
import {TokenStakingNode} from "src/ynEIGEN/TokenStakingNode.sol";
import {AssetRegistry} from "src/ynEIGEN/AssetRegistry.sol";
import {EigenStrategyManager} from "src/ynEIGEN/EigenStrategyManager.sol";
import {ynEigen} from "src/ynEIGEN/ynEigen.sol";

contract ynEigenIntegrationBaseTest is Test, Utils {

    // State
    bytes constant ZERO_PUBLIC_KEY = hex"000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"; 
    bytes constant ONE_PUBLIC_KEY = hex"000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001";
    bytes constant TWO_PUBLIC_KEY = hex"000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002";
    bytes constant  ZERO_SIGNATURE = hex"000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";
    bytes32 constant ZERO_DEPOSIT_ROOT = bytes32(0);

    // Utils
    ContractAddresses public contractAddresses;
    ContractAddresses.ChainAddresses public chainAddresses;
    ActorAddresses public actorAddresses;
    ActorAddresses.Actors public actors;
    ynViewer public viewer;

    // Rewards
    RewardsReceiver public executionLayerReceiver;
    RewardsReceiver public consensusLayerReceiver;
    RewardsDistributor public rewardsDistributor;

    // Staking
    TokenStakingNodesManager public tokenStakingNodesManager;
    TokenStakingNode public tokenStakingNodeImplementation;

    // Assets
    ynEigen public ynEigenToken;
    AssetRegistry public assetRegistry;
    LSDRateProvider public rateProvider;

    // Strategy
    EigenStrategyManager eigenStrategyManager;

    // Eigen
    IEigenPodManager public eigenPodManager;
    IDelegationManager public delegationManager;
    IDelayedWithdrawalRouter public delayedWithdrawalRouter;
    IStrategyManager public strategyManager;


    function setUp() public virtual {


        // Setup Addresses
        contractAddresses = new ContractAddresses();
        actorAddresses = new ActorAddresses();

        // Setup Protocol
        setupUtils();
        setupYnEigenProxies();
        setupEigenLayer();
        setupTokenStakingNodesManager();
        setupYnEigen();
    }

    function setupYnEigenProxies() public {
        TransparentUpgradeableProxy ynEigenProxy;
        TransparentUpgradeableProxy eigenStrategyManagerProxy;
        TransparentUpgradeableProxy tokenStakingNodesManagerProxy;
        TransparentUpgradeableProxy assetRegistryProxy;
        TransparentUpgradeableProxy rateProviderProxy;

        ynEigenToken = new ynEigen();
        eigenStrategyManager = new EigenStrategyManager();
        tokenStakingNodesManager = new TokenStakingNodesManager();
        assetRegistry = new AssetRegistry();
        rateProvider = new LSDRateProvider();

        ynEigenProxy = new TransparentUpgradeableProxy(address(ynEigenToken), actors.admin.PROXY_ADMIN_OWNER, "");
        eigenStrategyManagerProxy = new TransparentUpgradeableProxy(address(eigenStrategyManager), actors.admin.PROXY_ADMIN_OWNER, "");
        tokenStakingNodesManagerProxy = new TransparentUpgradeableProxy(address(tokenStakingNodesManager), actors.admin.PROXY_ADMIN_OWNER, "");
        assetRegistryProxy = new TransparentUpgradeableProxy(address(assetRegistry), actors.admin.PROXY_ADMIN_OWNER, "");
        rateProviderProxy = new TransparentUpgradeableProxy(address(rateProvider), actors.admin.PROXY_ADMIN_OWNER, "");

        // Wrapping proxies with their respective interfaces
        ynEigenToken = ynEigen(payable(ynEigenProxy));
        eigenStrategyManager = EigenStrategyManager(payable(eigenStrategyManagerProxy));
        tokenStakingNodesManager = TokenStakingNodesManager(payable(tokenStakingNodesManagerProxy));
        assetRegistry = AssetRegistry(payable(assetRegistryProxy));
        rateProvider = LSDRateProvider(payable(rateProviderProxy));

        // Re-deploying ynEigen and creating its proxy again
        ynEigenToken = new ynEigen();
        ynEigenProxy = new TransparentUpgradeableProxy(address(ynEigenToken), actors.admin.PROXY_ADMIN_OWNER, "");
        ynEigenToken = ynEigen(payable(ynEigenProxy));

        // Re-deploying EigenStrategyManager and creating its proxy again
        eigenStrategyManager = new EigenStrategyManager();
        eigenStrategyManagerProxy = new TransparentUpgradeableProxy(address(eigenStrategyManager), actors.admin.PROXY_ADMIN_OWNER, "");
        eigenStrategyManager = EigenStrategyManager(payable(eigenStrategyManagerProxy));

        // Re-deploying TokenStakingNodesManager and creating its proxy again
        tokenStakingNodesManager = new TokenStakingNodesManager();
        tokenStakingNodesManagerProxy = new TransparentUpgradeableProxy(address(tokenStakingNodesManager), actors.admin.PROXY_ADMIN_OWNER, "");
        tokenStakingNodesManager = TokenStakingNodesManager(payable(tokenStakingNodesManagerProxy));

        // Re-deploying AssetRegistry and creating its proxy again
        assetRegistry = new AssetRegistry();
        assetRegistryProxy = new TransparentUpgradeableProxy(address(assetRegistry), actors.admin.PROXY_ADMIN_OWNER, "");
        assetRegistry = AssetRegistry(payable(assetRegistryProxy));

        // Re-deploying LSDRateProvider and creating its proxy again
        rateProvider = new LSDRateProvider();
        rateProviderProxy = new TransparentUpgradeableProxy(address(rateProvider), actors.admin.PROXY_ADMIN_OWNER, "");
        rateProvider = LSDRateProvider(payable(rateProviderProxy));
    }

    function setupUtils() public {
        chainAddresses = contractAddresses.getChainAddresses(block.chainid);
        actors = actorAddresses.getActors(block.chainid);
    }

    function setupEigenLayer() public {
        delayedWithdrawalRouter = IDelayedWithdrawalRouter(vm.addr(6));
        strategyManager = IStrategyManager(vm.addr(7));
        eigenPodManager = IEigenPodManager(chainAddresses.eigenlayer.EIGENPOD_MANAGER_ADDRESS);
        delegationManager = IDelegationManager(chainAddresses.eigenlayer.DELEGATION_MANAGER_ADDRESS);
        delayedWithdrawalRouter = IDelayedWithdrawalRouter(chainAddresses.eigenlayer.DELAYED_WITHDRAWAL_ROUTER_ADDRESS); // Assuming DEPOSIT_2_ADDRESS is used for DelayedWithdrawalRouter
        strategyManager = IStrategyManager(chainAddresses.eigenlayer.STRATEGY_MANAGER_ADDRESS);
    }

    function setupYnEigen() public {
        address[] memory pauseWhitelist = new address[](1);
        pauseWhitelist[0] = actors.eoa.DEFAULT_SIGNER;

        
        ynEigen.Init memory ynEigenInit = ynEigen.Init({
            name: "Eigenlayer YieldNest LSD",
            symbol: "ynLSDe",
            admin: actors.admin.ADMIN,
            pauser: actors.ops.PAUSE_ADMIN,
            unpauser: actors.admin.UNPAUSE_ADMIN,
            eigenStrategyManager: IEigenStrategyManager(address(eigenStrategyManager)),
            assetRegistry: IAssetRegistry(address(assetRegistry)),
            pauseWhitelist: pauseWhitelist
        });

        ynEigenToken.initialize(ynEigenInit);
    }

    function setupTokenStakingNodesManager() public {
        tokenStakingNodeImplementation = new TokenStakingNode();

        TokenStakingNodesManager.Init memory tokenStakingNodesManagerInit = TokenStakingNodesManager.Init({
            strategyManager: strategyManager,
            delegationManager: delegationManager,
            eigenStrategyManager: IEigenStrategyManager(address(eigenStrategyManager)),
            maxNodeCount: 10,
            admin: actors.admin.ADMIN,
            pauser: actors.ops.PAUSE_ADMIN,
            unpauser: actors.admin.UNPAUSE_ADMIN,
            stakingAdmin: actors.admin.STAKING_ADMIN,
            tokenRestakingManager: address(rewardsDistributor),
            tokenStakingNodeCreatorRole: actors.ops.STAKING_NODE_CREATOR
        });

        vm.prank(actors.admin.PROXY_ADMIN_OWNER);
        tokenStakingNodesManager.initialize(tokenStakingNodesManagerInit);
        vm.prank(actors.admin.STAKING_ADMIN); // TokenStakingNodesManager is the only contract that can register a staking node implementation contract
        tokenStakingNodesManager.registerTokenStakingNodeImplementationContract(address(tokenStakingNodeImplementation));
    }

    function setupAssetRegistry() public {
        assetRegistry = new AssetRegistry();
        AssetRegistry.Init memory assetRegistryInit = AssetRegistry.Init({
            name: "ynEigen Asset Registry",
            symbol: "ynEAR",
            assets: new IERC20[](0), // Initialize with an empty array of assets
            rateProvider: IRateProvider(address(rateProvider)),
            eigenStrategyManager: IEigenStrategyManager(address(eigenStrategyManager)),
            ynEigen: IynEigen(address(ynEigenToken)),
            admin: actors.admin.ADMIN,
            pauser: actors.ops.PAUSE_ADMIN,
            unpauser: actors.admin.UNPAUSE_ADMIN
        });
        assetRegistry.initialize(assetRegistryInit);
    }
}

