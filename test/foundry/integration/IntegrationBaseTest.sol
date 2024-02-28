// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IStrategyManager} from "../../../src/external/eigenlayer/v0.1.0/interfaces/IStrategyManager.sol";
import {IDelayedWithdrawalRouter} from "../../../src/external/eigenlayer/v0.1.0/interfaces/IDelayedWithdrawalRouter.sol";
import {IDepositContract} from "../../../src/external/ethereum/IDepositContract.sol";
import {IEigenPodManager} from "../../../src/external/eigenlayer/v0.1.0/interfaces/IEigenPodManager.sol";
import {IStakingNodesManager} from "../../../src/interfaces/IStakingNodesManager.sol";
import {IDelegationManager} from "../../../src/external/eigenlayer/v0.1.0/interfaces//IDelegationManager.sol";
import {IStakingNodesManager} from "../../../src/interfaces/IStakingNodesManager.sol";
import {IRewardsDistributor} from "../../../src/interfaces/IRewardsDistributor.sol";
import {IynETH} from "../../../src/interfaces/IynETH.sol";
import {IWETH} from "../../../src/external/tokens/IWETH.sol";
import {Test} from "forge-std/Test.sol";
import {WETH} from "../../../src/external/tokens/WETH.sol";
import {ynETH} from "../../../src/ynETH.sol";
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
    uint256 startingExchangeAdjustmentRate;
    bytes   ZERO_PUBLIC_KEY = hex"000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"; 
    bytes   ONE_PUBLIC_KEY = hex"000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001";
    bytes   ZERO_SIGNATURE = hex"000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";
    bytes32 ZERO_DEPOSIT_ROOT = bytes32(0);

    // Utils
    ContractAddresses public contractAddresses;
    ContractAddresses.ChainAddresses public chainAddresses;
    ActorAddresses public actorAddresses;
    ActorAddresses.Actors public actors;
    ynViewer public viewer;

    // Rewards
    RewardsReceiver public executionLayerReceiver;
    RewardsReceiver public consensusLayerReceiver;
    TransparentUpgradeableProxy public rewardsDistributorProxy;
    RewardsDistributor public rewardsDistributor;

    // Staking
    StakingNodesManager public stakingNodesManager;
    TransparentUpgradeableProxy public stakingNodesManagerProxy;
    StakingNode public stakingNodeImplementation;

    // Tokens
    TransparentUpgradeableProxy public ynethProxy;
    ynETH public yneth;

    // Eigen
    IEigenPodManager public eigenPodManager;
    IDelegationManager public delegationManager;
    IDelayedWithdrawalRouter public delayedWithdrawalRouter;
    IStrategyManager public strategyManager;

    // Ethereum
    IDepositContract public depositContractEth2;

    function setUp() public virtual {

        // Setup Addresses
        contractAddresses = new ContractAddresses();
        actorAddresses = new ActorAddresses();

        // // Setup Protocol
        setupUtils();
        setupProxies();
        setupEthereum();
        setupEigenLayer();
        setupRewardsDistributor();
        setupStakingNodesManager();
        setupYnETH();
    }

    function setupProxies() public {
        // Rewards
        RewardsDistributor rewardsDistributorImplementation = new RewardsDistributor();
        rewardsDistributorProxy = new TransparentUpgradeableProxy(address(rewardsDistributorImplementation), actors.PROXY_ADMIN_OWNER, "");
        
        // ETH
        yneth = new ynETH();
        ynethProxy = new TransparentUpgradeableProxy(address(yneth), actors.PROXY_ADMIN_OWNER, "");
        yneth = ynETH(payable(ynethProxy));

        // Staking
        stakingNodesManager = new StakingNodesManager();
        stakingNodesManagerProxy = new TransparentUpgradeableProxy(address(stakingNodesManager), actors.PROXY_ADMIN_OWNER, "");
        stakingNodesManager = StakingNodesManager(payable(stakingNodesManagerProxy));
        vm.stopPrank();
    }

    function setupUtils() public {
        viewer = new ynViewer(yneth, stakingNodesManager);
        chainAddresses = contractAddresses.getChainAddresses(block.chainid);
        actors = actorAddresses.getActors(block.chainid);
    }

    function setupEthereum() public {
        depositContractEth2 = IDepositContract(chainAddresses.DEPOSIT_2_ADDRESS);
    }

    function setupEigenLayer() public {
        eigenPodManager = IEigenPodManager(vm.addr(4));
        delegationManager = IDelegationManager(vm.addr(5));
        delayedWithdrawalRouter = IDelayedWithdrawalRouter(vm.addr(6));
        strategyManager = IStrategyManager(vm.addr(7));
        eigenPodManager = IEigenPodManager(chainAddresses.EIGENLAYER_EIGENPOD_MANAGER_ADDRESS);
        delegationManager = IDelegationManager(chainAddresses.EIGENLAYER_DELEGATION_MANAGER_ADDRESS);
        delayedWithdrawalRouter = IDelayedWithdrawalRouter(chainAddresses.EIGENLAYER_DELAYED_WITHDRAWAL_ROUTER_ADDRESS); // Assuming DEPOSIT_2_ADDRESS is used for DelayedWithdrawalRouter
        strategyManager = IStrategyManager(chainAddresses.EIGENLAYER_STRATEGY_MANAGER_ADDRESS);
    }

    function setupYnETH() public {
        WETH weth = new WETH();
        startingExchangeAdjustmentRate = 4;
        address[] memory pauseWhitelist = new address[](1);
        pauseWhitelist[0] = actors.TRANSFER_ENABLED_EOA;
        ynETH.Init memory ynethInit = ynETH.Init({
            admin: actors.ADMIN,
            pauser: actors.PAUSE_ADMIN,
            stakingNodesManager: IStakingNodesManager(address(stakingNodesManager)),
            rewardsDistributor: IRewardsDistributor(address(rewardsDistributor)),
            wETH: IWETH(address(weth)),  // Deployed WETH address
            exchangeAdjustmentRate: startingExchangeAdjustmentRate,
            pauseWhitelist: pauseWhitelist
        });

        yneth.initialize(ynethInit);
    }

    function setupRewardsDistributor() public {
        executionLayerReceiver = new RewardsReceiver();
        consensusLayerReceiver = new RewardsReceiver();
        rewardsDistributor = RewardsDistributor(payable(rewardsDistributorProxy));
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
        executionLayerReceiver.initialize(rewardsReceiverInit);
        consensusLayerReceiver.initialize(rewardsReceiverInit);
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
            rewardsDistributor: IRewardsDistributor(address(rewardsDistributor))
        });
        stakingNodesManager.initialize(stakingNodesManagerInit);
        vm.prank(actors.STAKING_NODES_ADMIN);
        stakingNodesManager.registerStakingNodeImplementationContract(address(stakingNodeImplementation));
    }
}

