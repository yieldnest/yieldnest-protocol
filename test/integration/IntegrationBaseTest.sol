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
import {IReferralDepositAdapter} from "src/interfaces/IReferralDepositAdapter.sol";
import {IynETH} from "src/interfaces/IynETH.sol";
import {Test} from "forge-std/Test.sol";
import {ynETH} from "src/ynETH.sol";
import {ynLSD} from "src/ynLSD.sol";
import {YieldNestOracle} from "src/YieldNestOracle.sol";
import {LSDStakingNode} from "src/LSDStakingNode.sol";
import {ynViewer} from "src/ynViewer.sol";
import {StakingNodesManager} from "src/StakingNodesManager.sol";
import {StakingNode} from "src/StakingNode.sol";
import {RewardsReceiver} from "src/RewardsReceiver.sol";
import {RewardsDistributor} from "src/RewardsDistributor.sol";
import {ReferralDepositAdapter} from "src/ReferralDepositAdapter.sol";
import {ContractAddresses} from "script/ContractAddresses.sol";
import {StakingNode} from "src/StakingNode.sol";
import {Utils} from "script/Utils.sol";
import {ActorAddresses} from "script/Actors.sol";
import {TestAssetUtils} from "test/utils/TestAssetUtils.sol";

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
    ReferralDepositAdapter referralDepositAdapter;

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
        chainAddresses = contractAddresses.getChainAddresses(block.chainid);
        actors = actorAddresses.getActors(block.chainid);

        // Setup Protocol
        setupYnETHPoxies();
        setupYnLSDProxies();
        setupEthereum();
        setupEigenLayer();
        setupRewardsDistributor();
        setupStakingNodesManager();
        setupYnETH();
        setupYieldNestOracleAndYnLSD();
        setupUtils();
    }

    function setupYnETHPoxies() public {
        TransparentUpgradeableProxy ynethProxy;
        TransparentUpgradeableProxy rewardsDistributorProxy;
        TransparentUpgradeableProxy stakingNodesManagerProxy;
        TransparentUpgradeableProxy executionLayerReceiverProxy;
        TransparentUpgradeableProxy consensusLayerReceiverProxy;

                // Initializing RewardsDistributor contract and creating its proxy
        rewardsDistributor = new RewardsDistributor();
        yneth = new ynETH();
        stakingNodesManager = new StakingNodesManager();

        executionLayerReceiver = new RewardsReceiver();
        consensusLayerReceiver = new RewardsReceiver();

        rewardsDistributorProxy = new TransparentUpgradeableProxy(address(rewardsDistributor), actors.admin.PROXY_ADMIN_OWNER, "");
        rewardsDistributor = RewardsDistributor(payable(rewardsDistributorProxy));
        
        ynethProxy = new TransparentUpgradeableProxy(address(yneth), actors.admin.PROXY_ADMIN_OWNER, "");
        stakingNodesManagerProxy = new TransparentUpgradeableProxy(address(stakingNodesManager), actors.admin.PROXY_ADMIN_OWNER, "");

        executionLayerReceiverProxy = new TransparentUpgradeableProxy(address(executionLayerReceiver), actors.admin.PROXY_ADMIN_OWNER, "");
        consensusLayerReceiverProxy = new TransparentUpgradeableProxy(address(consensusLayerReceiver), actors.admin.PROXY_ADMIN_OWNER, "");

        executionLayerReceiver = RewardsReceiver(payable(executionLayerReceiverProxy));
        consensusLayerReceiver = RewardsReceiver(payable(consensusLayerReceiverProxy));

        // Wrapping proxies with their respective interfaces
        yneth = ynETH(payable(ynethProxy));
        stakingNodesManager = StakingNodesManager(payable(stakingNodesManagerProxy));

        // Re-deploying ynETH and creating its proxy again
        yneth = new ynETH();
        ynethProxy = new TransparentUpgradeableProxy(address(yneth), actors.admin.PROXY_ADMIN_OWNER, "");
        yneth = ynETH(payable(ynethProxy));

        // Re-deploying StakingNodesManager and creating its proxy again
        stakingNodesManager = new StakingNodesManager();
        stakingNodesManagerProxy = new TransparentUpgradeableProxy(address(stakingNodesManager), actors.admin.PROXY_ADMIN_OWNER, "");
        stakingNodesManager = StakingNodesManager(payable(stakingNodesManagerProxy));
    }

    function setupYnLSDProxies() public {
        TransparentUpgradeableProxy ynLSDProxy;
        TransparentUpgradeableProxy yieldNestOracleProxy;

        yieldNestOracle = new YieldNestOracle();
        ynlsd = new ynLSD();

        yieldNestOracleProxy = new TransparentUpgradeableProxy(address(yieldNestOracle), actors.admin.PROXY_ADMIN_OWNER, "");
        ynLSDProxy = new TransparentUpgradeableProxy(address(ynlsd), actors.admin.PROXY_ADMIN_OWNER, "");

        yieldNestOracle = YieldNestOracle(address(yieldNestOracleProxy));
        ynlsd = ynLSD(address(ynLSDProxy));
    }

    function setupUtils() public {
        viewer = new ynViewer(yneth, stakingNodesManager);

        ReferralDepositAdapter referralDepositAdapterImplementation;
        TransparentUpgradeableProxy referralDepositAdapterProxy;

        referralDepositAdapterImplementation = new ReferralDepositAdapter();
        referralDepositAdapterProxy = new TransparentUpgradeableProxy(address(referralDepositAdapterImplementation), actors.admin.PROXY_ADMIN_OWNER, "");
        referralDepositAdapter = ReferralDepositAdapter(payable(address(referralDepositAdapterProxy)));
        
        IReferralDepositAdapter.Init memory initArgs = IReferralDepositAdapter.Init({
            admin: actors.admin.ADMIN,
            referralPublisher: actors.ops.REFERAL_PUBLISHER,
            _ynETH: yneth
        });
        referralDepositAdapter.initialize(initArgs);
    }

    function setupEthereum() public {
        depositContractEth2 = IDepositContract(chainAddresses.ethereum.DEPOSIT_2_ADDRESS);
    }

    function setupEigenLayer() public {
        delayedWithdrawalRouter = IDelayedWithdrawalRouter(vm.addr(6));
        strategyManager = IStrategyManager(vm.addr(7));
        eigenPodManager = IEigenPodManager(chainAddresses.eigenlayer.EIGENPOD_MANAGER_ADDRESS);
        delegationManager = IDelegationManager(chainAddresses.eigenlayer.DELEGATION_MANAGER_ADDRESS);
        delayedWithdrawalRouter = IDelayedWithdrawalRouter(chainAddresses.eigenlayer.DELAYED_WITHDRAWAL_ROUTER_ADDRESS); // Assuming DEPOSIT_2_ADDRESS is used for DelayedWithdrawalRouter
        strategyManager = IStrategyManager(chainAddresses.eigenlayer.STRATEGY_MANAGER_ADDRESS);
    }

    function setupYnETH() public {
        address[] memory pauseWhitelist = new address[](1);
        pauseWhitelist[0] = actors.eoa.DEFAULT_SIGNER;
        
        ynETH.Init memory ynethInit = ynETH.Init({
            admin: actors.admin.ADMIN,
            pauser: actors.ops.PAUSE_ADMIN,
            unpauser: actors.admin.UNPAUSE_ADMIN,
            stakingNodesManager: IStakingNodesManager(address(stakingNodesManager)),
            rewardsDistributor: IRewardsDistributor(address(rewardsDistributor)),
            pauseWhitelist: pauseWhitelist
        });

        yneth.initialize(ynethInit);
    }

    function setupRewardsDistributor() public {

        RewardsReceiver.Init memory rewardsReceiverInit = RewardsReceiver.Init({
            admin: actors.admin.ADMIN,
            withdrawer: address(rewardsDistributor)
        });
        vm.startPrank(actors.admin.PROXY_ADMIN_OWNER);
        executionLayerReceiver.initialize(rewardsReceiverInit);
        consensusLayerReceiver.initialize(rewardsReceiverInit);
        vm.stopPrank();
        RewardsDistributor.Init memory rewardsDistributorInit = RewardsDistributor.Init({
            admin: actors.admin.ADMIN,
            rewardsAdmin: actors.admin.REWARDS_ADMIN,
            executionLayerReceiver: executionLayerReceiver,
            consensusLayerReceiver: consensusLayerReceiver,
            feesReceiver: payable(actors.admin.FEE_RECEIVER),
            ynETH: IynETH(address(yneth))
        });
        rewardsDistributor.initialize(rewardsDistributorInit);
    }

    function setupStakingNodesManager() public {
        stakingNodeImplementation = new StakingNode();

        StakingNodesManager.Init memory stakingNodesManagerInit = StakingNodesManager.Init({
            admin: actors.admin.ADMIN,
            stakingAdmin: actors.admin.STAKING_ADMIN,
            stakingNodesOperator: actors.ops.STAKING_NODES_OPERATOR,
            stakingNodesDelegator: actors.admin.STAKING_NODES_DELEGATOR,
            validatorManager: actors.ops.VALIDATOR_MANAGER,
            pauser: actors.ops.PAUSE_ADMIN,
            unpauser: actors.admin.UNPAUSE_ADMIN,
            maxNodeCount: 10,
            depositContract: depositContractEth2,
            ynETH: IynETH(address(yneth)),
            eigenPodManager: eigenPodManager,
            delegationManager: delegationManager,
            delayedWithdrawalRouter: delayedWithdrawalRouter,
            strategyManager: strategyManager,
            rewardsDistributor: IRewardsDistributor(address(rewardsDistributor)),
            stakingNodeCreatorRole:  actors.ops.STAKING_NODE_CREATOR
        });
        vm.prank(actors.admin.PROXY_ADMIN_OWNER);
        stakingNodesManager.initialize(stakingNodesManagerInit);
        vm.prank(actors.admin.STAKING_ADMIN); // StakingNodesManager is the only contract that can register a staking node implementation contract
        stakingNodesManager.registerStakingNodeImplementationContract(address(stakingNodeImplementation));
    }
    
    function setupYieldNestOracleAndYnLSD() public {
        IERC20[] memory assets = new IERC20[](2);
        address[] memory assetsAddresses = new address[](2);
        address[] memory priceFeeds = new address[](2);
        uint256[] memory maxAges = new uint256[](2);
        IStrategy[] memory strategies = new IStrategy[](2);

        address[] memory pauseWhitelist = new address[](1);
        pauseWhitelist[0] = actors.ops.PAUSE_ADMIN;

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
            admin: actors.admin.ADMIN,
            oracleManager: actors.admin.ORACLE_ADMIN
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
            admin: actors.admin.ADMIN,
            unpauser: actors.admin.UNPAUSE_ADMIN,
            stakingAdmin: actors.admin.STAKING_ADMIN,
            lsdRestakingManager: actors.ops.LSD_RESTAKING_MANAGER,
            lsdStakingNodeCreatorRole: actors.ops.STAKING_NODE_CREATOR,
            pauseWhitelist: pauseWhitelist,
            pauser: actors.ops.PAUSE_ADMIN,
            depositBootstrapper: actors.eoa.DEPOSIT_BOOTSTRAPPER
        });

        TestAssetUtils testAssetUtils = new TestAssetUtils();
        testAssetUtils.get_stETH(actors.eoa.DEPOSIT_BOOTSTRAPPER, 10000 ether);

        vm.prank(actors.eoa.DEPOSIT_BOOTSTRAPPER);
        IERC20(chainAddresses.lsd.STETH_ADDRESS).approve(address(ynlsd), type(uint256).max);
        ynlsd.initialize(init);

        vm.prank(actors.admin.STAKING_ADMIN);
        ynlsd.registerLSDStakingNodeImplementationContract(address(lsdStakingNodeImplementation));
    }
}

