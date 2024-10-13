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
        
        // Roles are granted here just for testing purposes.
        // On Mainnet only WithdrawalsProcessor has permission to run this, but the system is designed to run
        // them separately as well if needed.
        // Grant roles on StakingNodesManager for mainnet only
        if (block.chainid == 1) { // Mainnet chain ID
            vm.startPrank(actors.admin.ADMIN);
            stakingNodesManager.grantRole(stakingNodesManager.WITHDRAWAL_MANAGER_ROLE(), actors.ops.WITHDRAWAL_MANAGER);
            stakingNodesManager.grantRole(stakingNodesManager.STAKING_NODES_WITHDRAWER_ROLE(), actors.ops.STAKING_NODES_WITHDRAWER);
            vm.stopPrank();
        }
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
            withdrawalsProcessor = WithdrawalsProcessor(payable(chainAddresses.yn.WITHDRAWALS_PROCESSOR_ADDRESS));
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
}
