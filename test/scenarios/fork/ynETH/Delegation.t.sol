// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IEigenPod} from "lib/eigenlayer-contracts/src/contracts/interfaces/IEigenPod.sol";
import {StakingNode} from "src/StakingNode.sol";
import {IStakingNode} from "src/interfaces/IStakingNode.sol";
import {IStakingNodesManager} from "src/interfaces/IStakingNodesManager.sol";
import {IWithdrawalQueueManager} from "src/interfaces/IWithdrawalQueueManager.sol";

import {WithdrawalsScenarioTestBase} from "./WithdrawalsScenarioTestBase.sol";


contract YnETHDelegationScenarioTest is WithdrawalsScenarioTestBase {

    function test_undelegate_Scenario_undelegateByOperator() public {

        // Log total assets before undelegation
        uint256 totalAssetsBefore = yneth.totalAssets();


        IStakingNode stakingNode = stakingNodesManager.nodes(0);

        // Get initial ETH balance of staking node
        uint256 stakingNodeBalanceBefore = stakingNode.getETHBalance();

        // Get operator for node 0
        address operator = delegationManager.delegatedTo(address(stakingNode));

        // Get initial pod shares and block number
        int256 signedPodSharesBefore = eigenPodManager.podOwnerDepositShares(address(stakingNode));

        // TODO: ensure
        uint256 podSharesBefore = signedPodSharesBefore < 0 ? 0 : uint256(signedPodSharesBefore);

        uint32 blockNumberBefore = uint32(block.number);

        // Call undelegate from operator
        vm.startPrank(operator);
        delegationManager.undelegate(address(stakingNode));
        vm.stopPrank();

        // Assert node is no longer delegated after undelegation
        assertEq(delegationManager.delegatedTo(address(stakingNode)), address(0), "Node should not be delegated after undelegation");

        // Assert total assets remain unchanged after undelegation
        assertEq(totalAssetsBefore,  yneth.totalAssets(), "Total assets should not change after undelegation");

        // Assert staking node balance dropped by pod shares amount
        assertEq(stakingNodeBalanceBefore - podSharesBefore, stakingNode.getETHBalance(), "Staking node balance should decrease by pod shares amount");

        // Assert node is not synchronized after undelegation
        assertFalse(stakingNode.isSynchronized(), "Node should not be synchronized after undelegation");

        // Call synchronize after verifying not synchronized
        vm.prank(actors.admin.STAKING_NODES_DELEGATOR);
        stakingNode.synchronize(podSharesBefore, blockNumberBefore);

        // Assert staking node balance remains unchanged after synchronization
        assertEq(stakingNodeBalanceBefore, stakingNode.getETHBalance(), "Staking node balance should not change after synchronization");

        stakingNodesManager.updateTotalETHStaked();

        assertEq(totalAssetsBefore,  yneth.totalAssets(), "Total assets should not change after synchronization");

        // Complete queued withdrawals as shares
        QueuedWithdrawalInfo[] memory queuedWithdrawals = new QueuedWithdrawalInfo[](1);
        queuedWithdrawals[0] = QueuedWithdrawalInfo({
            nodeId: 0,
            withdrawnAmount: podSharesBefore
        });
        address[] memory operators = new address[](1);
        operators[0] = operator;

        uint256 queuedSharesBefore = stakingNode.getQueuedSharesAmount();

        completeQueuedWithdrawalsAsShares(0, queuedWithdrawals, operators);

        assertEq(queuedSharesBefore - podSharesBefore, stakingNode.getQueuedSharesAmount(), "Queued shares should decrease by pod shares amount");

        // Assert staking node balance remains unchanged after completing withdrawals
        assertEq(stakingNodeBalanceBefore, stakingNode.getETHBalance(), "Staking node balance should not change after completing withdrawals");

        stakingNodesManager.updateTotalETHStaked();

        // Assert total assets remain unchanged after completing withdrawals
        assertEq(totalAssetsBefore, yneth.totalAssets(), "Total assets should not change after completing withdrawals");
    }

    function test_undelegate_Scenario_undelegateByDelegator() public {
        // Log total assets before undelegation
        uint256 totalAssetsBefore = yneth.totalAssets();

        IStakingNode stakingNode = stakingNodesManager.nodes(0);

        // Get initial ETH balance of staking node
        uint256 stakingNodeBalanceBefore = stakingNode.getETHBalance();

        // Get delegator address for node 0
        address delegator = address(stakingNode);

        // Get initial pod shares and block number
        int256 signedPodSharesBefore = eigenPodManager.podOwnerDepositShares(delegator);
        uint256 podSharesBefore = signedPodSharesBefore < 0 ? 0 : uint256(signedPodSharesBefore);
        uint32 blockNumberBefore = uint32(block.number);

        // Call undelegate from delegator
        vm.startPrank(actors.admin.STAKING_NODES_DELEGATOR);
        stakingNode.undelegate();
        vm.stopPrank();

        // Assert node is no longer delegated after undelegation
        assertEq(delegationManager.delegatedTo(address(stakingNode)), address(0), "Node should not be delegated after undelegation");


        // Assert total assets remain unchanged after undelegation
        assertEq(totalAssetsBefore, yneth.totalAssets(), "Total assets should not change after undelegation");

        // Assert staking node balance dropped by pod shares amount
        assertEq(stakingNodeBalanceBefore, stakingNode.getETHBalance(), "Staking node balance should stay the same");

        // Assert node is synchronized after undelegation
        assertTrue(stakingNode.isSynchronized(), "Node should be synchronized after undelegation");

        // Call synchronize after verifying synchronized
        vm.expectRevert(StakingNode.AlreadySynchronized.selector);
        vm.prank(actors.admin.STAKING_NODES_DELEGATOR);
        stakingNode.synchronize(podSharesBefore, blockNumberBefore);

        // Assert staking node balance remains unchanged after synchronization
        assertEq(stakingNodeBalanceBefore, stakingNode.getETHBalance(), "Staking node balance should not change after synchronization");

        assertEq(totalAssetsBefore, yneth.totalAssets(), "Total assets should not change after synchronization");
    }
}