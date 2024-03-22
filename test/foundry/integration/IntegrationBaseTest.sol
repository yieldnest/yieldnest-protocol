// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IStrategyManager} from "../../../src/external/eigenlayer/v0.1.0/interfaces/IStrategyManager.sol";
import {IDelayedWithdrawalRouter} from "../../../src/external/eigenlayer/v0.1.0/interfaces/IDelayedWithdrawalRouter.sol";
import {IDepositContract} from "../../../src/external/ethereum/IDepositContract.sol";
import {IEigenPodManager} from "../../../src/external/eigenlayer/v0.1.0/interfaces/IEigenPodManager.sol";
import {IStrategy} from "../../../src/external/eigenlayer/v0.1.0/interfaces/IStrategy.sol";
import {IStakingNodesManager} from "../../../src/interfaces/IStakingNodesManager.sol";
import {IDelegationManager} from "../../../src/external/eigenlayer/v0.1.0/interfaces//IDelegationManager.sol";
import {IStakingNodesManager} from "../../../src/interfaces/IStakingNodesManager.sol";
import {IRewardsDistributor} from "../../../src/interfaces/IRewardsDistributor.sol";
import {IynETH} from "../../../src/interfaces/IynETH.sol";
import {IWETH} from "../../../src/external/tokens/IWETH.sol";
import {Test} from "forge-std/Test.sol";
import {WETH} from "../../../src/external/tokens/WETH.sol";
import {ynETH} from "../../../src/ynETH.sol";
import {ynLSD} from "../../../src/ynLSD.sol";
import {YieldNestOracle} from "../../../src/YieldNestOracle.sol";
import {LSDStakingNode} from "../../../src/LSDStakingNode.sol";

import {ynViewer} from "../../../src/ynViewer.sol";
import {StakingNodesManager} from "../../../src/StakingNodesManager.sol";
import {StakingNode} from "../../../src/StakingNode.sol";
import {RewardsReceiver} from "../../../src/RewardsReceiver.sol";
import {RewardsDistributor} from "../../../src/RewardsDistributor.sol";
import {ContractAddresses} from "../ContractAddresses.sol";
import {StakingNode} from "../../../src/StakingNode.sol";
import {Utils} from "../../../scripts/forge/Utils.sol";
import {ActorAddresses} from "../ActorAddresses.sol";


contract IntegrationBaseTest is Test, Utils {

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
    StakingNodesManager public stakingNodesManager;
    StakingNode public stakingNodeImplementation;


    // Assets
    ynETH public yneth;
    ynLSD public ynlsd;

    // Oracles
    YieldNestOracle public yieldNestOracle;

    // Eigen
    IEigenPodManager public eigenPodManager;
    IDelegationManager public delegationManager;
    IDelayedWithdrawalRouter public delayedWithdrawalRouter;
    IStrategyManager public strategyManager;

    // Ethereum
    IDepositContract public depositContractEth2;

    address public transferEnabledEOA;

    function setUp() public virtual {


        // Setup Addresses
        contractAddresses = new ContractAddresses();
        actorAddresses = new ActorAddresses();

        // Setup Protocol
        setupUtils();
        setupProxies();
        setupEthereum();
        setupEigenLayer();
        setupRewardsDistributor();
        setupStakingNodesManager();
        setupYnETH();
        setupYieldNestOracleAndYnLSD();
    }

    function setupProxies() public {

        TransparentUpgradeableProxy ynethProxy;
        TransparentUpgradeableProxy ynLSDProxy;
        TransparentUpgradeableProxy rewardsDistributorProxy;
        TransparentUpgradeableProxy stakingNodesManagerProxy;
        TransparentUpgradeableProxy yieldNestOracleProxy;
        // Initializing RewardsDistributor contract and creating its proxy
        rewardsDistributor = new RewardsDistributor();
        yneth = new ynETH();
        stakingNodesManager = new StakingNodesManager();
        yieldNestOracle = new YieldNestOracle();
        ynlsd = new ynLSD();

        rewardsDistributorProxy = new TransparentUpgradeableProxy(address(rewardsDistributor), actors.PROXY_ADMIN_OWNER, "");
        rewardsDistributor = RewardsDistributor(payable(rewardsDistributorProxy));
        
        ynethProxy = new TransparentUpgradeableProxy(address(yneth), actors.PROXY_ADMIN_OWNER, "");
        stakingNodesManagerProxy = new TransparentUpgradeableProxy(address(stakingNodesManager), actors.PROXY_ADMIN_OWNER, "");
        yieldNestOracleProxy = new TransparentUpgradeableProxy(address(yieldNestOracle), actors.PROXY_ADMIN_OWNER, "");
        ynLSDProxy = new TransparentUpgradeableProxy(address(ynlsd), actors.PROXY_ADMIN_OWNER, "");

        // Wrapping proxies with their respective interfaces
        yneth = ynETH(payable(ynethProxy));
        stakingNodesManager = StakingNodesManager(payable(stakingNodesManagerProxy));
        yieldNestOracle = YieldNestOracle(address(yieldNestOracleProxy));
        ynlsd = ynLSD(address(ynLSDProxy));

        // Re-deploying ynETH and creating its proxy again
        yneth = new ynETH();
        ynethProxy = new TransparentUpgradeableProxy(address(yneth), actors.PROXY_ADMIN_OWNER, "");
        yneth = ynETH(payable(ynethProxy));

        // Re-deploying StakingNodesManager and creating its proxy again
        stakingNodesManager = new StakingNodesManager();
        stakingNodesManagerProxy = new TransparentUpgradeableProxy(address(stakingNodesManager), actors.PROXY_ADMIN_OWNER, "");
        stakingNodesManager = StakingNodesManager(payable(stakingNodesManagerProxy));
    }

    function setupUtils() public {
        viewer = new ynViewer(yneth, stakingNodesManager);
        chainAddresses = contractAddresses.getChainAddresses(block.chainid);
        actors = actorAddresses.getActors(block.chainid);
    }

    function setupEthereum() public {
        depositContractEth2 = IDepositContract(chainAddresses.ethereum.DEPOSIT_2_ADDRESS);
    }

    function setupEigenLayer() public {
        eigenPodManager = IEigenPodManager(vm.addr(4));
        delegationManager = IDelegationManager(vm.addr(5));
        delayedWithdrawalRouter = IDelayedWithdrawalRouter(vm.addr(6));
        strategyManager = IStrategyManager(vm.addr(7));
        eigenPodManager = IEigenPodManager(chainAddresses.eigenlayer.EIGENPOD_MANAGER_ADDRESS);
        delegationManager = IDelegationManager(chainAddresses.eigenlayer.DELEGATION_MANAGER_ADDRESS);
        delayedWithdrawalRouter = IDelayedWithdrawalRouter(chainAddresses.eigenlayer.DELAYED_WITHDRAWAL_ROUTER_ADDRESS); // Assuming DEPOSIT_2_ADDRESS is used for DelayedWithdrawalRouter
        strategyManager = IStrategyManager(chainAddresses.eigenlayer.STRATEGY_MANAGER_ADDRESS);
    }

    function setupYnETH() public {
        address[] memory pauseWhitelist = new address[](1);
        pauseWhitelist[0] = actors.TRANSFER_ENABLED_EOA;
        
        ynETH.Init memory ynethInit = ynETH.Init({
            admin: actors.ADMIN,
            pauser: actors.PAUSE_ADMIN,
            stakingNodesManager: IStakingNodesManager(address(stakingNodesManager)),
            rewardsDistributor: IRewardsDistributor(address(rewardsDistributor)),
            pauseWhitelist: pauseWhitelist
        });

        yneth.initialize(ynethInit);
    }

    function setupRewardsDistributor() public {
        executionLayerReceiver = new RewardsReceiver();
        consensusLayerReceiver = new RewardsReceiver();
        RewardsDistributor.Init memory rewardsDistributorInit = RewardsDistributor.Init({
            admin: actors.ADMIN,
            executionLayerReceiver: executionLayerReceiver,
            consensusLayerReceiver: consensusLayerReceiver,
            feesReceiver: payable(actors.FEE_RECEIVER),
            ynETH: IynETH(address(yneth))
        });

        rewardsDistributor.initialize(rewardsDistributorInit);
        RewardsReceiver.Init memory rewardsReceiverInit = RewardsReceiver.Init({
            admin: actors.ADMIN,
            withdrawer: address(rewardsDistributor)
        });
        vm.startPrank(actors.PROXY_ADMIN_OWNER);
        executionLayerReceiver.initialize(rewardsReceiverInit);
        consensusLayerReceiver.initialize(rewardsReceiverInit);
        vm.stopPrank();
    }

    function setupStakingNodesManager() public {
        stakingNodeImplementation = new StakingNode();
        StakingNodesManager.Init memory stakingNodesManagerInit = StakingNodesManager.Init({
            admin: actors.ADMIN,
            stakingAdmin: actors.STAKING_ADMIN,
            stakingNodesAdmin: actors.STAKING_NODES_ADMIN,
            validatorManager: actors.VALIDATOR_MANAGER,
            maxNodeCount: 10,
            depositContract: depositContractEth2,
            ynETH: IynETH(address(yneth)),
            eigenPodManager: eigenPodManager,
            delegationManager: delegationManager,
            delayedWithdrawalRouter: delayedWithdrawalRouter,
            strategyManager: strategyManager,
            rewardsDistributor: IRewardsDistributor(address(rewardsDistributor)),
            stakingNodeCreatorRole:  actors.STAKING_NODE_CREATOR
        });
        vm.prank(actors.PROXY_ADMIN_OWNER);
        stakingNodesManager.initialize(stakingNodesManagerInit);
        vm.prank(actors.STAKING_ADMIN); // StakingNodesManager is the only contract that can register a staking node implementation contract
        stakingNodesManager.registerStakingNodeImplementationContract(address(stakingNodeImplementation));
    }

    function setupYieldNestOracleAndYnLSD() public {
        IERC20[] memory assets = new IERC20[](2);
        address[] memory assetsAddresses = new address[](2);
        address[] memory priceFeeds = new address[](2);
        uint256[] memory maxAges = new uint256[](2);
        IStrategy[] memory strategies = new IStrategy[](2);

        address[] memory pauseWhitelist = new address[](1);
        pauseWhitelist[0] = actors.TRANSFER_ENABLED_EOA;


        // stETH
        assets[0] = IERC20(chainAddresses.lsd.STETH_ADDRESS);
        assetsAddresses[0] = chainAddresses.lsd.STETH_ADDRESS;
        strategies[0] = IStrategy(chainAddresses.lsd.STETH_STRATEGY_ADDRESS);
        priceFeeds[0] = chainAddresses.lsd.STETH_FEED_ADDRESS;
        maxAges[0] = uint256(86400); //one hour

        // rETH
        assets[1] = IERC20(chainAddresses.lsd.RETH_ADDRESS);
        assetsAddresses[1] = chainAddresses.lsd.RETH_ADDRESS;
        strategies[1] = IStrategy(chainAddresses.lsd.RETH_STRATEGY_ADDRESS);
        priceFeeds[1] = chainAddresses.lsd.RETH_FEED_ADDRESS;
        maxAges[1] = uint256(86400);

        YieldNestOracle.Init memory oracleInit = YieldNestOracle.Init({
            assets: assetsAddresses,
            priceFeedAddresses: priceFeeds,
            maxAges: maxAges,
            admin: actors.ADMIN,
            oracleManager: actors.ORACLE_MANAGER
        });
        yieldNestOracle.initialize(oracleInit);

        LSDStakingNode lsdStakingNodeImplementation = new LSDStakingNode();
        ynLSD.Init memory init = ynLSD.Init({
            assets: assets,
            strategies: strategies,
            strategyManager: strategyManager,
            delegationManager: delegationManager,
            oracle: yieldNestOracle,
            maxNodeCount: 10,
            admin: actors.ADMIN,
            stakingAdmin: actors.STAKING_ADMIN,
            lsdRestakingManager: actors.LSD_RESTAKING_MANAGER,
            lsdStakingNodeCreatorRole: actors.STAKING_NODE_CREATOR,
            pauseWhitelist: pauseWhitelist,
            pauser: actors.PAUSE_ADMIN,
            depositBootstrapper: actors.DEPOSIT_BOOTSTRAPER
        });

        vm.deal(actors.DEPOSIT_BOOTSTRAPER, 10000 ether);

        vm.prank(actors.DEPOSIT_BOOTSTRAPER);
        (bool success, ) = chainAddresses.lsd.STETH_ADDRESS.call{value: 1000 ether}("");
        require(success, "ETH transfer failed");

        vm.prank(actors.DEPOSIT_BOOTSTRAPER);
        IERC20(chainAddresses.lsd.STETH_ADDRESS).approve(address(ynlsd), type(uint256).max);
        ynlsd.initialize(init);

        vm.prank(actors.STAKING_ADMIN);
        ynlsd.registerLSDStakingNodeImplementationContract(address(lsdStakingNodeImplementation));
    }
}

