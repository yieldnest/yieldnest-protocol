
// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IStrategy} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TransparentUpgradeableProxy, ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
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


import "./ynLSDeScenarioBaseTest.sol";


contract YnEigenDelegationScenarioTest is ynLSDeScenarioBaseTest {
    
  function test_undelegate_Scenario_undelegateByOperator() public {

        updateTokenStakingNodesBalancesForAllAssets();

        // Log total assets before undelegation
        uint256 totalAssetsBefore = yneigen.totalAssets();

        ITokenStakingNode stakingNode = tokenStakingNodesManager.nodes(0);

        // Get operator for node 0
        address operator = delegationManager.delegatedTo(address(stakingNode));

        uint32 blockNumberBefore = uint32(block.number);
        
        // Get strategies and shares before undelegating
        (IStrategy[] memory strategies, uint256[] memory shares) = IDelegationManagerExtended(
            address(delegationManager)
        ).getDelegatableShares(address(stakingNode));

        // Call undelegate from operator
        vm.startPrank(operator);
        delegationManager.undelegate(address(stakingNode));
        vm.stopPrank();

        // Assert node is no longer delegated after undelegation
        assertEq(delegationManager.delegatedTo(address(stakingNode)), address(0), "Node should not be delegated after undelegation");

        // Assert total assets remain unchanged after undelegation
        assertEq(totalAssetsBefore, yneigen.totalAssets(), "Total assets should not change after undelegation");

        // Assert node is not synchronized after undelegation
        assertFalse(stakingNode.isSynchronized(), "Node should not be synchronized after undelegation");

        //Call synchronize after verifying not synchronized
        vm.prank(actors.admin.STAKING_NODES_DELEGATOR);
        stakingNode.synchronize(shares, blockNumberBefore, strategies);

        updateTokenStakingNodesBalancesForAllAssets();

        assertApproxEqAbs(totalAssetsBefore, yneigen.totalAssets(), 10, "Total assets should not change after synchronization");

        // Complete queued withdrawals as shares
        // IWithdrawalQueueManager.QueuedWithdrawalInfo[] memory queuedWithdrawals = new IWithdrawalQueueManager.QueuedWithdrawalInfo[](1);
        // queuedWithdrawals[0] = IWithdrawalQueueManager.QueuedWithdrawalInfo({
        //     nodeId: 0,
        //     withdrawnAmount: podSharesBefore
        // });
        // address[] memory operators = new address[](1);
        // operators[0] = operator;

        // uint256 queuedSharesBefore = stakingNode.getQueuedSharesAmount();

        // withdrawalQueueManager.completeQueuedWithdrawalsAsShares(0, queuedWithdrawals, operators);

        // assertEq(queuedSharesBefore - podSharesBefore, stakingNode.getQueuedSharesAmount(), "Queued shares should decrease by pod shares amount");

        // // Assert staking node balance remains unchanged after completing withdrawals
        // assertEq(stakingNodeBalanceBefore, stakingNode.getBalance(), "Staking node balance should not change after completing withdrawals");

        // tokenStakingNodesManager.updateTotalStaked();

        // // Assert total assets remain unchanged after completing withdrawals
        // assertEq(totalAssetsBefore, yneigen.totalAssets(), "Total assets should not change after completing withdrawals");
    }
}