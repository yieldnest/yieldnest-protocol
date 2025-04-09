// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {TransparentUpgradeableProxy, ITransparentUpgradeableProxy} from "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {TimelockController} from "lib/openzeppelin-contracts/contracts/governance/TimelockController.sol";

import {IStrategy} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IEigenPodManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IEigenPodManager.sol";
import {IDelegationManager, IDelegationManagerTypes} from "lib/eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {BeaconChainMock, BeaconChainProofs, CheckpointProofs, CredentialProofs, EigenPodManager} from "lib/eigenlayer-contracts/src/test/integration/mocks/BeaconChainMock.t.sol";
import {Utils} from "script/Utils.sol";
import {ContractAddresses} from "script/ContractAddresses.sol";
import {ActorAddresses} from "script/Actors.sol";

import {IDepositContract} from "src/external/ethereum/IDepositContract.sol";

import {IRedeemableAsset} from "src/interfaces/IRedeemableAsset.sol";
import {IRedemptionAssetsVault} from "src/interfaces/IRedemptionAssetsVault.sol";
import {IynETH} from "src/interfaces/IynETH.sol";

import {ynETH} from "src/ynETH.sol";
import {StakingNodesManager, IStakingNodesManager} from "src/StakingNodesManager.sol";
import {StakingNode} from "src/StakingNode.sol";
import {RewardsReceiver} from "src/RewardsReceiver.sol";
import {RewardsDistributor} from "src/RewardsDistributor.sol";
import {StakingNode} from "src/StakingNode.sol";
import {HoleskyStakingNodesManager} from "src/HoleskyStakingNodesManager.sol";
import {WithdrawalQueueManager} from "src/WithdrawalQueueManager.sol";
import {ynETHRedemptionAssetsVault} from "src/ynETHRedemptionAssetsVault.sol";
import {IStakingNode} from "src/interfaces/IStakingNodesManager.sol";
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
    ContractAddresses.ChainIds public chainIds;

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

    address payable public constant EIGENLAYER_TIMELOCK = payable(0xC06Fd4F821eaC1fF1ae8067b36342899b57BAa2d);
    address public constant EIGENLAYER_MULTISIG = 0x461854d84Ee845F905e0eCf6C288DDEEb4A9533F;

    function setUp() public virtual {
        assignContracts();
        
        // Roles are granted here just for testing purposes.
        // On Mainnet only WithdrawalsProcessor has permission to run this, but the system is designed to run
        // them separately as well if needed.
        // Grant roles on StakingNodesManager for mainnet only
        if (block.chainid == chainIds.mainnet) { // Mainnet chain ID
            vm.startPrank(actors.admin.ADMIN);
            stakingNodesManager.grantRole(stakingNodesManager.WITHDRAWAL_MANAGER_ROLE(), actors.ops.WITHDRAWAL_MANAGER);
            stakingNodesManager.grantRole(stakingNodesManager.STAKING_NODES_WITHDRAWER_ROLE(), actors.ops.STAKING_NODES_WITHDRAWER);
            vm.stopPrank();
        }

        // for(uint256 i = 0; i < stakingNodesManager.nodesLength(); i++) {
        //     vm.startPrank(actors.admin.STAKING_NODES_DELEGATOR);
        //     stakingNodesManager.nodes(i).syncQueuedShares();
        //     vm.stopPrank();
        // }
        upgradeStakingNodesManagerAndStakingNode();
        upgradeWithdrawalsProcessor();
        stakingNodesManager.updateTotalETHStaked();
    }

    function assignContracts() internal {
        contractAddresses = new ContractAddresses();
        chainAddresses = contractAddresses.getChainAddresses(block.chainid);
        actorAddresses = new ActorAddresses();
        actors = actorAddresses.getActors(block.chainid);
        chainIds = contractAddresses.getChainIds();

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

        // execute scheduled transactions for slashing upgrades
        {
            bytes memory payload = hex"6a76120200000000000000000000000040a2accbd92bca938b02010e17a5b8929b49130d000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001400000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000ea00000000000000000000000000000000000000000000000000000000000000d248d80ff0a00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000cc6008b9566ada63b64d1e1dcf1418b43fd1433b724440000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004499a88ec4000000000000000000000000135dda560e946695d6f155dacafc6f1f25c1f5af000000000000000000000000a396d855d70e1a1ec1a0199adb9845096683b6a2008b9566ada63b64d1e1dcf1418b43fd1433b724440000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004499a88ec400000000000000000000000039053d51b77dc0d36036fc1fcc8cb819df8ef37a000000000000000000000000a75112d1df37fa53a431525cd47a7d7facea7e73008b9566ada63b64d1e1dcf1418b43fd1433b724440000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004499a88ec40000000000000000000000007750d328b314effa365a0402ccfd489b80b0adda000000000000000000000000a505c0116ad65071f0130061f94745b7853220ab008b9566ada63b64d1e1dcf1418b43fd1433b724440000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004499a88ec4000000000000000000000000858646372cc42e1a627fce94aa7a7033e7cf075a000000000000000000000000ba4b2b8a076851a3044882493c2e36503d50b925005a2a4f2f3c18f09179b6703e63d9edd165909073000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000243659cfe6000000000000000000000000b132a8dad03a507f1b9d2f467a4936df2161c63e008b9566ada63b64d1e1dcf1418b43fd1433b724440000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004499a88ec400000000000000000000000091e677b07f7af907ec9a428aafa9fc14a0d3a3380000000000000000000000009801266cbbbe1e94bb9daf7de8d61528f49cec77008b9566ada63b64d1e1dcf1418b43fd1433b724440000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004499a88ec4000000000000000000000000acb55c530acdb2849e6d4f36992cd8c9d50ed8f700000000000000000000000090b074ddd680bd06c72e28b09231a0f848205729000ed6703c298d28ae0878d1b28e88ca87f9662fe9000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000243659cfe60000000000000000000000000ec17ef9c00f360db28ca8008684a4796b11e456008b9566ada63b64d1e1dcf1418b43fd1433b724440000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004499a88ec40000000000000000000000005e4c39ad7a3e881585e383db9827eb4811f6f6470000000000000000000000001b97d8f963179c0e17e5f3d85cdfd9a31a49bc66008b9566ada63b64d1e1dcf1418b43fd1433b724440000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004499a88ec400000000000000000000000093c4b944d05dfe6df7645a86cd2206016c51564d000000000000000000000000afda870d4a94b9444f9f22a0e61806178b6bf178008b9566ada63b64d1e1dcf1418b43fd1433b724440000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004499a88ec40000000000000000000000001bee69b7dfffa4e2d53c2a2df135c388ad25dcd2000000000000000000000000afda870d4a94b9444f9f22a0e61806178b6bf178008b9566ada63b64d1e1dcf1418b43fd1433b724440000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004499a88ec400000000000000000000000054945180db7943c0ed0fee7edab2bd24620256bc000000000000000000000000afda870d4a94b9444f9f22a0e61806178b6bf178008b9566ada63b64d1e1dcf1418b43fd1433b724440000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004499a88ec40000000000000000000000009d7ed45ee2e8fc5482fa2428f15c971e6369011d000000000000000000000000afda870d4a94b9444f9f22a0e61806178b6bf178008b9566ada63b64d1e1dcf1418b43fd1433b724440000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004499a88ec400000000000000000000000013760f50a9d7377e4f20cb8cf9e4c26586c658ff000000000000000000000000afda870d4a94b9444f9f22a0e61806178b6bf178008b9566ada63b64d1e1dcf1418b43fd1433b724440000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004499a88ec4000000000000000000000000a4c637e0f704745d182e4d38cab7e7485321d059000000000000000000000000afda870d4a94b9444f9f22a0e61806178b6bf178008b9566ada63b64d1e1dcf1418b43fd1433b724440000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004499a88ec400000000000000000000000057ba429517c3473b6d34ca9acd56c0e735b94c02000000000000000000000000afda870d4a94b9444f9f22a0e61806178b6bf178008b9566ada63b64d1e1dcf1418b43fd1433b724440000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004499a88ec40000000000000000000000000fe4f44bee93503346a3ac9ee5a26b130a5796d6000000000000000000000000afda870d4a94b9444f9f22a0e61806178b6bf178008b9566ada63b64d1e1dcf1418b43fd1433b724440000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004499a88ec40000000000000000000000007ca911e83dabf90c90dd3de5411a10f1a6112184000000000000000000000000afda870d4a94b9444f9f22a0e61806178b6bf178008b9566ada63b64d1e1dcf1418b43fd1433b724440000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004499a88ec40000000000000000000000008ca7a5d6f3acd3a7a8bc468a8cd0fb14b6bd28b6000000000000000000000000afda870d4a94b9444f9f22a0e61806178b6bf178008b9566ada63b64d1e1dcf1418b43fd1433b724440000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004499a88ec4000000000000000000000000ae60d8180437b5c34bb956822ac2710972584473000000000000000000000000afda870d4a94b9444f9f22a0e61806178b6bf178008b9566ada63b64d1e1dcf1418b43fd1433b724440000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004499a88ec4000000000000000000000000298afb19a105d59e74658c4c334ff360bade6dd2000000000000000000000000afda870d4a94b9444f9f22a0e61806178b6bf1780091e677b07f7af907ec9a428aafa9fc14a0d3a33800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000024fabc1cbc00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000041000000000000000000000000c06fd4f821eac1ff1ae8067b36342899b57baa2d00000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000";
            vm.warp(block.timestamp + 11 days);
            vm.prank(EIGENLAYER_MULTISIG);
            TimelockController(EIGENLAYER_TIMELOCK).execute(0x369e6F597e22EaB55fFb173C6d9cD234BD699111, 0, payload, bytes32(0), bytes32(0));
        }

        // deploy EigenLayer mocks
        {
            vm.warp(GENESIS_TIME_LOCAL);
            beaconChain = new BeaconChainMock(EigenPodManager(address(eigenPodManager)), GENESIS_TIME_LOCAL);
        }
    }

    function upgradeStakingNodesManagerAndStakingNode() internal virtual {


        // Upgrade StakingNodesManager
        // bytes memory initializeV3Data = abi.encodeWithSelector(stakingNodesManager.initializeV3.selector, chainAddresses.eigenlayer.REWARDS_COORDINATOR_ADDRESS);

        address newStakingNodesManagerImpl = address(new StakingNodesManager());
        // commented here because totalAssets is broken in Holesky
        // uint256 totalAssetsBefore = yneth.totalAssets();

        vm.prank(actors.admin.PROXY_ADMIN_OWNER);
        ProxyAdmin(getTransparentUpgradeableProxyAdminAddress(address(stakingNodesManager))).upgradeAndCall(
            ITransparentUpgradeableProxy(address(stakingNodesManager)),
            newStakingNodesManagerImpl,
            ""
        );

        assertEq(address(stakingNodesManager.rewardsCoordinator()), chainAddresses.eigenlayer.REWARDS_COORDINATOR_ADDRESS, "rewardsCoordinator not set correctly after upgrade");

        // Upgrade StakingNode implementation
        address newStakingNodeImpl = address(new StakingNode());


        // Register new implementation
        vm.prank(actors.admin.STAKING_ADMIN);
        stakingNodesManager.upgradeStakingNodeImplementation(newStakingNodeImpl);

        // assertEq(yneth.totalAssets(), totalAssetsBefore, "totalAssets of ynETH changed after upgrade");
    }

    function upgradeWithdrawalsProcessor() internal {

        address newWithdrawalsProcessorImpl = address(new WithdrawalsProcessor());

        vm.startPrank(actors.admin.PROXY_ADMIN_OWNER);
        ProxyAdmin(getTransparentUpgradeableProxyAdminAddress(address(withdrawalsProcessor))).upgradeAndCall(
            ITransparentUpgradeableProxy(address(withdrawalsProcessor)),
            newWithdrawalsProcessorImpl,
            ""
        );
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

         for (uint i = 0; i < previousStakingNodeBalances.length; i++) {
            IStakingNode stakingNodeInstance = stakingNodesManager.nodes(i);
            vm.prank(actors.admin.STAKING_NODES_DELEGATOR);
            stakingNodeInstance.synchronize();

            uint256 currentStakingNodeBalance = stakingNodeInstance.getETHBalance();
            assertEq(
                currentStakingNodeBalance, previousStakingNodeBalances[i],
                string.concat("Staking node balance integrity check failed for node ID: ", vm.toString(i))
            );
        }

        stakingNodesManager.updateTotalETHStaked();
        assertEq(yneth.totalAssets(), previousTotalAssets, "Total assets integrity check failed");
        assertEq(yneth.totalSupply(), previousTotalSupply, "Share mint integrity check failed");

        assertEq(
            previousStakingNodeBalances.length,
            stakingNodesManager.nodesLength(),
            "Number of staking nodes changed after upgrade"
        );
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
            uint256 podShares = uint256(IEigenPodManager(chainAddresses.eigenlayer.EIGENPOD_MANAGER_ADDRESS).podOwnerDepositShares(address(stakingNode)));
            console.log("Node", i, "Shares:", podShares);
        }
    }
}
