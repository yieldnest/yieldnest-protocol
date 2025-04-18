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
import {TestUpgradeUtils} from "test/utils/TestUpgradeUtils.sol";

contract IntegrationBaseTest is Test, Utils, TestUpgradeUtils {

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

    function setUp() public virtual {

        // Setup Addresses
        contractAddresses = new ContractAddresses();
        actorAddresses = new ActorAddresses();
        chainAddresses = contractAddresses.getChainAddresses(block.chainid);
        actors = actorAddresses.getActors(block.chainid);

        // execute scheduled transactions for slashing upgrades
        // TestUpgradeUtils.executeEigenlayerSlashingUpgrade();

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
