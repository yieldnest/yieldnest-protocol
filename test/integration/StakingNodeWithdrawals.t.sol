// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IDelegationManagerTypes} from "lib/eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStakingNode} from "src/interfaces/IStakingNode.sol";
import {IStakingNodesManager} from "src/interfaces/IStakingNodesManager.sol";
import {StakingNode} from "src/StakingNode.sol";
import {EigenPod} from "lib/eigenlayer-contracts/src/contracts/pods/EigenPod.sol";
import {EigenPodManager} from "lib/eigenlayer-contracts/src/contracts/pods/EigenPodManager.sol";
import {IEigenPodManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IEigenPodManager.sol";
import {IEigenPod} from "lib/eigenlayer-contracts/src/contracts/interfaces/IEigenPod.sol";
import {IEigenPodManagerErrors} from "lib/eigenlayer-contracts/src/contracts/interfaces/IEigenPodManager.sol";
import {StakingNodeTestBase} from "./StakingNodeTestBase.sol";
import {SlashingLib} from "lib/eigenlayer-contracts/src/contracts/libraries/SlashingLib.sol";
import {BeaconChainMock} from "lib/eigenlayer-contracts/src/test/integration/mocks/BeaconChainMock.t.sol";

contract StakingNodeWithdrawals is StakingNodeTestBase {

    using SlashingLib for *;

    function testQueueWithdrawals() public {
        // Setup
        uint256 depositAmount = 32 ether;
        address user = vm.addr(156_737);
        vm.deal(user, 1000 ether);
        yneth.depositETH{value: depositAmount}(user);

        uint256[] memory nodeIds = createStakingNodes(1);
        uint256 nodeId = nodeIds[0];
        IStakingNode stakingNodeInstance = stakingNodesManager.nodes(nodeIds[0]);

        // Create and register a validator
        uint40[] memory validatorIndices = createValidators(repeat(nodeIds[0], 1), 1);

        registerValidators(repeat(nodeIds[0], 1));
        beaconChain.advanceEpoch_NoRewards();

        // Verify withdrawal credentials
        _verifyWithdrawalCredentials(nodeIds[0], validatorIndices[0]);

        // Simulate some rewards
        beaconChain.advanceEpoch();

        uint40[] memory _validators = new uint40[](1);
        _validators[0] = validatorIndices[0];

        startAndVerifyCheckpoint(nodeId, _validators);

        // Get initial state
        StateSnapshot memory initialState = takeSnapshot(nodeIds[0]);

        // Queue withdrawals
        uint256 withdrawalAmount = 1 ether;
        vm.prank(actors.ops.STAKING_NODES_WITHDRAWER);
        stakingNodeInstance.queueWithdrawals(withdrawalAmount);

        // Get final state
        StateSnapshot memory finalState = takeSnapshot(nodeIds[0]);

        // Assert
        assertEq(finalState.totalAssets, initialState.totalAssets, "Total assets should remain unchanged");
        assertEq(finalState.totalSupply, initialState.totalSupply, "Total supply should remain unchanged");
        assertEq(
            finalState.stakingNodeBalance,
            initialState.stakingNodeBalance,
            "Staking node balance should remain unchanged"
        );
        assertEq(
            finalState.queuedShares,
            initialState.queuedShares + withdrawalAmount,
            "Queued shares should increase by withdrawal amount"
        );
        assertEq(finalState.withdrawnETH, initialState.withdrawnETH, "Withdrawn ETH should remain unchanged");
        assertEq(
            finalState.unverifiedStakedETH,
            initialState.unverifiedStakedETH,
            "Unverified staked ETH should remain unchanged"
        );
        assertEq(
            finalState.podOwnerDepositShares,
            initialState.podOwnerDepositShares - int256(withdrawalAmount),
            "Pod owner shares should decrease by withdrawalAmount"
        );
    }

    function testQueueWithdrawalsFailsWhenNotAdmin() public {
        uint256[] memory nodeIds = createStakingNodes(1);
        IStakingNode stakingNodeInstance = stakingNodesManager.nodes(nodeIds[0]);

        uint256 withdrawalAmount = 1 ether;
        vm.prank(address(0x1234567890123456789012345678901234567890));
        vm.expectRevert(StakingNode.NotStakingNodesWithdrawer.selector);
        stakingNodeInstance.queueWithdrawals(withdrawalAmount);
    }

    function testQueueWithdrawalsFailsWhenInsufficientBalance() public {
        uint256[] memory nodeIds = createStakingNodes(1);
        IStakingNode stakingNodeInstance = stakingNodesManager.nodes(nodeIds[0]);

        uint256 withdrawalAmount = 100 ether; // Assuming this is more than the node's balance
        vm.prank(actors.ops.STAKING_NODES_WITHDRAWER);
        vm.expectRevert(IEigenPodManagerErrors.SharesNegative.selector);
        stakingNodeInstance.queueWithdrawals(withdrawalAmount);
    }

    function testCompleteQueuedWithdrawalsWithMultipleValidators() public {
        // Setup
        uint256 validatorCount = 2;
        uint256 depositAmount = 32 ether;
        address user = vm.addr(156_737);
        vm.deal(user, 1000 ether);
        yneth.depositETH{value: depositAmount * validatorCount}(user); // Deposit for validators

        uint256[] memory nodeIds = createStakingNodes(1);
        uint256 nodeId = nodeIds[0];
        IStakingNode stakingNodeInstance = stakingNodesManager.nodes(nodeId);

        // Setup: Create multiple validators and verify withdrawal credentials
        uint40[] memory validatorIndices = createValidators(repeat(nodeId, validatorCount), validatorCount);
        beaconChain.advanceEpoch_NoRewards();
        registerValidators(repeat(nodeId, validatorCount));

        beaconChain.advanceEpoch_NoRewards();

        for (uint256 i = 0; i < validatorCount; i++) {
            _verifyWithdrawalCredentials(nodeIds[0], validatorIndices[i]);
        }

        beaconChain.advanceEpoch_NoRewards();

        // Exit some validators
        uint256 exitedValidatorCount = 1;
        for (uint256 i = 0; i < exitedValidatorCount; i++) {
            beaconChain.exitValidator(validatorIndices[i]);
        }

        // Advance the beacon chain by one epoch without rewards
        beaconChain.advanceEpoch_NoRewards();

        // Start and verify checkpoint for all validators
        startAndVerifyCheckpoint(nodeId, validatorIndices);

        // Queue withdrawals for exited validators
        uint256 withdrawalAmount = 32 ether * exitedValidatorCount;
        vm.prank(actors.ops.STAKING_NODES_WITHDRAWER);
        bytes32[] memory withdrawalRoots = stakingNodeInstance.queueWithdrawals(withdrawalAmount);

        // Capture initial state
        StateSnapshot memory before = takeSnapshot(nodeIds[0]);

        _completeQueuedWithdrawals(withdrawalRoots, nodeIds[0], false);

        // Capture final state
        StateSnapshot memory afterCompletion = takeSnapshot(nodeIds[0]);

        // Assertions
        assertEq(afterCompletion.queuedShares, before.queuedShares - withdrawalAmount, "Queued shares should decrease");
        assertEq(afterCompletion.withdrawnETH, before.withdrawnETH + withdrawalAmount, "Withdrawn ETH should increase");
        assertEq(afterCompletion.podOwnerDepositShares, before.podOwnerDepositShares, "Pod owner shares should remain unchanged");
        assertEq(
            afterCompletion.stakingNodeBalance,
            before.stakingNodeBalance,
            "Staking node balance should remain unchanged"
        );
    }

    function testQueueWithdrawalsBeforeExitingAndVerifyingValidator() public {
        uint256 validatorCount = 1;
        uint256 depositAmount = 32 ether;
        address user = vm.addr(156_737);
        vm.deal(user, 1000 ether);
        yneth.depositETH{value: depositAmount * validatorCount}(user);

        uint256 nodeId = createStakingNodes(1)[0];
        IStakingNode stakingNodeInstance = stakingNodesManager.nodes(nodeId);

        // Create and register a validator
        uint40[] memory validatorIndices = createValidators(repeat(nodeId, validatorCount), validatorCount);
        beaconChain.advanceEpoch_NoRewards();
        registerValidators(repeat(nodeId, validatorCount));

        beaconChain.advanceEpoch_NoRewards();

        // Verify withdrawal credentials
        _verifyWithdrawalCredentials(nodeId, validatorIndices[0]);

        beaconChain.advanceEpoch_NoRewards();

        // Capture initial state
        StateSnapshot memory before = takeSnapshot(nodeId);

        // Queue withdrawals before exiting the validator
        uint256 withdrawalAmount = 32 ether;
        vm.prank(actors.ops.STAKING_NODES_WITHDRAWER);
        bytes32[] memory _withdrawalRoots = stakingNodeInstance.queueWithdrawals(withdrawalAmount);
        (IDelegationManagerTypes.Withdrawal memory _withdrawal, ) = delegationManager.getQueuedWithdrawal(_withdrawalRoots[0]);
        uint256 _scaledShares = _withdrawal.scaledShares[0];

        // Exit the validator
        beaconChain.slashValidators(validatorIndices, BeaconChainMock.SlashType.Minor);

        beaconChain.advanceEpoch_NoRewards();

        uint256 _beaconChainSlashingFactorBefore = eigenPodManager.beaconChainSlashingFactor(address(stakingNodeInstance));
        assertEq(_beaconChainSlashingFactorBefore, 1e18, "_testQueueWithdrawalsBeforeExitingAndVerifyingValidator: E0");
        // Start and verify checkpoint
        startAndVerifyCheckpoint(nodeId, validatorIndices);

        uint256 _beaconChainSlashingFactorAfter = eigenPodManager.beaconChainSlashingFactor(address(stakingNodeInstance));
        assertLt(_beaconChainSlashingFactorAfter, 1e18, "_testQueueWithdrawalsBeforeExitingAndVerifyingValidator: E1");
        // Assert that podOwnerDepositShares are equal to negative slashingAmount
        uint256 slashedAmount = beaconChain.MINOR_SLASH_AMOUNT_GWEI() * 1e9;
        assertEq(
            eigenPodManager.podOwnerDepositShares(address(stakingNodeInstance)), 0,
            "Pod owner shares should not change"
        );

        vm.prank(actors.admin.STAKING_NODES_DELEGATOR);
        stakingNodeInstance.syncQueuedShares();

        _completeQueuedWithdrawals(_withdrawalRoots, nodeId, false);

        // Capture final state
        StateSnapshot memory afterCompletion = takeSnapshot(nodeId);

        // Assertions
        assertEq(
            afterCompletion.withdrawnETH,
            before.withdrawnETH + withdrawalAmount - slashedAmount,
            "Withdrawn ETH should increase by the withdrawn amount"
        );
        assertEq(
            afterCompletion.podOwnerDepositShares,
            before.podOwnerDepositShares - int256(withdrawalAmount),
            "Pod owner shares should decrease by withdrawalAmount"
        );
        assertEq(
            afterCompletion.queuedShares, before.queuedShares, "Queued shares should decrease back to original value"
        );
        assertEq(
            afterCompletion.stakingNodeBalance,
            before.stakingNodeBalance - slashedAmount,
            "Staking node balance should remain unchanged"
        );
        assertEq(
            afterCompletion.withdrawnETH,
            before.withdrawnETH + withdrawalAmount - slashedAmount,
            "Total withdrawn amount should match the expected amount"
        );
    }

}