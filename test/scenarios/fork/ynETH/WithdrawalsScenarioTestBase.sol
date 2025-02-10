// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IDelegationManager, IDelegationManagerTypes} from "lib/eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStakingNodesManager} from "src/interfaces/IStakingNodesManager.sol";
import {IStrategy} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";

import {Base} from "./Base.t.sol";

contract WithdrawalsScenarioTestBase is Base {

    struct QueuedWithdrawalInfo {
        uint256 nodeId;
        uint256 withdrawnAmount;
    }

    function getDelegationManagerWithdrawals(QueuedWithdrawalInfo[] memory queuedWithdrawals, address[] memory operators) private view returns (IDelegationManager.Withdrawal[] memory) {
        // create Withdrawal struct
        IDelegationManager.Withdrawal[] memory _withdrawals = new IDelegationManager.Withdrawal[](queuedWithdrawals.length);
        {
            for (uint256 i = 0; i < queuedWithdrawals.length; i++) {
                uint256[] memory _shares = new uint256[](1);
                _shares[0] = queuedWithdrawals[i].withdrawnAmount;
                IStrategy[] memory _strategies = new IStrategy[](1);
                _strategies[0] = IStrategy(0xbeaC0eeEeeeeEEeEeEEEEeeEEeEeeeEeeEEBEaC0); // beacon chain eth strat
                address _stakingNode = address(stakingNodesManager.nodes(queuedWithdrawals[i].nodeId));
                _withdrawals[i] = IDelegationManagerTypes.Withdrawal({
                    staker: _stakingNode,
                    delegatedTo: operators[i],
                    withdrawer: _stakingNode,
                    nonce: delegationManager.cumulativeWithdrawalsQueued(_stakingNode) - 1,
                    startBlock: uint32(block.number),
                    strategies: _strategies,
                    scaledShares: _shares
                });   
            }
        }
        
        return _withdrawals;
    }

    function completeQueuedWithdrawals(uint256 nodeId, QueuedWithdrawalInfo[] memory queuedWithdrawals) internal {

        // create Withdrawal struct
        address[] memory operators = new address[](queuedWithdrawals.length);
        for (uint256 i = 0; i < operators.length; i++) {
            address _stakingNode = address(stakingNodesManager.nodes(queuedWithdrawals[i].nodeId));
            operators[i] = delegationManager.delegatedTo(_stakingNode);
        }
        IDelegationManager.Withdrawal[] memory _withdrawals = getDelegationManagerWithdrawals(
            queuedWithdrawals,
            operators
        );

        {
            IStrategy[] memory _strategies = new IStrategy[](1);
            _strategies[0] = IStrategy(0xbeaC0eeEeeeeEEeEeEEEEeeEEeEeeeEeeEEBEaC0); // beacon chain eth strat

            // advance time to allow completion
            vm.roll(block.number + delegationManager.minWithdrawalDelayBlocks() + 1);
        }

        // complete queued withdrawals
        {
            uint256[] memory _middlewareTimesIndexes = new uint256[](_withdrawals.length);
            // all is zeroed out by defailt
            _middlewareTimesIndexes[0] = 0;
            vm.startPrank(actors.ops.STAKING_NODES_WITHDRAWER);
            stakingNodesManager.nodes(nodeId).completeQueuedWithdrawals(_withdrawals, _middlewareTimesIndexes);
            vm.stopPrank();
        }
    }

    function completeQueuedWithdrawalsAsShares(
        uint256 nodeId,
        QueuedWithdrawalInfo[] memory queuedWithdrawals,
        address[] memory operators
        ) internal {

        IDelegationManager.Withdrawal[] memory _withdrawals = getDelegationManagerWithdrawals(
            queuedWithdrawals,
            operators
        );

        {
            IStrategy[] memory _strategies = new IStrategy[](1);
            _strategies[0] = IStrategy(0xbeaC0eeEeeeeEEeEeEEEEeeEEeEeeeEeeEEBEaC0); // beacon chain eth strat

            // advance time to allow completion
            vm.roll(block.number + delegationManager.minWithdrawalDelayBlocks() + 1);
        }

        // complete queued withdrawals
        {
            uint256[] memory _middlewareTimesIndexes = new uint256[](_withdrawals.length);
            // all is zeroed out by defailt
            _middlewareTimesIndexes[0] = 0;
            vm.startPrank(actors.admin.STAKING_NODES_DELEGATOR);
            stakingNodesManager.nodes(nodeId).completeQueuedWithdrawalsAsShares(_withdrawals, _middlewareTimesIndexes);
            vm.stopPrank();
        }
    }

    function completeAndProcessWithdrawals(
        IStakingNodesManager.WithdrawalAction memory withdrawalAction,
        QueuedWithdrawalInfo[] memory queuedWithdrawals
    ) public {
        
        // create Withdrawal struct
        address[] memory operators = new address[](queuedWithdrawals.length);
        for (uint256 i = 0; i < operators.length; i++) {
            address _stakingNode = address(stakingNodesManager.nodes(queuedWithdrawals[i].nodeId));
            operators[i] = delegationManager.delegatedTo(_stakingNode);
        }
        IDelegationManager.Withdrawal[] memory _withdrawals = getDelegationManagerWithdrawals(
            queuedWithdrawals,
            operators
        );

        {
            IStrategy[] memory _strategies = new IStrategy[](1);
            _strategies[0] = IStrategy(0xbeaC0eeEeeeeEEeEeEEEEeeEEeEeeeEeeEEBEaC0); // beacon chain eth strat

            // advance time to allow completion
            vm.roll(block.number + delegationManager.minWithdrawalDelayBlocks() + 1);
        }


        {
            uint256[] memory _middlewareTimesIndexes = new uint256[](_withdrawals.length);
            vm.prank(actors.ops.WITHDRAWAL_MANAGER);
            withdrawalsProcessor.completeAndProcessWithdrawalsForNode(
                withdrawalAction,
                _withdrawals,
                _middlewareTimesIndexes
            );
        }
    }

}
