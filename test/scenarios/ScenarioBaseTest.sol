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
import {HoleskyStakingNodesManager} from "src/HoleskyStakingNodesManager.sol";
import {ITransparentUpgradeableProxy} from "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {WithdrawalQueueManager} from "src/WithdrawalQueueManager.sol";
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

    // Eigen
    IEigenPodManager public eigenPodManager;
    IDelegationManager public delegationManager;
    // IDelayedWithdrawalRouter public delayedWithdrawalRouter;
    IStrategyManager public strategyManager;

    // Ethereum
    IDepositContract public depositContractEth2;

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
    }

    function applyNextReleaseUpgrades() internal {

        vm.prank(actors.admin.UNPAUSE_ADMIN);
        yneth.unpauseTransfers();

        address newStakingNodesManagerImpl = block.chainid == 17000
            ? address(new HoleskyStakingNodesManager())
            : address(new StakingNodesManager());
        
        vm.prank(actors.wallets.YNSecurityCouncil);
        ProxyAdmin(getTransparentUpgradeableProxyAdminAddress(address(stakingNodesManager))).upgradeAndCall(ITransparentUpgradeableProxy(address(stakingNodesManager)), newStakingNodesManagerImpl, "");

        address newynETHImpl = address(new ynETH());
        vm.prank(actors.wallets.YNSecurityCouncil);
        ProxyAdmin(getTransparentUpgradeableProxyAdminAddress(address(yneth))).upgradeAndCall(ITransparentUpgradeableProxy(address(yneth)), newynETHImpl, "");

        ynETHRedemptionAssetsVault ynethRedemptionAssetsVaultImplementation = new ynETHRedemptionAssetsVault();
        TransparentUpgradeableProxy ynethRedemptionAssetsVaultProxy = new TransparentUpgradeableProxy(
            address(ynethRedemptionAssetsVaultImplementation),
            actors.admin.PROXY_ADMIN_OWNER,
            ""
        );
        ynETHRedemptionAssetsVaultInstance = ynETHRedemptionAssetsVault(payable(address(ynethRedemptionAssetsVaultProxy)));

        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(new WithdrawalQueueManager()),
            actors.admin.PROXY_ADMIN_OWNER,
            ""
        );
        ynETHWithdrawalQueueManager = WithdrawalQueueManager(address(proxy));

        ynETHRedemptionAssetsVault.Init memory vaultInit = ynETHRedemptionAssetsVault.Init({
            admin: actors.admin.PROXY_ADMIN_OWNER,
            redeemer: address(ynETHWithdrawalQueueManager),
            ynETH: IynETH(address(yneth))
        });
        ynETHRedemptionAssetsVaultInstance.initialize(vaultInit);

        WithdrawalQueueManager.Init memory managerInit = WithdrawalQueueManager.Init({
            name: "ynETH Withdrawal Manager",
            symbol: "ynETHWM",
            redeemableAsset: IRedeemableAsset(address(yneth)),
            redemptionAssetsVault: IRedemptionAssetsVault(address(ynETHRedemptionAssetsVaultInstance)),
            admin: actors.admin.PROXY_ADMIN_OWNER,
            withdrawalQueueAdmin: actors.ops.WITHDRAWAL_MANAGER,
            redemptionAssetWithdrawer: actors.ops.REDEMPTION_ASSET_WITHDRAWER,
            requestFinalizer:  actors.ops.REQUEST_FINALIZER,
            withdrawalFee: 500, // 0.05%
            feeReceiver: actors.admin.FEE_RECEIVER
        });
        ynETHWithdrawalQueueManager.initialize(managerInit);

        StakingNodesManager.Init2 memory initParams = StakingNodesManager.Init2({
            redemptionAssetsVault: ynETHRedemptionAssetsVaultInstance,
            withdrawalManager: actors.ops.WITHDRAWAL_MANAGER,
            stakingNodesWithdrawer: actors.ops.STAKING_NODES_WITHDRAWER
        });
        
        vm.prank(actors.admin.ADMIN);
        stakingNodesManager.initializeV2(initParams);
        assert(stakingNodesManager.hasRole(stakingNodesManager.WITHDRAWAL_MANAGER_ROLE(), actors.ops.WITHDRAWAL_MANAGER));
        console.log("WITHDRAWAL_MANAGER address:", actors.ops.WITHDRAWAL_MANAGER);

        stakingNodeImplementation = new StakingNode();
        
        vm.prank(actors.admin.STAKING_ADMIN);
        stakingNodesManager.upgradeStakingNodeImplementation(address(stakingNodeImplementation));

        bytes32 burnerRole = yneth.BURNER_ROLE();
        vm.prank(actors.admin.ADMIN);
        yneth.grantRole(burnerRole, address(ynETHWithdrawalQueueManager));
    }
}