// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {TransparentUpgradeableProxy} from "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IStrategyManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
// import {IDelayedWithdrawalRouter} from "lib/eigenlayer-contracts/src/contracts/interfaces/IDelayedWithdrawalRouter.sol";
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
import {ynLSD} from "src/ynLSD.sol";
import {YieldNestOracle} from "src/YieldNestOracle.sol";
import {LSDStakingNode} from "src/LSDStakingNode.sol";
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
import {HoleskyStakingNodesManager} from "src/HoleskyStakingNodesManager.sol";
import {ITransparentUpgradeableProxy} from "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {WithdrawalQueueManager} from "src/WithdrawalQueueManager.sol";
import { ynETHRedemptionAssetsVault } from "src/ynETHRedemptionAssetsVault.sol";
import {IRedeemableAsset} from "src/interfaces/IRedeemableAsset.sol";
import {IRedemptionAssetsVault} from "src/interfaces/IRedemptionAssetsVault.sol";
import {IStakingNode} from "src/interfaces/IStakingNode.sol";
import {PreProdHoleskyStakingNodesManager} from "src/PreProdHoleskystakingNodesManager.sol";
import "forge-std/console.sol";



contract PreProdForkBaseTest is Test, Utils {

    // Utils
    ContractAddresses public contractAddresses;
    ContractAddresses.ChainAddresses public chainAddresses;
    ActorAddresses public actorAddresses;
    ActorAddresses.Actors public actors;

    // Rewards
    RewardsReceiver public executionLayerReceiver;
    RewardsReceiver public consensusLayerReceiver;
    RewardsDistributor public rewardsDistributor;

    // Staking
    StakingNodesManager public stakingNodesManager;
    StakingNode public stakingNodeImplementation;

    // Assets
    ynETH public yneth;

    // Withdrawals
    WithdrawalQueueManager public ynETHWithdrawalQueueManager;
    ynETHRedemptionAssetsVault public ynETHRedemptionAssetsVaultInstance;

    // Eigen
    IEigenPodManager public eigenPodManager;
    IDelegationManager public delegationManager;
    // IDelayedWithdrawalRouter public delayedWithdrawalRouter;
    IStrategyManager public strategyManager;

    // Ethereum
    IDepositContract public depositContractEth2;

    address GLOBAL_ADMIN = 0x72fdBD51085bDa5eEEd3b55D1a46E2e92f0837a5;

    function setUp() public virtual {
        assignContracts();
        applyNextReleaseUpgrades();
    }
    function assignContracts() internal {
        uint256 chainId = block.chainid;

        contractAddresses = new ContractAddresses();
        chainAddresses = contractAddresses.getChainAddresses(chainId);

        actorAddresses = new ActorAddresses();
        actors = actorAddresses.getActors(block.chainid);

        // Assign Ethereum addresses
        depositContractEth2 = IDepositContract(chainAddresses.ethereum.DEPOSIT_2_ADDRESS);

        // SOURCE: https://hackmd.io/kZp6wiC8S-aIwStA0-XyMw

        // Assign Eigenlayer addresses
        eigenPodManager = IEigenPodManager(0xB8d8952f572e67B11e43bC21250967772fa883Ff);
        delegationManager = IDelegationManager(0x75dfE5B44C2E530568001400D3f704bC8AE350CC);
        // delayedWithdrawalRouter = IDelayedWithdrawalRouter(chainAddresses.eigenlayer.DELAYED_WITHDRAWAL_ROUTER_ADDRESS);
        strategyManager = IStrategyManager(chainAddresses.eigenlayer.STRATEGY_MANAGER_ADDRESS);

        // Assign LSD addresses
        // Example: sfrxeth = ISFRXETH(chainAddresses.lsd.SFRXETH_ADDRESS);


        /*
            Pre-prod deployment:
        "proxy-ynETH": "0xe8A0fA11735b9C91F5F89340A2E2720e9c9d19fb",
        "proxyAdmin-consensusLayerReceiver": "0x3e6dfcbEF005449211966eb2c2E3Ec2EbcFF0115",
        "proxyAdmin-executionLayerReceiver": "0x587E799d2A28C6C9115F990833dFcCa025FC73f1",
        "proxyAdmin-rewardsDistributor": "0x01f35923731D82dD1E40267DF6C8D7aF9A8C6fDa",
        "proxyAdmin-stakingNodesManager": "0x68F28E059f95c861F1aC6b0884bCDFC8355395Ac",
        "proxyAdmin-ynETH": "0xd44C0b9eA1dFfDBF9d5B2Ab8c432F70772D1B6BD",
        */

        // Assign YieldNest addresses
        yneth = ynETH(payable(chainAddresses.yn.YNETH_ADDRESS));
        stakingNodesManager = StakingNodesManager(payable(chainAddresses.yn.STAKING_NODES_MANAGER_ADDRESS));
        rewardsDistributor = RewardsDistributor(payable(chainAddresses.yn.REWARDS_DISTRIBUTOR_ADDRESS));
        executionLayerReceiver = RewardsReceiver(payable(chainAddresses.yn.EXECUTION_LAYER_RECEIVER_ADDRESS));
        consensusLayerReceiver = RewardsReceiver(payable(chainAddresses.yn.CONSENSUS_LAYER_RECEIVER_ADDRESS));

        console.log("ynETH address:", address(yneth));
        console.log("StakingNodesManager address:", address(stakingNodesManager));
        console.log("RewardsDistributor address:", address(rewardsDistributor));
        console.log("ExecutionLayerReceiver address:", address(executionLayerReceiver));
        console.log("ConsensusLayerReceiver address:", address(consensusLayerReceiver));
    }

    function applyNextReleaseUpgrades() internal {

        if (block.chainid != 17000) {
            // not applicable
            return;
        }

        vm.prank(GLOBAL_ADMIN);
        yneth.unpauseTransfers();

        address newStakingNodesManagerImpl = address(new PreProdHoleskyStakingNodesManager());

        // Print the number of staking nodes
        uint256 nodesLengthBefore = stakingNodesManager.nodesLength();
        console.log("Number of staking nodes before upgrade:", nodesLengthBefore);

        
        vm.prank(GLOBAL_ADMIN);
        ProxyAdmin(getTransparentUpgradeableProxyAdminAddress(address(stakingNodesManager))).upgradeAndCall(ITransparentUpgradeableProxy(address(stakingNodesManager)), newStakingNodesManagerImpl, "");

        uint256 nodesLengthAfter = stakingNodesManager.nodesLength();
        console.log("Number of staking nodes after upgrade:", nodesLengthAfter);

        address newynETHImpl = address(new ynETH());
        vm.prank(GLOBAL_ADMIN);
        ProxyAdmin(getTransparentUpgradeableProxyAdminAddress(address(yneth))).upgradeAndCall(ITransparentUpgradeableProxy(address(yneth)), newynETHImpl, "");

        ynETHRedemptionAssetsVault ynethRedemptionAssetsVaultImplementation = new ynETHRedemptionAssetsVault();
        TransparentUpgradeableProxy ynethRedemptionAssetsVaultProxy = new TransparentUpgradeableProxy(
            address(ynethRedemptionAssetsVaultImplementation),
            GLOBAL_ADMIN,
            ""
        );
        ynETHRedemptionAssetsVaultInstance = ynETHRedemptionAssetsVault(payable(address(ynethRedemptionAssetsVaultProxy)));

        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(new WithdrawalQueueManager()),
            GLOBAL_ADMIN,
            ""
        );
        ynETHWithdrawalQueueManager = WithdrawalQueueManager(address(proxy));

        ynETHRedemptionAssetsVault.Init memory vaultInit = ynETHRedemptionAssetsVault.Init({
            admin: GLOBAL_ADMIN,
            redeemer: address(ynETHWithdrawalQueueManager),
            ynETH: IynETH(address(yneth))
        });
        ynETHRedemptionAssetsVaultInstance.initialize(vaultInit);

        WithdrawalQueueManager.Init memory managerInit = WithdrawalQueueManager.Init({
            name: "ynETH Withdrawal Manager",
            symbol: "ynETHWM",
            redeemableAsset: IRedeemableAsset(address(yneth)),
            redemptionAssetsVault: IRedemptionAssetsVault(address(ynETHRedemptionAssetsVaultInstance)),
            admin: GLOBAL_ADMIN,
            withdrawalQueueAdmin: GLOBAL_ADMIN,
            redemptionAssetWithdrawer: GLOBAL_ADMIN,
            requestFinalizer:  GLOBAL_ADMIN,
            withdrawalFee: 500, // 0.05%
            feeReceiver: GLOBAL_ADMIN
        });
        ynETHWithdrawalQueueManager.initialize(managerInit);

        StakingNodesManager.Init2 memory initParams = StakingNodesManager.Init2({
            redemptionAssetsVault: ynETHRedemptionAssetsVaultInstance,
            withdrawalManager: GLOBAL_ADMIN,
            stakingNodesWithdrawer: GLOBAL_ADMIN
        });
        
        vm.prank(GLOBAL_ADMIN);
        stakingNodesManager.initializeV2(initParams);
        assert(stakingNodesManager.hasRole(stakingNodesManager.WITHDRAWAL_MANAGER_ROLE(), GLOBAL_ADMIN));
        console.log("WITHDRAWAL_MANAGER address:", actors.ops.WITHDRAWAL_MANAGER);

        stakingNodeImplementation = new StakingNode();

        // Print the number of staking nodes
        uint256 nodesLength = stakingNodesManager.nodesLength();
        console.log("Number of staking nodes:", nodesLength);

        // Print ETH balance of staking node 1 before upgrade
        IStakingNode stakingNode1 = stakingNodesManager.nodes(1);
        uint256 balanceBefore = stakingNode1.getETHBalance();
        console.log("Staking Node 1 ETH balance before upgrade:", balanceBefore);

        vm.prank(GLOBAL_ADMIN);
        stakingNodesManager.upgradeStakingNodeImplementation(address(stakingNodeImplementation));

        // Print ETH balance of staking node 1 after upgrade
        uint256 balanceAfter = stakingNode1.getETHBalance();
        console.log("Staking Node 1 ETH balance after upgrade:", balanceAfter);

        // Print ETH balance of staking node 0
        IStakingNode stakingNode0 = stakingNodesManager.nodes(0);
        uint256 balanceNode0 = stakingNode0.getETHBalance();
        console.log("Staking Node 0 ETH balance:", balanceNode0);

        // Print totalAssets of ynETH
        uint256 totalAssets = yneth.totalAssets();
        console.log("ynETH total assets:", totalAssets);

        bytes32 burnerRole = yneth.BURNER_ROLE();
        vm.prank(GLOBAL_ADMIN);
        yneth.grantRole(burnerRole, address(ynETHWithdrawalQueueManager));
    }
}