// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {TransparentUpgradeableProxy, ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import {IStrategyManager} from "@eigenlayer-contracts/interfaces/IStrategyManager.sol";
import {IEigenPodManager} from "@eigenlayer-contracts/interfaces/IEigenPodManager.sol";
import {IStrategy} from "@eigenlayer-contracts/interfaces/IStrategy.sol";
import {IDelegationManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";

import {Utils} from "../../../script/Utils.sol";
import {ContractAddresses} from "../../../script/ContractAddresses.sol";
import {ActorAddresses} from "../../../script/Actors.sol";

import {IDepositContract} from "../../../src/external/ethereum/IDepositContract.sol";

import {IRedeemableAsset} from "../../../src/interfaces/IRedeemableAsset.sol";
import {IRedemptionAssetsVault} from "../../../src/interfaces/IRedemptionAssetsVault.sol";
import {IRewardsDistributor} from "../../../src/interfaces/IRewardsDistributor.sol";
import {IynETH} from "../../../src/interfaces/IynETH.sol";

import {ynETH} from "../../../src/ynETH.sol";
import {StakingNodesManager} from "../../../src/StakingNodesManager.sol";
import {StakingNode} from "../../../src/StakingNode.sol";
import {RewardsReceiver} from "../../../src/RewardsReceiver.sol";
import {RewardsDistributor} from "../../../src/RewardsDistributor.sol";
import {StakingNode} from "../../../src/StakingNode.sol";
import {WithdrawalQueueManager} from "../../../src/WithdrawalQueueManager.sol";
import {ynETHRedemptionAssetsVault} from "../../../src/ynETHRedemptionAssetsVault.sol";

import "forge-std/console.sol";
import "forge-std/Test.sol";

contract Base is Test, Utils {

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

    // EigenLayer
    IEigenPodManager public eigenPodManager;
    IDelegationManager public delegationManager;
    IStrategyManager public strategyManager;

    // Ethereum
    IDepositContract public depositContractEth2;

    address GLOBAL_ADMIN = 0x72fdBD51085bDa5eEEd3b55D1a46E2e92f0837a5;

    function setUp() public virtual {
        assignContracts();
        upgradeYnToM3();
    }

    function assignContracts() internal {
        contractAddresses = new ContractAddresses();
        chainAddresses = contractAddresses.getChainAddresses(block.chainid);
        actorAddresses = new ActorAddresses();
        actors = actorAddresses.getActors(block.chainid);

        // Assign YieldNest addresses
        {
            yneth = ynETH(payable(chainAddresses.yn.YNETH_ADDRESS));
            stakingNodesManager = StakingNodesManager(payable(chainAddresses.yn.STAKING_NODES_MANAGER_ADDRESS));
            rewardsDistributor = RewardsDistributor(payable(chainAddresses.yn.REWARDS_DISTRIBUTOR_ADDRESS));
            executionLayerReceiver = RewardsReceiver(payable(chainAddresses.yn.EXECUTION_LAYER_RECEIVER_ADDRESS));
            consensusLayerReceiver = RewardsReceiver(payable(chainAddresses.yn.CONSENSUS_LAYER_RECEIVER_ADDRESS));
        }

        // Assign Ethereum addresses
        {
            depositContractEth2 = IDepositContract(chainAddresses.ethereum.DEPOSIT_2_ADDRESS);
        }

        // Assign Eigenlayer addresses
        {
            eigenPodManager = IEigenPodManager(chainAddresses.eigenlayer.EIGENPOD_MANAGER_ADDRESS);
            delegationManager = IDelegationManager(chainAddresses.eigenlayer.DELEGATION_MANAGER_ADDRESS);
            strategyManager = IStrategyManager(chainAddresses.eigenlayer.STRATEGY_MANAGER_ADDRESS);
        }
    }

    function upgradeYnToM3() internal {
        if (block.chainid != 17000) return;

        // upgrade stakingNodesManager
        {
            vm.prank(GLOBAL_ADMIN);
            ProxyAdmin(
                getTransparentUpgradeableProxyAdminAddress(address(stakingNodesManager))
            ).upgradeAndCall(
                ITransparentUpgradeableProxy(address(stakingNodesManager)),
                address(new StakingNodesManager()),
                ""
            );
        }

        // upgrade ynETH
        {
            vm.prank(GLOBAL_ADMIN);
            ProxyAdmin(
                getTransparentUpgradeableProxyAdminAddress(address(yneth))
            ).upgradeAndCall(
                ITransparentUpgradeableProxy(address(yneth)),
                address(new ynETH()),
                ""
            );
        }

        // deploy ynETHRedemptionAssetsVault
        {
            TransparentUpgradeableProxy _proxy = new TransparentUpgradeableProxy(
                address(new ynETHRedemptionAssetsVault()),
                GLOBAL_ADMIN,
                ""
            );
            ynETHRedemptionAssetsVaultInstance = ynETHRedemptionAssetsVault(payable(address(_proxy)));
        }

        // deploy WithdrawalQueueManager
        {
            TransparentUpgradeableProxy _proxy = new TransparentUpgradeableProxy(
                address(new WithdrawalQueueManager()),
                GLOBAL_ADMIN,
                ""
            );
            ynETHWithdrawalQueueManager = WithdrawalQueueManager(address(_proxy));
        }

        // initialize ynETHRedemptionAssetsVault
        {
            ynETHRedemptionAssetsVault.Init memory _init = ynETHRedemptionAssetsVault.Init({
                admin: GLOBAL_ADMIN,
                redeemer: address(ynETHWithdrawalQueueManager),
                ynETH: IynETH(address(yneth))
            });
            ynETHRedemptionAssetsVaultInstance.initialize(_init);
        }

        // initialize WithdrawalQueueManager
        {
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
        }

        // initialize stakingNodesManager
        {
            StakingNodesManager.Init memory _init = StakingNodesManager.Init({
                admin: GLOBAL_ADMIN,
                stakingAdmin: GLOBAL_ADMIN,
                stakingNodesOperator: GLOBAL_ADMIN,
                stakingNodesDelegator: GLOBAL_ADMIN,
                validatorManager: GLOBAL_ADMIN,
                stakingNodeCreatorRole: GLOBAL_ADMIN,
                pauser: GLOBAL_ADMIN,
                unpauser: GLOBAL_ADMIN,
                maxNodeCount: stakingNodesManager.maxNodeCount(),
                ynETH: IynETH(address(yneth)),
                rewardsDistributor: IRewardsDistributor(address(rewardsDistributor)),
                depositContract: IDepositContract(address(depositContractEth2)),
                eigenPodManager: IEigenPodManager(address(eigenPodManager)),
                delegationManager: IDelegationManager(address(delegationManager)),
                strategyManager: IStrategyManager(address(strategyManager))
            });
            vm.prank(GLOBAL_ADMIN);
            stakingNodesManager.initialize(_init);
        }

        // initialize stakingNodesManager withdrawal contracts
        {
            StakingNodesManager.Init2 memory initParams = StakingNodesManager.Init2({
                redemptionAssetsVault: ynETHRedemptionAssetsVaultInstance,
                withdrawalManager: GLOBAL_ADMIN,
                stakingNodesWithdrawer: GLOBAL_ADMIN
            });
            
            vm.prank(GLOBAL_ADMIN);
            stakingNodesManager.initializeV2(initParams);
        }

        // upgrade StakingNodeImplementation
        {
            stakingNodeImplementation = new StakingNode();
            vm.prank(GLOBAL_ADMIN);
            stakingNodesManager.upgradeStakingNodeImplementation(address(stakingNodeImplementation));
        }

        // grant burner role
        {
            vm.prank(GLOBAL_ADMIN);
            yneth.grantRole(yneth.BURNER_ROLE(), address(ynETHWithdrawalQueueManager));
        }

        // unpause ynETH transfers, in case they are paused
        {
            vm.prank(GLOBAL_ADMIN);
            yneth.unpauseTransfers();
        }
    }
}
