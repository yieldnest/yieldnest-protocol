// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {TransparentUpgradeableProxy} from "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IStrategyManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {TimelockController} from "lib/openzeppelin-contracts/contracts/governance/TimelockController.sol";
// import {IDelayedWithdrawalRouter} from "lib/eigenlayer-contracts/src/contracts/interfaces/IDelayedWithdrawalRouter.sol";
import {IDepositContract} from "src/external/ethereum/IDepositContract.sol";
import {IEigenPodManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IEigenPodManager.sol";
import {IStrategy} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IStakingNodesManager} from "src/interfaces/IStakingNodesManager.sol";
import {IDelegationManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStakingNodesManager} from "src/interfaces/IStakingNodesManager.sol";
import {IRewardsDistributor} from "src/interfaces/IRewardsDistributor.sol";
import {IRewardsCoordinator} from "lib/eigenlayer-contracts/src/contracts/interfaces/IRewardsCoordinator.sol";
import {IReferralDepositAdapter} from "src/interfaces/IReferralDepositAdapter.sol";
import {IynETH} from "src/interfaces/IynETH.sol";
import {Test} from "forge-std/Test.sol";
import {ynETH} from "src/ynETH.sol";
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
import {WithdrawalQueueManager} from "src/WithdrawalQueueManager.sol";
import {ynETHRedemptionAssetsVault} from "src/ynETHRedemptionAssetsVault.sol";
import {IRedeemableAsset} from "src/interfaces/IRedeemableAsset.sol";
import {IRedemptionAssetsVault} from "src/interfaces/IRedemptionAssetsVault.sol";
import {BeaconChainMock, BeaconChainProofs, CheckpointProofs, CredentialProofs, EigenPodManager} from "lib/eigenlayer-contracts/src/test/integration/mocks/BeaconChainMock.t.sol";

contract IntegrationBaseTest is Test, Utils {

    // State
    bytes constant ZERO_PUBLIC_KEY = hex"000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"; 
    bytes constant ONE_PUBLIC_KEY = hex"000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001";
    bytes constant TWO_PUBLIC_KEY = hex"000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002";
    bytes constant  ZERO_SIGNATURE = hex"000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";
    bytes32 constant ZERO_DEPOSIT_ROOT = bytes32(0);
    uint64 public constant GENESIS_TIME_LOCAL = 1 hours * 12;

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

    // Withdrawals
    WithdrawalQueueManager public ynETHWithdrawalQueueManager;
    ynETHRedemptionAssetsVault public ynETHRedemptionAssetsVaultInstance;

    // Staking
    StakingNodesManager public stakingNodesManager;
    StakingNode public stakingNodeImplementation;

    // Assets
    ynETH public yneth;

    // Eigen
    IEigenPodManager public eigenPodManager;
    IDelegationManager public delegationManager;
    // IDelayedWithdrawalRouter public delayedWithdrawalRouter;
    IStrategyManager public strategyManager;
    IRewardsCoordinator public rewardsCoordinator;

    // Ethereum
    IDepositContract public depositContractEth2;

    address public transferEnabledEOA;

    BeaconChainMock public beaconChain;

    address payable public constant EIGENLAYER_TIMELOCK = payable(0xC06Fd4F821eaC1fF1ae8067b36342899b57BAa2d);
    address public constant EIGENLAYER_MULTISIG = 0x461854d84Ee845F905e0eCf6C288DDEEb4A9533F;

    function setUp() public virtual {


        // Setup Addresses
        contractAddresses = new ContractAddresses();
        actorAddresses = new ActorAddresses();
        chainAddresses = contractAddresses.getChainAddresses(block.chainid);
        actors = actorAddresses.getActors(block.chainid);

        // execute scheduled transactions for slashing upgrades
        {
            bytes memory payload = hex"6a76120200000000000000000000000040a2accbd92bca938b02010e17a5b8929b49130d000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001400000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000ea00000000000000000000000000000000000000000000000000000000000000d248d80ff0a00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000cc6008b9566ada63b64d1e1dcf1418b43fd1433b724440000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004499a88ec4000000000000000000000000135dda560e946695d6f155dacafc6f1f25c1f5af000000000000000000000000a396d855d70e1a1ec1a0199adb9845096683b6a2008b9566ada63b64d1e1dcf1418b43fd1433b724440000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004499a88ec400000000000000000000000039053d51b77dc0d36036fc1fcc8cb819df8ef37a000000000000000000000000a75112d1df37fa53a431525cd47a7d7facea7e73008b9566ada63b64d1e1dcf1418b43fd1433b724440000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004499a88ec40000000000000000000000007750d328b314effa365a0402ccfd489b80b0adda000000000000000000000000a505c0116ad65071f0130061f94745b7853220ab008b9566ada63b64d1e1dcf1418b43fd1433b724440000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004499a88ec4000000000000000000000000858646372cc42e1a627fce94aa7a7033e7cf075a000000000000000000000000ba4b2b8a076851a3044882493c2e36503d50b925005a2a4f2f3c18f09179b6703e63d9edd165909073000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000243659cfe6000000000000000000000000b132a8dad03a507f1b9d2f467a4936df2161c63e008b9566ada63b64d1e1dcf1418b43fd1433b724440000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004499a88ec400000000000000000000000091e677b07f7af907ec9a428aafa9fc14a0d3a3380000000000000000000000009801266cbbbe1e94bb9daf7de8d61528f49cec77008b9566ada63b64d1e1dcf1418b43fd1433b724440000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004499a88ec4000000000000000000000000acb55c530acdb2849e6d4f36992cd8c9d50ed8f700000000000000000000000090b074ddd680bd06c72e28b09231a0f848205729000ed6703c298d28ae0878d1b28e88ca87f9662fe9000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000243659cfe60000000000000000000000000ec17ef9c00f360db28ca8008684a4796b11e456008b9566ada63b64d1e1dcf1418b43fd1433b724440000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004499a88ec40000000000000000000000005e4c39ad7a3e881585e383db9827eb4811f6f6470000000000000000000000001b97d8f963179c0e17e5f3d85cdfd9a31a49bc66008b9566ada63b64d1e1dcf1418b43fd1433b724440000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004499a88ec400000000000000000000000093c4b944d05dfe6df7645a86cd2206016c51564d000000000000000000000000afda870d4a94b9444f9f22a0e61806178b6bf178008b9566ada63b64d1e1dcf1418b43fd1433b724440000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004499a88ec40000000000000000000000001bee69b7dfffa4e2d53c2a2df135c388ad25dcd2000000000000000000000000afda870d4a94b9444f9f22a0e61806178b6bf178008b9566ada63b64d1e1dcf1418b43fd1433b724440000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004499a88ec400000000000000000000000054945180db7943c0ed0fee7edab2bd24620256bc000000000000000000000000afda870d4a94b9444f9f22a0e61806178b6bf178008b9566ada63b64d1e1dcf1418b43fd1433b724440000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004499a88ec40000000000000000000000009d7ed45ee2e8fc5482fa2428f15c971e6369011d000000000000000000000000afda870d4a94b9444f9f22a0e61806178b6bf178008b9566ada63b64d1e1dcf1418b43fd1433b724440000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004499a88ec400000000000000000000000013760f50a9d7377e4f20cb8cf9e4c26586c658ff000000000000000000000000afda870d4a94b9444f9f22a0e61806178b6bf178008b9566ada63b64d1e1dcf1418b43fd1433b724440000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004499a88ec4000000000000000000000000a4c637e0f704745d182e4d38cab7e7485321d059000000000000000000000000afda870d4a94b9444f9f22a0e61806178b6bf178008b9566ada63b64d1e1dcf1418b43fd1433b724440000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004499a88ec400000000000000000000000057ba429517c3473b6d34ca9acd56c0e735b94c02000000000000000000000000afda870d4a94b9444f9f22a0e61806178b6bf178008b9566ada63b64d1e1dcf1418b43fd1433b724440000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004499a88ec40000000000000000000000000fe4f44bee93503346a3ac9ee5a26b130a5796d6000000000000000000000000afda870d4a94b9444f9f22a0e61806178b6bf178008b9566ada63b64d1e1dcf1418b43fd1433b724440000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004499a88ec40000000000000000000000007ca911e83dabf90c90dd3de5411a10f1a6112184000000000000000000000000afda870d4a94b9444f9f22a0e61806178b6bf178008b9566ada63b64d1e1dcf1418b43fd1433b724440000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004499a88ec40000000000000000000000008ca7a5d6f3acd3a7a8bc468a8cd0fb14b6bd28b6000000000000000000000000afda870d4a94b9444f9f22a0e61806178b6bf178008b9566ada63b64d1e1dcf1418b43fd1433b724440000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004499a88ec4000000000000000000000000ae60d8180437b5c34bb956822ac2710972584473000000000000000000000000afda870d4a94b9444f9f22a0e61806178b6bf178008b9566ada63b64d1e1dcf1418b43fd1433b724440000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004499a88ec4000000000000000000000000298afb19a105d59e74658c4c334ff360bade6dd2000000000000000000000000afda870d4a94b9444f9f22a0e61806178b6bf1780091e677b07f7af907ec9a428aafa9fc14a0d3a33800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000024fabc1cbc00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000041000000000000000000000000c06fd4f821eac1ff1ae8067b36342899b57baa2d00000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000";
            vm.warp(block.timestamp + 11 days);
            vm.prank(EIGENLAYER_MULTISIG);
            TimelockController(EIGENLAYER_TIMELOCK).execute(0x369e6F597e22EaB55fFb173C6d9cD234BD699111, 0, payload, bytes32(0), bytes32(0));
        }

        // Setup Protocol
        setupYnETHPoxies();
        setupEthereum();
        setupEigenLayer();
        setupRewardsDistributor();
        setupStakingNodesManager();
        setupYnETH();
        setupUtils();
        setupWithdrawalQueueManager();
        setupInitialization();
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

    function setupUtils() public {
        viewer = new ynViewer(address(yneth), address(stakingNodesManager));

        ReferralDepositAdapter referralDepositAdapterImplementation;
        TransparentUpgradeableProxy referralDepositAdapterProxy;

        referralDepositAdapterImplementation = new ReferralDepositAdapter();
        referralDepositAdapterProxy = new TransparentUpgradeableProxy(address(referralDepositAdapterImplementation), actors.admin.PROXY_ADMIN_OWNER, "");
        referralDepositAdapter = ReferralDepositAdapter(payable(address(referralDepositAdapterProxy)));
        
        IReferralDepositAdapter.Init memory initArgs = IReferralDepositAdapter.Init({
            admin: actors.admin.ADMIN,
            referralPublisher: actors.ops.REFERRAL_PUBLISHER,
            _ynETH: yneth
        });
        referralDepositAdapter.initialize(initArgs);
    }

    function setupEthereum() public {
        depositContractEth2 = IDepositContract(chainAddresses.ethereum.DEPOSIT_2_ADDRESS);
        vm.warp(GENESIS_TIME_LOCAL);
        beaconChain = new BeaconChainMock(EigenPodManager(address(eigenPodManager)), GENESIS_TIME_LOCAL);
    }

    function setupEigenLayer() public {
        // delayedWithdrawalRouter = IDelayedWithdrawalRouter(vm.addr(6));
        strategyManager = IStrategyManager(vm.addr(7));
        eigenPodManager = IEigenPodManager(chainAddresses.eigenlayer.EIGENPOD_MANAGER_ADDRESS);
        delegationManager = IDelegationManager(chainAddresses.eigenlayer.DELEGATION_MANAGER_ADDRESS);
        strategyManager = IStrategyManager(chainAddresses.eigenlayer.STRATEGY_MANAGER_ADDRESS);
        rewardsCoordinator = IRewardsCoordinator(chainAddresses.eigenlayer.REWARDS_COORDINATOR_ADDRESS);
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
            // delayedWithdrawalRouter: delayedWithdrawalRouter,
            strategyManager: strategyManager,
            rewardsDistributor: IRewardsDistributor(address(rewardsDistributor)),
            stakingNodeCreatorRole:  actors.ops.STAKING_NODE_CREATOR
        });
        vm.prank(actors.admin.PROXY_ADMIN_OWNER);
        stakingNodesManager.initialize(stakingNodesManagerInit);
        vm.prank(actors.admin.STAKING_ADMIN); // StakingNodesManager is the only contract that can register a staking node implementation contract
        stakingNodesManager.registerStakingNodeImplementationContract(address(stakingNodeImplementation));
    }

    function setupWithdrawalQueueManager() public {

        TransparentUpgradeableProxy _proxy = new TransparentUpgradeableProxy(
            address(new ynETHRedemptionAssetsVault()),
            actors.admin.PROXY_ADMIN_OWNER,
            ""
        );
        ynETHRedemptionAssetsVaultInstance = ynETHRedemptionAssetsVault(payable(address(_proxy)));

        _proxy = new TransparentUpgradeableProxy(
            address(new WithdrawalQueueManager()),
            actors.admin.PROXY_ADMIN_OWNER,
            ""
        );
        ynETHWithdrawalQueueManager = WithdrawalQueueManager(address(_proxy));

        ynETHRedemptionAssetsVault.Init memory _vaultInit = ynETHRedemptionAssetsVault.Init({
            admin: actors.admin.PROXY_ADMIN_OWNER,
            redeemer: address(ynETHWithdrawalQueueManager),
            ynETH: IynETH(address(yneth))
        });
        ynETHRedemptionAssetsVaultInstance.initialize(_vaultInit);

        WithdrawalQueueManager.Init memory _managerInit = WithdrawalQueueManager.Init({
            name: "ynETH Withdrawal Manager",
            symbol: "ynETHWM",
            redeemableAsset: IRedeemableAsset(address(yneth)),
            redemptionAssetsVault: IRedemptionAssetsVault(address(ynETHRedemptionAssetsVaultInstance)),
            admin: actors.admin.PROXY_ADMIN_OWNER,
            withdrawalQueueAdmin: actors.ops.WITHDRAWAL_MANAGER,
            redemptionAssetWithdrawer: actors.ops.REDEMPTION_ASSET_WITHDRAWER,
            requestFinalizer: actors.ops.REQUEST_FINALIZER,
            withdrawalFee: 500, // 0.05%
            feeReceiver: actors.admin.FEE_RECEIVER
        });
        ynETHWithdrawalQueueManager.initialize(_managerInit);

        vm.startPrank(actors.admin.ADMIN);
        yneth.grantRole(yneth.BURNER_ROLE(), address(ynETHWithdrawalQueueManager));
        vm.stopPrank();

        // Initialize V2 of StakingNodesManager
        vm.prank(actors.admin.ADMIN);
        stakingNodesManager.initializeV2(
            StakingNodesManager.Init2({
                redemptionAssetsVault: ynETHRedemptionAssetsVaultInstance,
                withdrawalManager: actors.ops.WITHDRAWAL_MANAGER,
                stakingNodesWithdrawer: actors.ops.STAKING_NODES_WITHDRAWER
            })
        );
    }

    function setupInitialization() internal {

        // Initialize V3 of StakingNodesManager with new implementation
        stakingNodesManager.initializeV3(rewardsCoordinator);
        vm.prank(actors.admin.STAKING_ADMIN);
        stakingNodesManager.upgradeStakingNodeImplementation(address(stakingNodeImplementation));
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  UTILITY  -----------------------------------------
    //--------------------------------------------------------------------------------------

    function createValidators(uint256[] memory nodeIds, uint256 count) public returns (uint40[] memory) {
        uint40[] memory validatorIndices = new uint40[](count * nodeIds.length);
        uint256 index = 0;

        for (uint256 j = 0; j < nodeIds.length; j++) {
            bytes memory withdrawalCredentials = stakingNodesManager.getWithdrawalCredentials(nodeIds[j]);

            for (uint256 i = 0; i < count; i++) {
                validatorIndices[index] = beaconChain.newValidator{value: 32 ether}(withdrawalCredentials);
                index++;
            }
        }
        return validatorIndices;
    }

    function registerValidators(uint256[] memory validatorNodeIds) public {
        IStakingNodesManager.ValidatorData[] memory validatorData = new IStakingNodesManager.ValidatorData[](validatorNodeIds.length);
        
        for (uint256 i = 0; i < validatorNodeIds.length; i++) {
            bytes memory publicKey = abi.encodePacked(uint256(i));
            publicKey = bytes.concat(publicKey, new bytes(ZERO_PUBLIC_KEY.length - publicKey.length));
            validatorData[i] = IStakingNodesManager.ValidatorData({
                publicKey: publicKey,
                signature: ZERO_SIGNATURE,
                nodeId: validatorNodeIds[i],
                depositDataRoot: bytes32(0)
            });
        }

        for (uint256 i = 0; i < validatorData.length; i++) {
            uint256 amount = 32 ether;
            bytes memory withdrawalCredentials = stakingNodesManager.getWithdrawalCredentials(validatorData[i].nodeId);
            bytes32 depositDataRoot = stakingNodesManager.generateDepositRoot(validatorData[i].publicKey, validatorData[i].signature, withdrawalCredentials, amount);
            validatorData[i].depositDataRoot = depositDataRoot;
        }
        
        vm.prank(actors.ops.VALIDATOR_MANAGER);
        stakingNodesManager.registerValidators(validatorData);
    }
}
