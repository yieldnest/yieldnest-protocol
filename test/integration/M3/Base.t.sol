// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {TransparentUpgradeableProxy, ITransparentUpgradeableProxy} from "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";

import {IStrategy} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IEigenPodManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IEigenPodManager.sol";
import {IDelegationManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {BeaconChainMock, BeaconChainProofs, CheckpointProofs, CredentialProofs, EigenPodManager} from "lib/eigenlayer-contracts/src/test/integration/mocks/BeaconChainMock.t.sol";

import {Utils} from "../../../script/Utils.sol";
import {ContractAddresses} from "../../../script/ContractAddresses.sol";
import {ActorAddresses} from "../../../script/Actors.sol";

import {IDepositContract} from "../../../src/external/ethereum/IDepositContract.sol";

import {IRedeemableAsset} from "../../../src/interfaces/IRedeemableAsset.sol";
import {IRedemptionAssetsVault} from "../../../src/interfaces/IRedemptionAssetsVault.sol";
import {IynETH} from "../../../src/interfaces/IynETH.sol";

import {ynETH} from "../../../src/ynETH.sol";
import {StakingNodesManager, IStakingNodesManager} from "../../../src/StakingNodesManager.sol";
import {StakingNode} from "../../../src/StakingNode.sol";
import {RewardsReceiver} from "../../../src/RewardsReceiver.sol";
import {RewardsDistributor} from "../../../src/RewardsDistributor.sol";
import {StakingNode} from "../../../src/StakingNode.sol";
import {WithdrawalQueueManager} from "../../../src/WithdrawalQueueManager.sol";
import {ynETHRedemptionAssetsVault} from "../../../src/ynETHRedemptionAssetsVault.sol";
import {IStakingNode} from "../../../src/interfaces/IStakingNodesManager.sol";
import {PlaceholderStakingNodesManager} from "./PlaceholderStakingNodesManager.sol";
import {WithdrawalsProcessor} from "src/WithdrawalsProcessor.sol";



import "forge-std/console.sol";
import "forge-std/Test.sol";

contract Base is Test, Utils {

    bytes public constant ZERO_SIGNATURE = hex"000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";
    bytes constant ZERO_PUBLIC_KEY = hex"000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"; 

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

    // EigenLayer
    IEigenPodManager public eigenPodManager;
    IDelegationManager public delegationManager;

    // Mock Contracts to deploy
    BeaconChainMock public beaconChain;

    // Ethereum
    IDepositContract public depositContractEth2;

    uint64 public constant GENESIS_TIME_LOCAL = 1 hours * 12;

    function setUp() public virtual {
        assignContracts();
        upgradeYnToM3();
    }

    function assignContracts() internal {
        contractAddresses = new ContractAddresses();
        chainAddresses = contractAddresses.getChainAddresses(block.chainid);
        actorAddresses = new ActorAddresses();
        actors = actorAddresses.getActors(block.chainid);

        // assign YieldNest addresses
        {
            yneth = ynETH(payable(chainAddresses.yn.YNETH_ADDRESS));
            stakingNodesManager = StakingNodesManager(payable(chainAddresses.yn.STAKING_NODES_MANAGER_ADDRESS));
            rewardsDistributor = RewardsDistributor(payable(chainAddresses.yn.REWARDS_DISTRIBUTOR_ADDRESS));
            executionLayerReceiver = RewardsReceiver(payable(chainAddresses.yn.EXECUTION_LAYER_RECEIVER_ADDRESS));
            consensusLayerReceiver = RewardsReceiver(payable(chainAddresses.yn.CONSENSUS_LAYER_RECEIVER_ADDRESS));
            ynETHWithdrawalQueueManager = WithdrawalQueueManager(payable(chainAddresses.yn.WITHDRAWAL_QUEUE_MANAGER_ADDRESS));
            ynETHRedemptionAssetsVaultInstance = ynETHRedemptionAssetsVault(payable(chainAddresses.yn.YNETH_REDEMPTION_ASSETS_VAULT_ADDRESS));
        }

        // assign Ethereum addresses
        {
            depositContractEth2 = IDepositContract(chainAddresses.ethereum.DEPOSIT_2_ADDRESS);
        }

        // assign Eigenlayer addresses
        {
            eigenPodManager = IEigenPodManager(chainAddresses.eigenlayer.EIGENPOD_MANAGER_ADDRESS);
            delegationManager = IDelegationManager(chainAddresses.eigenlayer.DELEGATION_MANAGER_ADDRESS);
        }

        // deploy EigenLayer mocks
        {
            vm.warp(GENESIS_TIME_LOCAL);
            beaconChain = new BeaconChainMock(EigenPodManager(address(eigenPodManager)), GENESIS_TIME_LOCAL);
        }
    }

    function upgradeYnToM3() internal {
        if (block.chainid == 17000) {
            // Nothing to do, only mainnet left to upgrade
            deployWithdrawalsProcessor();
            return;
        }


        uint256 totalAssets = yneth.totalAssets();
        uint256 totalSupply = yneth.totalSupply();

        // Capture the upgrade state before making any changes
        UpgradeState memory preUpgradeState = captureUpgradeState();

        preUpgradeState.stakingNodesManagerTotalDeposited = 0;
        for (uint256 i = 0; i < preUpgradeState.stakingNodeBalances.length; i++) {
            preUpgradeState.stakingNodesManagerTotalDeposited += preUpgradeState.stakingNodeBalances[i];
        }

        /*
         ███████╗████████╗ █████╗  ██████╗ ███████╗     ██╗
         ██╔════╝╚══██╔══╝██╔══██╗██╔════╝ ██╔════╝    ███║
         ███████╗   ██║   ███████║██║  ███╗█████╗      ╚██║
         ╚════██║   ██║   ██╔══██║██║   ██║██╔══╝       ██║
         ███████║   ██║   ██║  ██║╚██████╔╝███████╗     ██║
         ╚══════╝   ╚═╝   ╚═╝  ╚═╝ ╚═════╝ ╚══════╝     ╚═╝
         Stage 1 - ATOMIC upgrade existing contracts
        */


        // upgrade stakingNodesManager
        {
            /*
                ██████╗  █████╗ ███╗   ██╗ ██████╗ ███████╗██████╗ 
                ██╔══██╗██╔══██╗████╗  ██║██╔════╝ ██╔════╝██╔══██╗
                ██║  ██║███████║██╔██╗ ██║██║  ███╗█████╗  ██████╔╝
                ██║  ██║██╔══██║██║╚██╗██║██║   ██║██╔══╝  ██╔══██╗
                ██████╔╝██║  ██║██║ ╚████║╚██████╔╝███████╗██║  ██║
                ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═══╝ ╚═════╝ ╚══════╝╚═╝  ╚═╝
            */

            address stakinNodesManagerImplementation = getStakingNodesManagerImplementation(preUpgradeState);

            vm.startPrank(actors.admin.PROXY_ADMIN_OWNER);
            ProxyAdmin(
                getTransparentUpgradeableProxyAdminAddress(address(stakingNodesManager))
            ).upgradeAndCall(
                ITransparentUpgradeableProxy(address(stakingNodesManager)),
                address(stakinNodesManagerImplementation),
                ""
            );
            vm.stopPrank();
        }

        runUpgradeIntegrityInvariants(preUpgradeState);

        // upgrade ynETH
        {
            vm.startPrank(actors.admin.PROXY_ADMIN_OWNER);
            ProxyAdmin(
                getTransparentUpgradeableProxyAdminAddress(address(yneth))
            ).upgradeAndCall(
                ITransparentUpgradeableProxy(address(yneth)),
                address(new ynETH()),
                ""
            );
            vm.stopPrank();
        }

        runUpgradeIntegrityInvariants(preUpgradeState);

        // upgrade StakingNodeImplementation
        {
            stakingNodeImplementation = new StakingNode();
            vm.prank(actors.admin.STAKING_ADMIN);
            stakingNodesManager.upgradeStakingNodeImplementation(address(stakingNodeImplementation));
        }

        {
            runUpgradeIntegrityInvariants(preUpgradeState);
            // Assert that the redemptionAssetsVault is initially set to the zero address in the StakingNodesManager
            assertEq(address(stakingNodesManager.redemptionAssetsVault()), address(0), "redemptionAssetsVault should initially be set to the zero address in StakingNodesManager");
            // Assert that previewRedeem returns a non-zero value
            uint256 previewRedeemAmount = yneth.previewRedeem(1 ether);
            assertGt(previewRedeemAmount, 0, "previewRedeem should return a non-zero value");
        }

        logStakingNodeBalancesAndShares(preUpgradeState);


        //  ███████╗████████╗ █████╗  ██████╗ ███████╗    ██████╗ 
        //  ██╔════╝╚══██╔══╝██╔══██╗██╔════╝ ██╔════╝    ╚════██╗
        //  ███████╗   ██║   ███████║██║  ███╗█████╗       █████╔╝
        //  ╚════██║   ██║   ██╔══██║██║   ██║██╔══╝      ██╔═══╝ 
        //  ███████║   ██║   ██║  ██║╚██████╔╝███████╗    ███████╗
        // STAGE 2: NEW CONTRACTS - Deploy and initialize new contracts

        // deploy ynETHRedemptionAssetsVault
        {
            TransparentUpgradeableProxy _proxy = new TransparentUpgradeableProxy(
                address(new ynETHRedemptionAssetsVault()),
                actors.admin.PROXY_ADMIN_OWNER,
                ""
            );
            ynETHRedemptionAssetsVaultInstance = ynETHRedemptionAssetsVault(payable(address(_proxy)));
        }

        // deploy WithdrawalQueueManager
        {
            TransparentUpgradeableProxy _proxy = new TransparentUpgradeableProxy(
                address(new WithdrawalQueueManager()),
                actors.admin.PROXY_ADMIN_OWNER,
                ""
            );
            ynETHWithdrawalQueueManager = WithdrawalQueueManager(address(_proxy));
        }

        // initialize ynETHRedemptionAssetsVault
        {
            ynETHRedemptionAssetsVault.Init memory _init = ynETHRedemptionAssetsVault.Init({
                admin: actors.admin.PROXY_ADMIN_OWNER,
                redeemer: address(ynETHWithdrawalQueueManager),
                ynETH: IynETH(address(yneth))
            });
            ynETHRedemptionAssetsVaultInstance.initialize(_init);
        }

        runUpgradeIntegrityInvariants(preUpgradeState);

        // initialize WithdrawalQueueManager
        {
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
        }

        runUpgradeIntegrityInvariants(preUpgradeState);

        // End of STAGE 2 - Deploy new contracts

        // ---------------------------------------------------------------
        // STAGE 3 - Initialize StakingNodesManager with Init2 and add BURNER_ROLE for WithdrawalQueueManager
        // ---------------------------------------------------------------
        {
            StakingNodesManager.Init2 memory initParams = StakingNodesManager.Init2({
                redemptionAssetsVault: ynETHRedemptionAssetsVaultInstance,
                withdrawalManager: actors.ops.WITHDRAWAL_MANAGER,
                stakingNodesWithdrawer: actors.ops.STAKING_NODES_WITHDRAWER
            });
            
            vm.prank(actors.admin.ADMIN);
            stakingNodesManager.initializeV2(initParams);
        }

        runUpgradeIntegrityInvariants(preUpgradeState);

        // grant burner role
        {
            vm.startPrank(actors.admin.STAKING_ADMIN);
            yneth.grantRole(yneth.BURNER_ROLE(), address(ynETHWithdrawalQueueManager));
            vm.stopPrank();
        }

        deployWithdrawalsProcessor();

        runUpgradeIntegrityInvariants(preUpgradeState);
    }

    function deployWithdrawalsProcessor() internal {
        // Deploy WithdrawalsProcessor
        // Deploy the implementation contract
        WithdrawalsProcessor withdrawalsProcessorImplementation = new WithdrawalsProcessor();

        // Prepare the initialization data
        bytes memory initData = abi.encodeWithSelector(
            WithdrawalsProcessor.initialize.selector,
            IStakingNodesManager(address(stakingNodesManager)),
            actors.admin.ADMIN,
            actors.ops.WITHDRAWAL_MANAGER
        );

        // Deploy the proxy
        TransparentUpgradeableProxy withdrawalsProcessorProxy = new TransparentUpgradeableProxy(
            address(withdrawalsProcessorImplementation),
            actors.admin.PROXY_ADMIN_OWNER,
            initData
        );

        withdrawalsProcessor = WithdrawalsProcessor(address(withdrawalsProcessorProxy));

        // Grant WITHDRAWAL_MANAGER_ROLE to WithdrawalsProcessor
        vm.startPrank(actors.admin.ADMIN);
        stakingNodesManager.grantRole(stakingNodesManager.WITHDRAWAL_MANAGER_ROLE(), address(withdrawalsProcessor));
        stakingNodesManager.grantRole(stakingNodesManager.STAKING_NODES_WITHDRAWER_ROLE(), address(withdrawalsProcessor));
        vm.stopPrank();
    }

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

    function runSystemStateInvariants(
        uint256 previousTotalAssets,
        uint256 previousTotalSupply,
        uint256[] memory previousStakingNodeBalances
    ) public {  
        assertEq(yneth.totalAssets(), previousTotalAssets, "Total assets integrity check failed");
        assertEq(yneth.totalSupply(), previousTotalSupply, "Share mint integrity check failed");

        assertEq(
            previousStakingNodeBalances.length,
            stakingNodesManager.nodesLength(),
            "Number of staking nodes changed after upgrade"
        );
        for (uint i = 0; i < previousStakingNodeBalances.length; i++) {
            IStakingNode stakingNodeInstance = stakingNodesManager.nodes(i);
            uint256 currentStakingNodeBalance = stakingNodeInstance.getETHBalance();
            assertEq(
                currentStakingNodeBalance, previousStakingNodeBalances[i],
                string.concat("Staking node balance integrity check failed for node ID: ", vm.toString(i))
            );
        }
	}

    struct UpgradeState {
        uint256 totalAssets;
        uint256 totalSupply;
        uint256[] stakingNodeBalances;
        uint256 stakingNodesManagerTotalDeposited;
        uint256 previewDepositAmount;
        address ynETHStakingNodesManager;
        address ynETHRewardsDistributor;
        address stakingNodesManagerYnETH;
        address stakingNodesManagerRewardsDistributor;
        address rewardsDistributorYnETH;
    }

    function captureUpgradeState() public view returns (UpgradeState memory) {
        return UpgradeState({
            totalAssets: yneth.totalAssets(),
            totalSupply: yneth.totalSupply(),
            stakingNodesManagerTotalDeposited: 0, // temp value since N/A in previous deployment
            stakingNodeBalances: getAllStakingNodeBalances(),
            previewDepositAmount: yneth.previewDeposit(1 ether),
            ynETHStakingNodesManager: address(yneth.stakingNodesManager()),
            ynETHRewardsDistributor: address(yneth.rewardsDistributor()),
            stakingNodesManagerYnETH: address(stakingNodesManager.ynETH()),
            stakingNodesManagerRewardsDistributor: address(stakingNodesManager.rewardsDistributor()),
            rewardsDistributorYnETH: address(rewardsDistributor.ynETH())
        });
    }

    function runUpgradeIntegrityInvariants(UpgradeState memory preUpgradeState) public {
        // Check system state invariants
        runSystemStateInvariants(
            preUpgradeState.totalAssets,
            preUpgradeState.totalSupply,
            preUpgradeState.stakingNodeBalances
        );

        assertEq(
            stakingNodesManager.totalDeposited(),
            preUpgradeState.stakingNodesManagerTotalDeposited,
            "StakingNodesManager totalDeposited changed after upgrade"
        );

        // Check previewDeposit stays the same
        assertEq(
            yneth.previewDeposit(1 ether),
            preUpgradeState.previewDepositAmount,
            "previewDeposit amount changed after upgrade"
        );

        // Check ynETH dependencies stay the same
        assertEq(
            address(yneth.stakingNodesManager()),
            preUpgradeState.ynETHStakingNodesManager,
            "ynETH stakingNodesManager changed after upgrade"
        );
        assertEq(
            address(yneth.rewardsDistributor()),
            preUpgradeState.ynETHRewardsDistributor,
            "ynETH rewardsDistributor changed after upgrade"
        );

        // Check StakingNodesManager dependencies stay the same
        assertEq(
            address(stakingNodesManager.ynETH()),
            preUpgradeState.stakingNodesManagerYnETH,
            "StakingNodesManager ynETH changed after upgrade"
        );
        assertEq(
            address(stakingNodesManager.rewardsDistributor()),
            preUpgradeState.stakingNodesManagerRewardsDistributor,
            "StakingNodesManager rewardsDistributor changed after upgrade"
        );

        // Check RewardsDistributor dependencies stay the same
        assertEq(
            address(rewardsDistributor.ynETH()),
            preUpgradeState.rewardsDistributorYnETH,
            "RewardsDistributor ynETH changed after upgrade"
        );
    }

    function getAllStakingNodeBalances() public view returns (uint256[] memory) {
        uint256[] memory balances = new uint256[](stakingNodesManager.nodesLength());
        for (uint256 i = 0; i < stakingNodesManager.nodesLength(); i++) {
            IStakingNode stakingNode = stakingNodesManager.nodes(i);
            balances[i] = stakingNode.getETHBalance();
        }
        return balances;
    }

    function logStakingNodeBalancesAndShares(UpgradeState memory preUpgradeState) internal {
        // Print StakingNode balance before upgrade
        console.log("StakingNode balance before upgrade:");
        for (uint256 i = 0; i < preUpgradeState.stakingNodeBalances.length; i++) {
            console.log("Node", i, ":", preUpgradeState.stakingNodeBalances[i]);
        }

        // Print current StakingNode balance after upgrade
        console.log("StakingNode balance after upgrade:");
        for (uint256 i = 0; i < stakingNodesManager.nodesLength(); i++) {
            IStakingNode stakingNode = stakingNodesManager.nodes(i);
            console.log("Node", i, ":", stakingNode.getETHBalance());
        }

        // Log pod shares for each eigenpod of each node
        console.log("EigenPod shares for each StakingNode:");
        for (uint256 i = 0; i < stakingNodesManager.nodesLength(); i++) {
            IStakingNode stakingNode = stakingNodesManager.nodes(i);
            address eigenPodAddress = address(stakingNode.eigenPod());
            uint256 podShares = uint256(IEigenPodManager(chainAddresses.eigenlayer.EIGENPOD_MANAGER_ADDRESS).podOwnerShares(address(stakingNode)));
            console.log("Node", i, "Shares:", podShares);
        }
    }

    function getStakingNodesManagerImplementation(UpgradeState memory preUpgradeState) internal returns (address stakinNodesManagerImplementation) {
        if (block.chainid == 1) { // only on MAINNET

            /*
                ██████╗  █████╗ ███╗   ██╗ ██████╗ ███████╗██████╗ 
                ██╔══██╗██╔══██╗████╗  ██║██╔════╝ ██╔════╝██╔══██╗
                ██║  ██║███████║██╔██╗ ██║██║  ███╗█████╗  ██████╔╝
                ██║  ██║██╔══██║██║╚██╗██║██║   ██║██╔══╝  ██╔══██╗
                ██████╔╝██║  ██║██║ ╚████║╚██████╔╝███████╗██║  ██║
                ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═══╝ ╚═════╝ ╚══════╝╚═╝  ╚═╝
            */

            // WARNING: This code is for testing purposes only and MUST be removed before deploying to mainnet.
            // It uses a placeholder implementation that doesn't reflect the actual mainnet behavior.
            // Keeping this in production could lead to severe security vulnerabilities and incorrect contract behavior.
            // This logic auto-adjust for unverifiedStakedETH based on the the difference between podOwnerShares and pre-deposit balance.

            // Compute deltas array
            uint256[] memory deltas = new uint256[](stakingNodesManager.nodesLength());
            for (uint256 i = 0; i < stakingNodesManager.nodesLength(); i++) {
                IStakingNode stakingNode = stakingNodesManager.nodes(i);
                uint256 podShares = uint256(IEigenPodManager(chainAddresses.eigenlayer.EIGENPOD_MANAGER_ADDRESS).podOwnerShares(address(stakingNode)));
                deltas[i] = preUpgradeState.stakingNodeBalances[i] - podShares;
                // Revert if delta is bigger than 32 ether
                require(deltas[i] <= 32 ether, "Delta exceeds 32 ether limit");
            }

            // Deploy PlaceholderStakingNodesManager
            PlaceholderStakingNodesManager placeholderStakingNodesManager = new PlaceholderStakingNodesManager(deltas);
            stakinNodesManagerImplementation = address(placeholderStakingNodesManager);
        } else {
            stakinNodesManagerImplementation = address(new StakingNodesManager());
        }
    }
}
