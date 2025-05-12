// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {UpgradeableBeacon} from "lib/openzeppelin-contracts/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {IPausable} from "lib/eigenlayer-contracts/src/contracts/interfaces/IPausable.sol";
import {IDelegationManager, IDelegationManagerTypes} from "lib/eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStakingNode} from "src/interfaces/IStakingNode.sol";
import {IStakingNodesManager} from "src/interfaces/IStakingNodesManager.sol";
import {IStrategyManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {StakingNode} from "src/StakingNode.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";
import {ISignatureUtilsMixinTypes} from "lib/eigenlayer-contracts/src/contracts/interfaces/ISignatureUtilsMixin.sol";
import {BytesLib} from "lib/eigenlayer-contracts/src/test/utils/BytesLib.sol";
import {EigenPod} from "lib/eigenlayer-contracts/src/contracts/pods/EigenPod.sol";
import {EigenPodManager} from "lib/eigenlayer-contracts/src/contracts/pods/EigenPodManager.sol";
import {IEigenPodManager, IEigenPodManagerErrors} from "lib/eigenlayer-contracts/src/contracts/interfaces/IEigenPodManager.sol";
import {IEigenPod, IEigenPodErrors} from "lib/eigenlayer-contracts/src/contracts/interfaces/IEigenPod.sol";
import {BeaconChainProofs} from "lib/eigenlayer-contracts/src/contracts/libraries/BeaconChainProofs.sol";
import {IStrategy} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {StakingNodeTestBase, IEigenPodSimplified} from "./StakingNodeTestBase.sol";
import {CheckpointProofs, CredentialProofs} from "lib/eigenlayer-contracts/src/test/integration/mocks/BeaconChainMock.t.sol";
import {IRewardsCoordinator} from "lib/eigenlayer-contracts/src/contracts/interfaces/IRewardsCoordinator.sol";
import {SlashingLib} from "lib/eigenlayer-contracts/src/contracts/libraries/SlashingLib.sol";
import {IAllocationManager, IAllocationManagerTypes} from "lib/eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {OperatorSet} from "lib/eigenlayer-contracts/src/contracts/libraries/OperatorSetLib.sol";
import {AllocationManagerStorage} from "lib/eigenlayer-contracts/src/contracts/core/AllocationManagerStorage.sol";
import {MockAVS} from "test/mocks/MockAVS.sol";

contract StakingNodeEigenPod is StakingNodeTestBase {

    // FIXME: update or delete to accomdate for M3
    function testCreateNodeAndVerifyPodStateIsValid() public {
        uint256 depositAmount = 32 ether;

        address user = vm.addr(156_737);

        // Create a user address and fund it with 1000 ETH
        vm.deal(user, 1000 ether);

        yneth.depositETH{value: depositAmount}(user);

        uint256[] memory nodeIds = createStakingNodes(1);
        IStakingNode stakingNodeInstance = stakingNodesManager.nodes(nodeIds[0]);
        IEigenPod eigenPodInstance = stakingNodeInstance.eigenPod();

        // TODO: double check this is the desired state for a pod.
        // we can't delegate on mainnet at this time so one should be able to farm points without delegating
        assertEq(eigenPodInstance.withdrawableRestakedExecutionLayerGwei(), 0, "Restaked Gwei should be 0");
        // Rewards given to each validator during epoch processing
        assertEq(address(eigenPodManager), address(eigenPodInstance.eigenPodManager()), "EigenPodManager should match");
        assertEq(eigenPodInstance.podOwner(), address(stakingNodeInstance), "Pod owner address does not match");
 
        address payable eigenPodAddress = payable(address(eigenPodInstance));

        // Get initial pod owner shares
        int256 initialpodOwnerDepositShares = eigenPodManager.podOwnerDepositShares(address(stakingNodeInstance));
        // Assert that initial pod owner shares are 0
        assertEq(initialpodOwnerDepositShares, 0, "Initial pod owner shares should be 0");

        // simulate ETH entering the pod by direct transfer as non-beacon chain ETH
        uint256 rewardsSweeped = 1 ether;
        vm.deal(address(this), rewardsSweeped);
        (bool success,) = eigenPodAddress.call{value: rewardsSweeped}("");
        require(success, "Failed to send rewards to EigenPod");

        // Assert that pod owner shares remain the same
        assertEq(initialpodOwnerDepositShares, 0, "Pod owner shares should not change");
    }

    function testCreateNodeVerifyPodStateAndCheckpoint() public {
        uint256 depositAmount = 32 ether;
        address user = vm.addr(156_737);

        // Fund user and deposit ETH
        vm.deal(user, 1000 ether);
        yneth.depositETH{value: depositAmount}(user);

        // Create staking node and get instances
        uint256[] memory nodeIds = createStakingNodes(1);
        IStakingNode stakingNodeInstance = stakingNodesManager.nodes(nodeIds[0]);
        IEigenPod eigenPodInstance = stakingNodeInstance.eigenPod();

        // Simulate ETH entering the pod
        uint256 rewardsSweeped = 1 ether;
        vm.deal(address(this), rewardsSweeped);
        (bool success,) = payable(address(eigenPodInstance)).call{value: rewardsSweeped}("");
        require(success, "Failed to send rewards to EigenPod");

        beaconChain.advanceEpoch_NoRewards();
        // Start checkpoint
        vm.prank(actors.ops.STAKING_NODES_OPERATOR);
        stakingNodeInstance.startCheckpoint(true);
        // Checkpoint ends since no active validators are here

        // Get final pod owner shares
        int256 finalpodOwnerDepositShares = eigenPodManager.podOwnerDepositShares(address(stakingNodeInstance));
        // Assert that the increase matches the swept rewards
        assertEq(uint256(finalpodOwnerDepositShares), rewardsSweeped, "Pod owner shares increase should match swept rewards");
    }

}

contract StakingNodeDelegation is StakingNodeTestBase {

    using stdStorage for StdStorage;
    using BytesLib for bytes;

    address user = vm.addr(156_737);
    uint40[] validatorIndices;

    address operator1 = address(0x9999);
    address operator2 = address(0x8888);
    uint256 nodeId;
    IStakingNode stakingNodeInstance;
    IStakingNode stakingNodeInstance2;

    function setUp() public override {
        super.setUp();

        address[] memory operators = new address[](2);
        operators[0] = operator1;
        operators[1] = operator2;

        for (uint256 i = 0; i < operators.length; i++) {
            vm.prank(operators[i]);
            delegationManager.registerAsOperator(address(0),0, "ipfs://some-ipfs-hash");
        }

        uint256[] memory nodeIds = createStakingNodes(2);
        nodeId = nodeIds[0];
        stakingNodeInstance = stakingNodesManager.nodes(nodeIds[0]);
        stakingNodeInstance2 = stakingNodesManager.nodes(nodeIds[1]);
    }

    function testDelegateFailWhenNotAdmin() public {
        vm.expectRevert();
        stakingNodeInstance.delegate(
            address(this), ISignatureUtilsMixinTypes.SignatureWithExpiry({signature: "", expiry: 0}), bytes32(0)
        );
    }

    function testStakingNodeDelegate() public {
        IDelegationManager delegationManager = stakingNodesManager.delegationManager();
        IPausable pauseDelegationManager = IPausable(address(delegationManager));
        vm.prank(chainAddresses.eigenlayer.DELEGATION_PAUSER_ADDRESS);
        pauseDelegationManager.unpause(0);

        vm.prank(actors.admin.STAKING_NODES_DELEGATOR);
        stakingNodeInstance.delegate(
            operator1, ISignatureUtilsMixinTypes.SignatureWithExpiry({signature: "", expiry: 0}), bytes32(0)
        );

        address delegatedOperator = delegationManager.delegatedTo(address(stakingNodeInstance));
        assertEq(delegatedOperator, operator1, "Delegation is not set to the right operator.");
    }

    function testStakingNodeUndelegate() public {
        IDelegationManager delegationManager = stakingNodesManager.delegationManager();
        IPausable pauseDelegationManager = IPausable(address(delegationManager));

        // Unpause delegation manager to allow delegation
        vm.prank(chainAddresses.eigenlayer.DELEGATION_PAUSER_ADDRESS);
        pauseDelegationManager.unpause(0);

        vm.prank(actors.admin.STAKING_NODES_DELEGATOR);
        stakingNodeInstance.delegate(
            operator1, ISignatureUtilsMixinTypes.SignatureWithExpiry({signature: "", expiry: 0}), bytes32(0)
        );

        // // Attempt to undelegate with the wrong role
        vm.expectRevert();
        stakingNodeInstance.undelegate();

        IStrategyManager strategyManager = stakingNodesManager.strategyManager();
        uint256 stakerStrategyListLength = strategyManager.stakerStrategyListLength(address(stakingNodeInstance));
        assertEq(stakerStrategyListLength, 0, "Staker strategy list length should be 0.");

        // Now actually undelegate with the correct role
        vm.prank(actors.admin.STAKING_NODES_DELEGATOR);
        stakingNodeInstance.undelegate();

        // Verify undelegation
        address delegatedAddress = delegationManager.delegatedTo(address(stakingNodeInstance));
        assertEq(delegatedAddress, address(0), "Delegation should be cleared after undelegation.");
    }

    function testStakingNodeSynchronize() public {
        IDelegationManager delegationManager = stakingNodesManager.delegationManager();

        vm.startPrank(actors.admin.STAKING_NODES_DELEGATOR);
        stakingNodeInstance.delegate(
            operator1, ISignatureUtilsMixinTypes.SignatureWithExpiry({signature: "", expiry: 0}), bytes32(0)
        );
        stakingNodeInstance2.delegate(
            operator1, ISignatureUtilsMixinTypes.SignatureWithExpiry({signature: "", expiry: 0}), bytes32(0)
        );
        vm.stopPrank();

        // Now operator1 undelegate
        vm.startPrank(operator1);
        delegationManager.undelegate(address(stakingNodeInstance));
        delegationManager.undelegate(address(stakingNodeInstance2));
        vm.stopPrank();

        // Verify undelegation
        assertEq(delegationManager.delegatedTo(address(stakingNodeInstance)), address(0), "Delegation should be cleared after undelegation.");
        assertEq(delegationManager.delegatedTo(address(stakingNodeInstance2)), address(0), "Delegation should be cleared after undelegation.");
        // Verify delegatedTo is set to operator1 in the StakingNode contract
        assertEq(
            stakingNodeInstance.delegatedTo(),
            operator1,
            "StakingNode delegatedTo not set to operator1 after undelegation even if state is not synchronized"
        );
        assertEq(
            stakingNodeInstance2.delegatedTo(),
            operator1,
            "StakingNode delegatedTo not set to operator1 after undelegation even if state is not synchronized"
        );
        
        vm.startPrank(actors.admin.STAKING_NODES_DELEGATOR);
        stakingNodeInstance.synchronize();
        stakingNodeInstance2.synchronize();
        vm.stopPrank();

        assertEq(
            stakingNodeInstance.delegatedTo(),
            address(0),
            "StakingNode delegatedTo not correctly set to address(0) after synchronization"
        );
        assertEq(
            stakingNodeInstance2.delegatedTo(),
            address(0),
            "StakingNode delegatedTo not correctly set to address(0) after synchronization"
        );
    }

    function testOperatorUndelegate() public {
        IDelegationManager delegationManager = stakingNodesManager.delegationManager();
        IPausable pauseDelegationManager = IPausable(address(delegationManager));

        // Unpause delegation manager to allow delegation
        vm.prank(chainAddresses.eigenlayer.DELEGATION_PAUSER_ADDRESS);
        pauseDelegationManager.unpause(0);

        vm.prank(actors.admin.STAKING_NODES_DELEGATOR);
        stakingNodeInstance.delegate(
            operator1, ISignatureUtilsMixinTypes.SignatureWithExpiry({signature: "", expiry: 0}), bytes32(0)
        );

        // // Attempt to undelegate with the wrong role
        vm.expectRevert();
        stakingNodeInstance.undelegate();

        IStrategyManager strategyManager = stakingNodesManager.strategyManager();
        uint256 stakerStrategyListLength = strategyManager.stakerStrategyListLength(address(stakingNodeInstance));
        assertEq(stakerStrategyListLength, 0, "Staker strategy list length should be 0.");

        // Now operator1 undelegate
        vm.prank(operator1);
        delegationManager.undelegate(address(stakingNodeInstance));

        // Verify undelegation
        address delegatedAddress = delegationManager.delegatedTo(address(stakingNodeInstance));
        assertEq(delegatedAddress, address(0), "Delegation should be cleared after undelegation.");

        // Verify delegatedTo is set to operator1 in the StakingNode contract
        assertEq(
            stakingNodeInstance.delegatedTo(),
            operator1,
            "StakingNode delegatedTo not set to operator1 after undelegation even if state is not synchronized"
        );

        BeaconChainProofs.StateRootProof memory stateRootProof = BeaconChainProofs.StateRootProof(bytes32(0), bytes(""));
        vm.expectRevert();
        vm.prank(actors.ops.STAKING_NODES_OPERATOR);
        stakingNodeInstance.verifyWithdrawalCredentials(
            0, stateRootProof, new uint40[](0), new bytes[](0), new bytes32[][](0)
        );

        vm.expectRevert();
        vm.prank(actors.admin.STAKING_NODES_DELEGATOR);
        stakingNodeInstance.delegate(
            operator1, ISignatureUtilsMixinTypes.SignatureWithExpiry({signature: "", expiry: 0}), bytes32(0)
        );

        vm.expectRevert();
        vm.prank(actors.admin.STAKING_NODES_DELEGATOR);
        stakingNodeInstance.undelegate();

        vm.expectRevert();
        vm.prank(actors.ops.STAKING_NODES_WITHDRAWER);
        stakingNodeInstance.queueWithdrawals(1);

        vm.expectRevert();
        vm.prank(actors.ops.STAKING_NODES_WITHDRAWER);
        stakingNodeInstance.completeQueuedWithdrawals(new IDelegationManager.Withdrawal[](1));

        vm.expectRevert();
        vm.prank(actors.admin.STAKING_NODES_DELEGATOR);
        stakingNodeInstance.completeQueuedWithdrawalsAsShares(new IDelegationManager.Withdrawal[](1));
    }

    function testDelegateUndelegateAndDelegateAgain() public {
        IDelegationManager delegationManager = stakingNodesManager.delegationManager();

        // Delegate to operator1
        vm.prank(actors.admin.STAKING_NODES_DELEGATOR);
        stakingNodeInstance.delegate(
            operator1, ISignatureUtilsMixinTypes.SignatureWithExpiry({signature: "", expiry: 0}), bytes32(0)
        );

        address delegatedOperator1 = delegationManager.delegatedTo(address(stakingNodeInstance));
        assertEq(delegatedOperator1, operator1, "Delegation is not set to operator1.");

        // Undelegate
        vm.prank(actors.admin.STAKING_NODES_DELEGATOR);
        stakingNodeInstance.undelegate();

        address undelegatedAddress = delegationManager.delegatedTo(address(stakingNodeInstance));
        assertEq(undelegatedAddress, address(0), "Delegation should be cleared after undelegation.");

        // Delegate to operator2
        vm.prank(actors.admin.STAKING_NODES_DELEGATOR);
        stakingNodeInstance.delegate(
            operator2, ISignatureUtilsMixinTypes.SignatureWithExpiry({signature: "", expiry: 0}), bytes32(0)
        );

        address delegatedOperator2 = delegationManager.delegatedTo(address(stakingNodeInstance));
        assertEq(delegatedOperator2, operator2, "Delegation is not set to operator2.");
    }

    function testDelegateUndelegateWithExistingStake() public {
        {
            vm.deal(user, 1000 ether);
            yneth.depositETH{value: 1000 ether}(user);

            // Call createValidators with the nodeIds array and validatorCount
            validatorIndices = createValidators(repeat(nodeId, 1), 1);
            beaconChain.advanceEpoch_NoRewards();
            registerValidators(repeat(nodeId, 1));
            _verifyWithdrawalCredentials(nodeId, validatorIndices[0]);
        }

        IDelegationManager delegationManager = stakingNodesManager.delegationManager();

        // Delegate to operator1
        vm.prank(actors.admin.STAKING_NODES_DELEGATOR);
        stakingNodeInstance.delegate(
            operator1, ISignatureUtilsMixinTypes.SignatureWithExpiry({signature: "", expiry: 0}), bytes32(0)
        );

        address delegatedOperator1 = delegationManager.delegatedTo(address(stakingNodeInstance));
        assertEq(delegatedOperator1, operator1, "Delegation is not set to operator1.");

        IStrategy[] memory strategies = new IStrategy[](1);
        strategies[0] = stakingNodeInstance.beaconChainETHStrategy();

        assertEq(
            delegationManager.getOperatorShares(operator1, strategies)[0],
            32 ether * validatorIndices.length,
            "Operator shares should be 32 ETH per validator"
        );

        // Get initial total assets
        uint256 initialTotalAssets = yneth.totalAssets();

        {
            // Get initial queued shares
            uint256 initialQueuedShares = stakingNodeInstance.getQueuedSharesAmount();
            // Undelegate
            vm.prank(actors.admin.STAKING_NODES_DELEGATOR);
            bytes32[] memory withdrawalRoots = stakingNodeInstance.undelegate();
            assertEq(withdrawalRoots.length, 1, "Should have exactly one withdrawal root");

            // Get final queued shares and verify increase
            uint256 finalQueuedShares = stakingNodeInstance.getQueuedSharesAmount();
            assertEq(
                finalQueuedShares - initialQueuedShares,
                32 ether * validatorIndices.length,
                "Queued shares should increase by 32 ETH per validator"
            );

            // Verify total assets stayed the same
            assertEq(yneth.totalAssets(), initialTotalAssets, "Total assets should not change after undelegation");
        }

        address undelegatedAddress = delegationManager.delegatedTo(address(stakingNodeInstance));
        assertEq(undelegatedAddress, address(0), "Delegation should be cleared after undelegation.");
    }

    function testOperatorUndelegateSynchronizeAndCompleteWithdrawals() public {
        {
            vm.deal(user, 1000 ether);
            yneth.depositETH{value: 1000 ether}(user);

            // Call createValidators with the nodeIds array and validatorCount
            validatorIndices = createValidators(repeat(nodeId, 1), 1);
            beaconChain.advanceEpoch_NoRewards();
            registerValidators(repeat(nodeId, 1));
            _verifyWithdrawalCredentials(nodeId, validatorIndices[0]);
        }

        IDelegationManager delegationManager = stakingNodesManager.delegationManager();

        // Delegate to operator1
        vm.prank(actors.admin.STAKING_NODES_DELEGATOR);
        stakingNodeInstance.delegate(
            operator1, ISignatureUtilsMixinTypes.SignatureWithExpiry({signature: "", expiry: 0}), bytes32(0)
        );

        address delegatedOperator1 = delegationManager.delegatedTo(address(stakingNodeInstance));
        assertEq(delegatedOperator1, operator1, "Delegation is not set to operator1.");

        IStrategy[] memory strategies = new IStrategy[](1);
        strategies[0] = stakingNodeInstance.beaconChainETHStrategy();

        assertEq(
            delegationManager.getOperatorShares(operator1, strategies)[0],
            32 ether * validatorIndices.length,
            "Operator shares should be 32 ETH per validator"
        );

        // Get initial total assets
        uint256 initialTotalAssets = yneth.totalAssets();

        {
            // Get initial queued shares
            uint256 initialQueuedShares = stakingNodeInstance.getQueuedSharesAmount();
            vm.prank(operator1);
            bytes32[] memory withdrawalRoots = delegationManager.undelegate(address(stakingNodeInstance));

            QueuedWithdrawalInfo[] memory queuedWithdrawals = new QueuedWithdrawalInfo[](1);
            queuedWithdrawals[0] = QueuedWithdrawalInfo({withdrawnAmount: 32 ether * validatorIndices.length});
            IDelegationManager.Withdrawal[] memory calculatedWithdrawals =
                _getWithdrawals(queuedWithdrawals, nodeId, operator1);

            assertEq(withdrawalRoots.length, 1, "Should have exactly one withdrawal root");
            assertEq(
                delegationManager.calculateWithdrawalRoot(calculatedWithdrawals[0]),
                withdrawalRoots[0],
                "Withdrawal root should match"
            );

            // Get final queued shares and verify increase
            uint256 finalQueuedShares = stakingNodeInstance.getQueuedSharesAmount();
            assertEq(
                finalQueuedShares,
                initialQueuedShares,
                "Queued shares should not change after undelegation from operator due to unsynchronized state"
            );

            // Verify total assets stayed the same
            assertEq(yneth.totalAssets(), initialTotalAssets, "Total assets should not change after undelegation");

            // Synchronize
            vm.prank(actors.admin.STAKING_NODES_DELEGATOR);
            stakingNodeInstance.synchronize();

            // Verify total assets stayed the same
            assertEq(yneth.totalAssets(), initialTotalAssets, "Total assets should not change after synchronization");

            {
                strategies = new IStrategy[](1);
                strategies[0] = stakingNodeInstance.beaconChainETHStrategy();
                // advance time to allow completion
                vm.roll(block.number + delegationManager.minWithdrawalDelayBlocks() + 1);
            }

            // complete queued withdrawals
            {
                vm.prank(actors.admin.STAKING_NODES_DELEGATOR);
                stakingNodeInstance.completeQueuedWithdrawalsAsShares(calculatedWithdrawals);
            }

            finalQueuedShares = stakingNodeInstance.getQueuedSharesAmount();
            assertEq(finalQueuedShares, 0, "Queued shares should decrease to 0 after withdrawal");

            // Verify total assets stayed the same
            assertEq(yneth.totalAssets(), initialTotalAssets, "Total assets should not change after withdrawal");
        }

        address delegatedAddress = delegationManager.delegatedTo(address(stakingNodeInstance));
        assertEq(delegatedAddress, address(0), "Delegation should be cleared after undelegation.");
    }

    function testOperatorUndelegateSynchronizeAndCompleteWithdrawalsAndDelegateAgain() public {
        {
            vm.deal(user, 1000 ether);
            yneth.depositETH{value: 1000 ether}(user);

            // Call createValidators with the nodeIds array and validatorCount
            validatorIndices = createValidators(repeat(nodeId, 1), 1);
            beaconChain.advanceEpoch_NoRewards();
            registerValidators(repeat(nodeId, 1));
            _verifyWithdrawalCredentials(nodeId, validatorIndices[0]);
        }

        IDelegationManager delegationManager = stakingNodesManager.delegationManager();

        // Delegate to operator1
        vm.prank(actors.admin.STAKING_NODES_DELEGATOR);
        stakingNodeInstance.delegate(
            operator1, ISignatureUtilsMixinTypes.SignatureWithExpiry({signature: "", expiry: 0}), bytes32(0)
        );

        address delegatedOperator1 = delegationManager.delegatedTo(address(stakingNodeInstance));
        assertEq(delegatedOperator1, operator1, "Delegation is not set to operator1.");

        IStrategy[] memory strategies = new IStrategy[](1);
        strategies[0] = stakingNodeInstance.beaconChainETHStrategy();

        assertEq(
            delegationManager.getOperatorShares(operator1, strategies)[0],
            32 ether * validatorIndices.length,
            "Operator shares should be 32 ETH per validator"
        );

        // Get initial total assets
        uint256 initialTotalAssets = yneth.totalAssets();

        {
            // Get initial queued shares
            uint256 initialQueuedShares = stakingNodeInstance.getQueuedSharesAmount();
            vm.prank(operator1);
            bytes32[] memory withdrawalRoots = delegationManager.undelegate(address(stakingNodeInstance));

            QueuedWithdrawalInfo[] memory queuedWithdrawals = new QueuedWithdrawalInfo[](1);
            queuedWithdrawals[0] = QueuedWithdrawalInfo({withdrawnAmount: 32 ether * validatorIndices.length});
            IDelegationManager.Withdrawal[] memory calculatedWithdrawals =
                _getWithdrawals(queuedWithdrawals, nodeId, operator1);

            assertEq(withdrawalRoots.length, 1, "Should have exactly one withdrawal root");
            assertEq(
                delegationManager.calculateWithdrawalRoot(calculatedWithdrawals[0]),
                withdrawalRoots[0],
                "Withdrawal root should match"
            );

            // Get final queued shares and verify increase
            uint256 finalQueuedShares = stakingNodeInstance.getQueuedSharesAmount();
            assertEq(
                finalQueuedShares,
                initialQueuedShares,
                "Queued shares should not change after undelegation from operator due to unsynchronized state"
            );

            // Verify total assets stayed the same
            assertEq(yneth.totalAssets(), initialTotalAssets, "Total assets should not change after undelegation");

            // Synchronize
            vm.prank(actors.admin.STAKING_NODES_DELEGATOR);
            stakingNodeInstance.synchronize();

            // Verify total assets stayed the same
            assertEq(yneth.totalAssets(), initialTotalAssets, "Total assets should not change after synchronization");

            {
                strategies = new IStrategy[](1);
                strategies[0] = stakingNodeInstance.beaconChainETHStrategy();
                // advance time to allow completion
                vm.roll(block.number + delegationManager.minWithdrawalDelayBlocks() + 1);
            }

            // complete queued withdrawals
            {
                vm.prank(actors.admin.STAKING_NODES_DELEGATOR);
                stakingNodeInstance.completeQueuedWithdrawalsAsShares(calculatedWithdrawals);
            }

            finalQueuedShares = stakingNodeInstance.getQueuedSharesAmount();
            assertEq(finalQueuedShares, 0, "Queued shares should decrease to 0 after withdrawal");

            // Verify total assets stayed the same
            assertEq(yneth.totalAssets(), initialTotalAssets, "Total assets should not change after withdrawal");
        }

        address delegatedAddress = delegationManager.delegatedTo(address(stakingNodeInstance));
        assertEq(delegatedAddress, address(0), "Delegation should be cleared after undelegation.");

        vm.prank(actors.admin.STAKING_NODES_DELEGATOR);
        stakingNodeInstance.delegate(
            operator2, ISignatureUtilsMixinTypes.SignatureWithExpiry({signature: "", expiry: 0}), bytes32(0)
        );

        delegatedAddress = delegationManager.delegatedTo(address(stakingNodeInstance));
        assertEq(
            delegatedAddress,
            operator2,
            "Delegation should be set to operator2 after undelegation and delegation again."
        );

        // Verify total assets stayed the same
        assertEq(yneth.totalAssets(), initialTotalAssets, "Total assets should not change after re-delegation");
    }

    function testOperatorUndelegateSynchronizeDelegateAndCompleteWithdrawals() public {
        {
            vm.deal(user, 1000 ether);
            yneth.depositETH{value: 1000 ether}(user);

            // Call createValidators with the nodeIds array and validatorCount
            validatorIndices = createValidators(repeat(nodeId, 1), 1);
            beaconChain.advanceEpoch_NoRewards();
            registerValidators(repeat(nodeId, 1));
            _verifyWithdrawalCredentials(nodeId, validatorIndices[0]);
        }

        IDelegationManager delegationManager = stakingNodesManager.delegationManager();

        // Delegate to operator1
        vm.prank(actors.admin.STAKING_NODES_DELEGATOR);
        stakingNodeInstance.delegate(
            operator1, ISignatureUtilsMixinTypes.SignatureWithExpiry({signature: "", expiry: 0}), bytes32(0)
        );

        address delegatedOperator1 = delegationManager.delegatedTo(address(stakingNodeInstance));
        assertEq(delegatedOperator1, operator1, "Delegation is not set to operator1.");

        IStrategy[] memory strategies = new IStrategy[](1);
        strategies[0] = stakingNodeInstance.beaconChainETHStrategy();

        assertEq(
            delegationManager.getOperatorShares(operator1, strategies)[0],
            32 ether * validatorIndices.length,
            "Operator shares should be 32 ETH per validator"
        );

        // Get initial total assets
        uint256 initialTotalAssets = yneth.totalAssets();

        IDelegationManager.Withdrawal[] memory calculatedWithdrawals;

        {
            // Get initial queued shares
            uint256 initialQueuedShares = stakingNodeInstance.getQueuedSharesAmount();
            vm.prank(operator1);
            bytes32[] memory withdrawalRoots = delegationManager.undelegate(address(stakingNodeInstance));

            QueuedWithdrawalInfo[] memory queuedWithdrawals = new QueuedWithdrawalInfo[](1);
            queuedWithdrawals[0] = QueuedWithdrawalInfo({withdrawnAmount: 32 ether * validatorIndices.length});
            calculatedWithdrawals = _getWithdrawals(queuedWithdrawals, nodeId, operator1);

            assertEq(withdrawalRoots.length, 1, "Should have exactly one withdrawal root");
            assertEq(
                delegationManager.calculateWithdrawalRoot(calculatedWithdrawals[0]),
                withdrawalRoots[0],
                "Withdrawal root should match"
            );

            // Get final queued shares and verify increase
            uint256 finalQueuedShares = stakingNodeInstance.getQueuedSharesAmount();
            assertEq(
                finalQueuedShares,
                initialQueuedShares,
                "Queued shares should not change after undelegation from operator due to unsynchronized state"
            );

            // Verify total assets stayed the same
            assertEq(yneth.totalAssets(), initialTotalAssets, "Total assets should not change after undelegation");

            // Synchronize
            vm.prank(actors.admin.STAKING_NODES_DELEGATOR);
            stakingNodeInstance.synchronize();

            // Verify total assets stayed the same
            assertEq(yneth.totalAssets(), initialTotalAssets, "Total assets should not change after synchronization");
        }

        address delegatedAddress = delegationManager.delegatedTo(address(stakingNodeInstance));
        assertEq(delegatedAddress, address(0), "Delegation should be cleared after undelegation.");

        vm.prank(actors.admin.STAKING_NODES_DELEGATOR);
        stakingNodeInstance.delegate(
            operator2, ISignatureUtilsMixinTypes.SignatureWithExpiry({signature: "", expiry: 0}), bytes32(0)
        );

        delegatedAddress = delegationManager.delegatedTo(address(stakingNodeInstance));
        assertEq(
            delegatedAddress,
            operator2,
            "Delegation should be set to operator2 after undelegation and delegation again."
        );

        {
            strategies = new IStrategy[](1);
            strategies[0] = stakingNodeInstance.beaconChainETHStrategy();
            // advance time to allow completion
            vm.roll(block.number + delegationManager.minWithdrawalDelayBlocks() + 1);
        }

        // complete queued withdrawals
        {
            vm.prank(actors.admin.STAKING_NODES_DELEGATOR);
            stakingNodeInstance.completeQueuedWithdrawalsAsShares(calculatedWithdrawals);

            uint256 finalQueuedShares = stakingNodeInstance.getQueuedSharesAmount();
            assertEq(finalQueuedShares, 0, "Queued shares should decrease to 0 after withdrawal");
        }

        // Verify total assets stayed the same
        assertEq(yneth.totalAssets(), initialTotalAssets, "Total assets should not change after withdrawal");
    }

    function testDelegateUndelegateAndDelegateAgainWithExistingStake() public {
        address initialOperator = operator1;
        testDelegateUndelegateWithExistingStake();

        uint256 initialTotalAssets = yneth.totalAssets();

        // Complete queued withdrawals as shares
        QueuedWithdrawalInfo[] memory queuedWithdrawals = new QueuedWithdrawalInfo[](1);
        queuedWithdrawals[0] = QueuedWithdrawalInfo({withdrawnAmount: 32 ether * validatorIndices.length});
        _completeQueuedWithdrawalsAsShares(queuedWithdrawals, nodeId, initialOperator);

        // Verify total assets stayed the same after _completeQueuedWithdrawalsAsShares
        assertEq(
            yneth.totalAssets(),
            initialTotalAssets,
            "Total assets should not change after completing queued withdrawals"
        );

        // Delegate to operator2
        vm.prank(actors.admin.STAKING_NODES_DELEGATOR);
        stakingNodeInstance.delegate(
            operator2, ISignatureUtilsMixinTypes.SignatureWithExpiry({signature: "", expiry: 0}), bytes32(0)
        );

        // Verify total assets stayed the same after delegation to operator2
        assertEq(
            yneth.totalAssets(), initialTotalAssets, "Total assets should not change after delegation to operator2"
        );

        address delegatedOperator2 = delegationManager.delegatedTo(address(stakingNodeInstance));
        assertEq(delegatedOperator2, operator2, "Delegation is not set to operator2.");

        IStrategy[] memory strategies = new IStrategy[](1);
        strategies[0] = stakingNodeInstance.beaconChainETHStrategy();

        assertEq(
            delegationManager.getOperatorShares(operator2, strategies)[0],
            32 ether * validatorIndices.length,
            "Operator shares should be 32 ETH per validator"
        );
    }

    function testDelegateUndelegateAndDelegateAgainWithoutStake() public {
        address initialOperator = operator1;
        testDelegateUndelegateWithExistingStake();

        uint256 initialTotalAssets = yneth.totalAssets();

        // Complete queued withdrawals as shares
        QueuedWithdrawalInfo[] memory queuedWithdrawals = new QueuedWithdrawalInfo[](1);
        queuedWithdrawals[0] = QueuedWithdrawalInfo({withdrawnAmount: 32 ether * validatorIndices.length});

        // Delegate to operator2
        vm.prank(actors.admin.STAKING_NODES_DELEGATOR);
        stakingNodeInstance.delegate(
            operator2, ISignatureUtilsMixinTypes.SignatureWithExpiry({signature: "", expiry: 0}), bytes32(0)
        );

        address delegatedOperator2 = delegationManager.delegatedTo(address(stakingNodeInstance));
        assertEq(delegatedOperator2, operator2, "Delegation is not set to operator2.");

        // Verify total assets stayed the same after delegation to operator2
        assertEq(
            yneth.totalAssets(), initialTotalAssets, "Total assets should not change after delegation to operator2"
        );

        assertEq(eigenPodManager.podOwnerDepositShares(address(stakingNodeInstance)), 0, "Pod owner shares should be 0");

        _completeQueuedWithdrawalsAsShares(queuedWithdrawals, nodeId, initialOperator);

        // Verify total assets stayed the same after _completeQueuedWithdrawalsAsShares
        assertEq(
            yneth.totalAssets(),
            initialTotalAssets,
            "Total assets should not change after completing queued withdrawals"
        );

        IStrategy[] memory strategies = new IStrategy[](1);
        strategies[0] = stakingNodeInstance.beaconChainETHStrategy();

        assertEq(
            delegationManager.getOperatorShares(operator2, strategies)[0],
            32 ether * validatorIndices.length,
            "Operator shares should be 32 ETH per validator"
        );

        assertEq(
            eigenPodManager.podOwnerDepositShares(address(stakingNodeInstance)),
            int256(32 ether * validatorIndices.length),
            "Pod owner shares should be 32 ETH per validator"
        );
    }

    function testSetClaimer() public {
        vm.prank(actors.admin.STAKING_NODES_DELEGATOR);
        stakingNodeInstance.delegate(
            operator1, ISignatureUtilsMixinTypes.SignatureWithExpiry({signature: "", expiry: 0}), bytes32(0)
        );

        // Create a claimer address
        address claimer = vm.addr(12_345);

        // Set claimer should fail from non-delegator
        vm.expectRevert(StakingNode.NotStakingNodesDelegator.selector);
        stakingNodeInstance.setClaimer(claimer);

        // Set claimer from delegator
        vm.prank(actors.admin.STAKING_NODES_DELEGATOR);
        stakingNodeInstance.setClaimer(claimer);

        // Verify claimer is set correctly in rewards coordinator
        IRewardsCoordinator rewardsCoordinator = stakingNodesManager.rewardsCoordinator();
        assertEq(rewardsCoordinator.claimerFor(address(stakingNodeInstance)), claimer, "Claimer not set correctly");
    }

    function testImplementViewFunction() public {
        vm.prank(actors.ops.STAKING_NODE_CREATOR);
        stakingNodeInstance = stakingNodesManager.createStakingNode();
        address expectedImplementation = address(stakingNodesManager.upgradeableBeacon().implementation());
        assertEq(stakingNodeInstance.implementation(), expectedImplementation, "Implementation address mismatch");
    }

}

contract StakingNodeVerifyWithdrawalCredentials is StakingNodeTestBase {

    address user = vm.addr(156_737);

    uint40[] validatorIndices;
    uint256 AMOUNT = 32 ether;

    function setUp() public override {
        super.setUp();

        // Create a user address and fund it with 1000 ETH
        vm.deal(user, 1000 ether);

        yneth.depositETH{value: 1000 ether}(user);
    }

    function testVerifyWithdrawalCredentialsForOneValidator() public {
        uint256 nodeId = createStakingNodes(1)[0];
        // Call createValidators with the nodeIds array and validatorCount
        validatorIndices = createValidators(repeat(nodeId, 1), 1);
        beaconChain.advanceEpoch_NoRewards();
        registerValidators(repeat(nodeId, 1));

        // Capture state before verification
        StateSnapshot memory before = takeSnapshot(nodeId);

        _verifyWithdrawalCredentials(nodeId, validatorIndices[0]);

        // Capture state after verification
        StateSnapshot memory afterVerification = takeSnapshot(nodeId);

        // Assert that ynETH totalAssets, totalSupply, and staking Node balance, queuedShares and withdrawnETH stay the same
        assertEq(afterVerification.totalAssets, before.totalAssets, "Total assets should not change");
        assertEq(afterVerification.totalSupply, before.totalSupply, "Total supply should not change");
        assertEq(
            afterVerification.stakingNodeBalance, before.stakingNodeBalance, "Staking node balance should not change"
        );
        assertEq(afterVerification.queuedShares, before.queuedShares, "Queued shares should not change");
        assertEq(afterVerification.withdrawnETH, before.withdrawnETH, "Withdrawn ETH should not change");

        // Assert that unverifiedStakedETH decreases
        assertLt(
            afterVerification.unverifiedStakedETH, before.unverifiedStakedETH, "Unverified staked ETH should decrease"
        );

        // Additional checks
        assertEq(afterVerification.unverifiedStakedETH, 0, "Unverified staked ETH should be 0 after verification");
        assertEq(
            uint256(eigenPodManager.podOwnerDepositShares(address(stakingNodesManager.nodes(nodeId)))),
            AMOUNT,
            "Pod owner shares should equal AMOUNT"
        );
    }

    function testVerifyWithdrawalCredentialsTwice() public {
        uint256 nodeId = createStakingNodes(1)[0];
        // Call createValidators with the nodeIds array and validatorCount
        validatorIndices = createValidators(repeat(nodeId, 1), 1);
        beaconChain.advanceEpoch_NoRewards();
        registerValidators(repeat(nodeId, 1));

        uint40 validatorIndex = validatorIndices[0];

        // First verification
        _verifyWithdrawalCredentials(nodeId, validatorIndex);

        // Try to verify withdrawal credentials again
        uint40[] memory _validators = new uint40[](1);
        _validators[0] = validatorIndex;

        CredentialProofs memory _proofs = beaconChain.getCredentialProofs(_validators);
        vm.startPrank(actors.ops.STAKING_NODES_OPERATOR);
        IEigenPodSimplified node = IEigenPodSimplified(address(stakingNodesManager.nodes(nodeId)));
        vm.expectRevert(IEigenPodErrors.CredentialsAlreadyVerified.selector);
        node.verifyWithdrawalCredentials({
            beaconTimestamp: _proofs.beaconTimestamp,
            stateRootProof: _proofs.stateRootProof,
            validatorIndices: _validators,
            validatorFieldsProofs: _proofs.validatorFieldsProofs,
            validatorFields: _proofs.validatorFields
        });
        vm.stopPrank();
    }

    function testVerifyCheckpointsForOneValidator() public {
        uint256 nodeId = createStakingNodes(1)[0];
        // Call createValidators with the nodeIds array and validatorCount
        validatorIndices = createValidators(repeat(nodeId, 1), 1);
        beaconChain.advanceEpoch_NoRewards();
        registerValidators(repeat(nodeId, 1));

        uint40 validatorIndex = validatorIndices[0];

        {
            _verifyWithdrawalCredentials(nodeId, validatorIndex);

            // check that unverifiedStakedETH is 0 and podOwnerDepositShares is 32 ETH (AMOUNT)
            assertEq(stakingNodesManager.nodes(nodeId).unverifiedStakedETH(), 0, "_testVerifyWithdrawalCredentials: E0");
            assertEq(
                uint256(eigenPodManager.podOwnerDepositShares(address(stakingNodesManager.nodes(nodeId)))),
                AMOUNT,
                "_testVerifyWithdrawalCredentials: E1"
            );
        }

        beaconChain.advanceEpoch();
        // Capture initial state
        StateSnapshot memory initialState = takeSnapshot(nodeId);

        // start checkpoint
        {
            vm.startPrank(actors.ops.STAKING_NODES_OPERATOR);
            stakingNodesManager.nodes(nodeId).startCheckpoint(false);
            vm.stopPrank();

            // make sure startCheckpoint cant be called again, which means that the checkpoint has started
            IStakingNode _node = stakingNodesManager.nodes(nodeId);
            vm.expectRevert(IEigenPodErrors.CheckpointAlreadyActive.selector);
            vm.prank(actors.ops.STAKING_NODES_OPERATOR);
            _node.startCheckpoint(true);
        }

        // Assert that state remains unchanged after starting checkpoint
        StateSnapshot memory afterStartCheckpoint = takeSnapshot(nodeId);
        assertEq(
            afterStartCheckpoint.totalAssets, initialState.totalAssets, "Total assets changed after starting checkpoint"
        );
        assertEq(
            afterStartCheckpoint.totalSupply, initialState.totalSupply, "Total supply changed after starting checkpoint"
        );
        assertEq(
            afterStartCheckpoint.stakingNodeBalance,
            initialState.stakingNodeBalance,
            "Node balance changed after starting checkpoint"
        );
        assertEq(
            afterStartCheckpoint.queuedShares,
            initialState.queuedShares,
            "Queued shares changed after starting checkpoint"
        );
        assertEq(
            afterStartCheckpoint.withdrawnETH,
            initialState.withdrawnETH,
            "Withdrawn ETH changed after starting checkpoint"
        );
        assertEq(
            afterStartCheckpoint.unverifiedStakedETH,
            initialState.unverifiedStakedETH,
            "Unverified staked ETH changed after starting checkpoint"
        );

        // verify checkpoints
        {
            uint40[] memory _validators = new uint40[](1);
            _validators[0] = validatorIndex;
            IStakingNode _node = stakingNodesManager.nodes(nodeId);
            CheckpointProofs memory _cpProofs =
                beaconChain.getCheckpointProofs(_validators, _node.eigenPod().currentCheckpointTimestamp());
            uint256 _currentCheckpointTimestampBefore = stakingNodesManager.nodes(nodeId).eigenPod().currentCheckpointTimestamp();
            IEigenPodSimplified(address(_node.eigenPod())).verifyCheckpointProofs({
                balanceContainerProof: _cpProofs.balanceContainerProof,
                proofs: _cpProofs.balanceProofs
            });
            uint256 _currentCheckpointTimestampAfter = stakingNodesManager.nodes(nodeId).eigenPod().currentCheckpointTimestamp();
            uint256 _lastCheckpointTimestamp = stakingNodesManager.nodes(nodeId).eigenPod().lastCheckpointTimestamp();
            // check that proofsRemaining is 0
            assertEq(_currentCheckpointTimestampAfter, 0, "_testVerifyCheckpointsBeforeWithdrawalRequest: E0");
            assertEq(_lastCheckpointTimestamp, _currentCheckpointTimestampBefore, "_testVerifyCheckpointsBeforeWithdrawalRequest: E1");

            stakingNodesManager.updateTotalETHStaked();

            // Assert that node balance and shares increased by the amount of rewards
            StateSnapshot memory afterVerification = takeSnapshot(nodeId);
            uint256 rewardsAmount = uint256(afterVerification.podOwnerDepositShares - initialState.podOwnerDepositShares);
            // Calculate expected rewards for one epoch
            uint256 expectedRewards = 1 * 1 * 1e9; // 1 GWEI per Epoch per Validator;
            assertApproxEqAbs(
                rewardsAmount, expectedRewards, 1, "Rewards amount does not match expected value for one epoch"
            );

            assertEq(
                afterVerification.stakingNodeBalance,
                initialState.stakingNodeBalance + rewardsAmount,
                "Node balance did not increase by rewards amount"
            );

            // Assert that other state variables remain unchanged
            assertEq(
                afterVerification.totalAssets,
                initialState.totalAssets + expectedRewards,
                "Total assets changed after verification"
            );
            assertEq(afterVerification.totalSupply, initialState.totalSupply, "Total supply changed after verification");
            assertEq(
                afterVerification.queuedShares, initialState.queuedShares, "Queued shares changed after verification"
            );
            assertEq(
                afterVerification.withdrawnETH, initialState.withdrawnETH, "Withdrawn ETH changed after verification"
            );
            assertEq(
                afterVerification.unverifiedStakedETH,
                initialState.unverifiedStakedETH,
                "Unverified staked ETH changed after verification"
            );
        }
    }

    function testVerifyCheckpointsForManyValidators() public {
        uint256 validatorCount = 3;

        uint256 nodeId = createStakingNodes(1)[0];
        // Call createValidators with the nodeIds array and validatorCount
        validatorIndices = createValidators(repeat(nodeId, 1), validatorCount);
        beaconChain.advanceEpoch_NoRewards();
        registerValidators(repeat(nodeId, validatorCount));

        {
            for (uint256 i = 0; i < validatorIndices.length; i++) {
                _verifyWithdrawalCredentials(nodeId, validatorIndices[i]);
            }

            // check that unverifiedStakedETH is 0 and podOwnerDepositShares is 32 ETH (AMOUNT)
            assertEq(stakingNodesManager.nodes(nodeId).unverifiedStakedETH(), 0, "_testVerifyWithdrawalCredentials: E0");
            assertEq(
                uint256(eigenPodManager.podOwnerDepositShares(address(stakingNodesManager.nodes(nodeId)))),
                AMOUNT * validatorCount,
                "_testVerifyWithdrawalCredentials: E1"
            );
        }

        beaconChain.advanceEpoch_NoRewards();

        uint256 exitedValidatorsCount = 1;

        // exit validators
        {
            for (uint256 i = 0; i < exitedValidatorsCount; i++) {
                beaconChain.exitValidator(validatorIndices[i]);
            }
            beaconChain.advanceEpoch_NoRewards();
        }
        // Take snapshot before starting checkpoint
        StateSnapshot memory beforeStart = takeSnapshot(nodeId);

        // start checkpoint
        {
            vm.startPrank(actors.ops.STAKING_NODES_OPERATOR);
            stakingNodesManager.nodes(nodeId).startCheckpoint(true);
            vm.stopPrank();

            // make sure startCheckpoint cant be called again, which means that the checkpoint has started
            IStakingNode _node = stakingNodesManager.nodes(nodeId);
            vm.expectRevert(IEigenPodErrors.CheckpointAlreadyActive.selector);
            vm.prank(actors.ops.STAKING_NODES_OPERATOR);
            _node.startCheckpoint(true);
        }

        // Take snapshot after starting checkpoint
        StateSnapshot memory afterStart = takeSnapshot(nodeId);

        // Assert state after starting checkpoint
        assertEq(
            afterStart.totalAssets, beforeStart.totalAssets, "Total assets should not change after starting checkpoint"
        );
        assertEq(
            afterStart.totalSupply, beforeStart.totalSupply, "Total supply should not change after starting checkpoint"
        );
        assertEq(
            afterStart.stakingNodeBalance,
            beforeStart.stakingNodeBalance,
            "Staking node balance should not change after starting checkpoint"
        );
        assertEq(
            afterStart.queuedShares,
            beforeStart.queuedShares,
            "Queued shares should not change after starting checkpoint"
        );
        assertEq(
            afterStart.withdrawnETH,
            beforeStart.withdrawnETH,
            "Withdrawn ETH should not change after starting checkpoint"
        );
        assertEq(
            afterStart.unverifiedStakedETH,
            beforeStart.unverifiedStakedETH,
            "Unverified staked ETH should not change after starting checkpoint"
        );
        assertEq(
            afterStart.podOwnerDepositShares,
            beforeStart.podOwnerDepositShares,
            "Pod owner shares should not change after starting checkpoint"
        );

        // verify checkpoints
        {
            uint40[] memory _validators = validatorIndices;
            IStakingNode _node = stakingNodesManager.nodes(nodeId);
            CheckpointProofs memory _cpProofs =
                beaconChain.getCheckpointProofs(_validators, _node.eigenPod().currentCheckpointTimestamp());
            uint256 _currentCheckpointTimestampBefore = stakingNodesManager.nodes(nodeId).eigenPod().currentCheckpointTimestamp();
            IEigenPodSimplified(address(_node.eigenPod())).verifyCheckpointProofs({
                balanceContainerProof: _cpProofs.balanceContainerProof,
                proofs: _cpProofs.balanceProofs
            });

            // Take snapshot after verifying checkpoint
            StateSnapshot memory afterVerify = takeSnapshot(nodeId);

            // Assert state after verifying checkpoint
            assertEq(
                afterVerify.totalAssets,
                afterStart.totalAssets,
                "Total assets should not change after verifying checkpoint"
            );
            assertEq(
                afterVerify.totalSupply,
                afterStart.totalSupply,
                "Total supply should not change after verifying checkpoint"
            );
            assertGe(
                afterVerify.stakingNodeBalance,
                afterStart.stakingNodeBalance,
                "Staking node balance should not decrease after verifying checkpoint"
            );
            assertEq(
                afterVerify.queuedShares,
                afterStart.queuedShares,
                "Queued shares should not change after verifying checkpoint"
            );
            assertEq(
                afterVerify.withdrawnETH,
                afterStart.withdrawnETH,
                "Withdrawn ETH should not change after verifying checkpoint"
            );
            assertEq(
                afterVerify.unverifiedStakedETH,
                afterStart.unverifiedStakedETH,
                "Unverified staked ETH should not change after verifying checkpoint"
            );
            assertGe(
                afterVerify.podOwnerDepositShares,
                afterStart.podOwnerDepositShares,
                "Pod owner shares should not decrease after verifying checkpoint"
            );

            uint256 _currentCheckpointTimestampAfter = stakingNodesManager.nodes(nodeId).eigenPod().currentCheckpointTimestamp();
            uint256 _lastCheckpointTimestamp = stakingNodesManager.nodes(nodeId).eigenPod().lastCheckpointTimestamp();
            assertEq(_currentCheckpointTimestampAfter, 0, "_testVerifyCheckpointsBeforeWithdrawalRequest: E0");
            assertEq(_lastCheckpointTimestamp, _currentCheckpointTimestampBefore, "_testVerifyCheckpointsBeforeWithdrawalRequest: E1");
            assertApproxEqAbs(
                uint256(eigenPodManager.podOwnerDepositShares(address(stakingNodesManager.nodes(nodeId)))),
                AMOUNT * validatorCount,
                1_000_000_000,
                "_testVerifyCheckpointsBeforeWithdrawalRequest: E2"
            );
        }
    }
}
