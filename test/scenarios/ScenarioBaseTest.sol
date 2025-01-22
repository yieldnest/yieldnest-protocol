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
import {ITransparentUpgradeableProxy} from "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {WithdrawalQueueManager} from "src/WithdrawalQueueManager.sol";
import {WithdrawalsProcessor} from "src/WithdrawalsProcessor.sol";

import { ynETHRedemptionAssetsVault } from "src/ynETHRedemptionAssetsVault.sol";
import {IRedeemableAsset} from "src/interfaces/IRedeemableAsset.sol";
import {IRedemptionAssetsVault} from "src/interfaces/IRedemptionAssetsVault.sol";
import "forge-std/console.sol";


contract ScenarioBaseTest is Test, Utils {

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
    WithdrawalsProcessor public withdrawalsProcessor;

    // Eigen
    IEigenPodManager public eigenPodManager;
    IDelegationManager public delegationManager;
    // IDelayedWithdrawalRouter public delayedWithdrawalRouter;
    IStrategyManager public strategyManager;

    // Ethereum
    IDepositContract public depositContractEth2;

    function setUp() public virtual {
        assignContracts();

        // Upgrade StakingNode implementation with EL slashing upgrade changes
        if (block.chainid == 17000) { // Holesky chain ID
            address newStakingNodeImplementation = address(new StakingNode());
            vm.startPrank(actors.admin.STAKING_ADMIN);
            stakingNodesManager.upgradeStakingNodeImplementation(newStakingNodeImplementation);
            vm.stopPrank();
        }
    }
    function assignContracts() internal {
        uint256 chainId = block.chainid;

        contractAddresses = new ContractAddresses();
        chainAddresses = contractAddresses.getChainAddresses(chainId);

        actorAddresses = new ActorAddresses();
        actors = actorAddresses.getActors(block.chainid);

        // Assign Ethereum addresses
        depositContractEth2 = IDepositContract(chainAddresses.ethereum.DEPOSIT_2_ADDRESS);

        // Assign Eigenlayer addresses
        eigenPodManager = IEigenPodManager(chainAddresses.eigenlayer.EIGENPOD_MANAGER_ADDRESS);
        delegationManager = IDelegationManager(chainAddresses.eigenlayer.DELEGATION_MANAGER_ADDRESS);
        // delayedWithdrawalRouter = IDelayedWithdrawalRouter(chainAddresses.eigenlayer.DELAYED_WITHDRAWAL_ROUTER_ADDRESS);
        strategyManager = IStrategyManager(chainAddresses.eigenlayer.STRATEGY_MANAGER_ADDRESS);

        // Assign LSD addresses
        // Example: sfrxeth = ISFRXETH(chainAddresses.lsd.SFRXETH_ADDRESS);

        // Assign YieldNest addresses
        yneth = ynETH(payable(chainAddresses.yn.YNETH_ADDRESS));
        stakingNodesManager = StakingNodesManager(payable(chainAddresses.yn.STAKING_NODES_MANAGER_ADDRESS));
        rewardsDistributor = RewardsDistributor(payable(chainAddresses.yn.REWARDS_DISTRIBUTOR_ADDRESS));
        executionLayerReceiver = RewardsReceiver(payable(chainAddresses.yn.EXECUTION_LAYER_RECEIVER_ADDRESS));
        consensusLayerReceiver = RewardsReceiver(payable(chainAddresses.yn.CONSENSUS_LAYER_RECEIVER_ADDRESS));
        ynETHWithdrawalQueueManager = WithdrawalQueueManager(payable(chainAddresses.yn.WITHDRAWAL_QUEUE_MANAGER_ADDRESS));
        ynETHRedemptionAssetsVaultInstance = ynETHRedemptionAssetsVault(payable(chainAddresses.yn.YNETH_REDEMPTION_ASSETS_VAULT_ADDRESS));
        withdrawalsProcessor = WithdrawalsProcessor(payable(chainAddresses.yn.WITHDRAWALS_PROCESSOR_ADDRESS));
    }
}