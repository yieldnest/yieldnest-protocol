// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IStrategy} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    TransparentUpgradeableProxy,
    ITransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

import {ITokenStakingNodesManager} from "src/interfaces/ITokenStakingNodesManager.sol";
import {ITokenStakingNode} from "src/interfaces/ITokenStakingNode.sol";
import {IRedeemableAsset} from "src/interfaces/IRedeemableAsset.sol";
import {IYieldNestStrategyManager} from "src/interfaces/IYieldNestStrategyManager.sol";

import {LSDWrapper} from "src/ynEIGEN/LSDWrapper.sol";
import {RedemptionAssetsVault} from "src/ynEIGEN/RedemptionAssetsVault.sol";
import {WithdrawalQueueManager} from "src/WithdrawalQueueManager.sol";
import {IWithdrawalQueueManager} from "src/interfaces/IWithdrawalQueueManager.sol";
import {IwstETH} from "src/external/lido/IwstETH.sol";
import {IDelegationManagerExtended} from "src/external/eigenlayer/IDelegationManagerExtended.sol";
import {IDelegationManagerTypes} from "lib/eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";

import "./ynLSDeScenarioBaseTest.sol";

contract YnEigenDelegationScenarioTest is ynLSDeScenarioBaseTest {

    function test_undelegate_Scenario_undelegateByOperator1() public {
        updateTokenStakingNodesBalancesForAllAssets();

        // Log total assets before undelegation
        uint256 totalAssetsBefore = yneigen.totalAssets();

        ITokenStakingNode stakingNode = tokenStakingNodesManager.nodes(0);

        // Get operator for node 0
        address operator = delegationManager.delegatedTo(address(stakingNode));

        uint32 blockNumberBefore = uint32(block.number);
        uint256 nonceBefore = delegationManager.cumulativeWithdrawalsQueued(address(stakingNode));

        // Get strategies and shares before undelegating
        (IStrategy[] memory strategies,) = delegationManager.getDepositedShares(address(stakingNode));
        (uint256[] memory shares,) = delegationManager.getWithdrawableShares(address(stakingNode), strategies);

        uint256[] memory queuedSharesBefore = new uint256[](strategies.length);
        for (uint256 i = 0; i < strategies.length; i++) {
            queuedSharesBefore[i] = stakingNode.queuedShares(strategies[i]);
        }

        // Call undelegate from operator
        vm.startPrank(operator);
        bytes32[] memory withdrawalRoots = delegationManager.undelegate(address(stakingNode));
        vm.stopPrank();

        uint256 nonceAfter = delegationManager.cumulativeWithdrawalsQueued(address(stakingNode));

        // Assert node is no longer delegated after undelegation
        assertEq(
            delegationManager.delegatedTo(address(stakingNode)),
            address(0),
            "Node should not be delegated after undelegation"
        );

        // Assert total assets remain unchanged after undelegation
        assertEq(totalAssetsBefore, yneigen.totalAssets(), "Total assets should not change after undelegation");

        // Assert node is not synchronized after undelegation
        assertFalse(stakingNode.isSynchronized(), "Node should not be synchronized after undelegation");

        //Call synchronize after verifying not synchronized
        vm.prank(actors.admin.STAKING_NODES_DELEGATOR);
        stakingNode.synchronize(shares, blockNumberBefore, strategies);

        for (uint256 i = 0; i < strategies.length; i++) {
            assertEq(
                stakingNode.queuedShares(strategies[i]) - queuedSharesBefore[i],
                shares[i],
                "Queued shares should be equal to shares"
            );
        }

        assertApproxEqAbs(
            totalAssetsBefore, yneigen.totalAssets(), 10, "Total assets should not change after synchronization"
        );

        // Complete queued withdrawals as shares
        IDelegationManager.Withdrawal[] memory withdrawals = new IDelegationManager.Withdrawal[](strategies.length);
        uint256[] memory middlewareTimesIndexes = new uint256[](strategies.length);
        for (uint256 i = 0; i < strategies.length; i++) {
            IStrategy[] memory singleStrategy = new IStrategy[](1);
            singleStrategy[0] = strategies[i];
            uint256[] memory singleShare = new uint256[](1);
            singleShare[0] = shares[i];
            address _Staker = address(stakingNode);
            withdrawals[i] = IDelegationManagerTypes.Withdrawal({
                staker: _Staker,
                delegatedTo: operator,
                withdrawer: _Staker,
                nonce: nonceBefore + i,
                startBlock: blockNumberBefore,
                strategies: singleStrategy,
                scaledShares: singleShare
            });
            middlewareTimesIndexes[i] = 0;
        }
        //  advance time to allow completion
        vm.roll(block.number + delegationManager.minWithdrawalDelayBlocks() + 1);

        vm.prank(actors.admin.STAKING_NODES_DELEGATOR);
        stakingNode.completeQueuedWithdrawalsAsShares(withdrawals, middlewareTimesIndexes);

        for (uint256 i = 0; i < strategies.length; i++) {
            assertEq(
                stakingNode.queuedShares(strategies[i]),
                queuedSharesBefore[i],
                "Queued shares should be reinvested after completion of withdrawals"
            );
        }
        assertApproxEqAbs(
            totalAssetsBefore, yneigen.totalAssets(), 10, "Total assets should not change after synchronization"
        );
    }

    function test_undelegate_Scenario_undelegateByDelegator() public {
        updateTokenStakingNodesBalancesForAllAssets();
        uint256 totalAssetsBefore = yneigen.totalAssets();

        ITokenStakingNode tokenStakingNode = tokenStakingNodesManager.nodes(0);

        uint256 undelegateBlockNumber = uint32(block.number);

        // Call undelegate from delegator
        vm.startPrank(actors.admin.STAKING_NODES_DELEGATOR);
        tokenStakingNode.undelegate();
        vm.stopPrank();

        // Assert node is no longer delegated after undelegation
        assertEq(
            delegationManager.delegatedTo(address(tokenStakingNode)),
            address(0),
            "Node should not be delegated after undelegation"
        );
        assertTrue(tokenStakingNode.isSynchronized(), "Node should be synchronized after undelegation");
        assertApproxEqAbs(
            totalAssetsBefore, yneigen.totalAssets(), 10, "Total assets should not change after undelegation"
        );

        // Call synchronize after verifying synchronized
        vm.expectRevert(TokenStakingNode.AlreadySynchronized.selector);
        vm.prank(actors.admin.STAKING_NODES_DELEGATOR);
        tokenStakingNode.synchronize(new uint256[](0), uint32(block.number), new IStrategy[](0));
    }

}
