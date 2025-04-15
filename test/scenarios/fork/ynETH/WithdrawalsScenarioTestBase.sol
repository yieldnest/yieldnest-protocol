// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IDelegationManager, IDelegationManagerTypes} from "lib/eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStakingNodesManager} from "src/interfaces/IStakingNodesManager.sol";
import {IStrategy} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {BeaconChainMock, BeaconChainProofs, CheckpointProofs, CredentialProofs, EigenPodManager} from "lib/eigenlayer-contracts/src/test/integration/mocks/BeaconChainMock.t.sol";
import {IStakingNode} from "src/interfaces/IStakingNode.sol";
import {IStakingNodesManager} from "src/interfaces/IStakingNodesManager.sol";

import {Base} from "./Base.t.sol";

interface IPod {
    function verifyWithdrawalCredentials(uint64 beaconTimestamp, BeaconChainProofs.StateRootProof calldata stateRootProof, uint40[] calldata validatorIndices, bytes[] calldata validatorFieldsProofs, bytes32[][] calldata validatorFields) external;
    function verifyCheckpointProofs(BeaconChainProofs.BalanceContainerProof calldata balanceContainerProof, BeaconChainProofs.BalanceProof[] calldata proofs) external;
}

interface IStakingNodeVars {
    function queuedSharesAmount() external view returns (uint256);
    function withdrawnETH() external view returns (uint256);
}

contract WithdrawalsScenarioTestBase is Base {

    struct QueuedWithdrawalInfo {
        uint256 nodeId;
        uint256 withdrawnAmount;
    }

    struct TestState {
        uint256 totalAssetsBefore;
        uint256 totalSupplyBefore;
        uint256[] stakingNodeBalancesBefore;
        uint256 previousYnETHRedemptionAssetsVaultBalance;
        uint256 previousYnETHBalance;
        uint256 validatorCount;
    }

    function registerVerifiedValidators(
        address user, uint256 totalDepositAmountInNewNode
    ) internal returns (TestState memory state, uint256 nodeId, uint256 amount, uint40[] memory validatorIndices) {

        amount = totalDepositAmountInNewNode;
        // deposit entire amount
        {
            vm.deal(user, amount);
            vm.prank(user);
            yneth.depositETH{value: amount}(user);
        }

        // Process rewards
        rewardsDistributor.processRewards();

        // create staking node
        {
            vm.prank(actors.ops.STAKING_NODE_CREATOR);
            stakingNodesManager.createStakingNode();
            nodeId = stakingNodesManager.nodesLength() - 1;
        }

        // Calculate validator count based on amount
        uint256 validatorCount = amount / 32 ether;
        
        state = TestState({
            totalAssetsBefore: yneth.totalAssets(),
            totalSupplyBefore: yneth.totalSupply(),
            stakingNodeBalancesBefore: getAllStakingNodeBalances(),
            previousYnETHRedemptionAssetsVaultBalance: ynETHRedemptionAssetsVaultInstance.availableRedemptionAssets(),
            previousYnETHBalance: address(yneth).balance,
            validatorCount: validatorCount
        });

        // create and register validators validator
        {
            // Create an array of nodeIds with length equal to validatorCount
            uint256[] memory nodeIds = new uint256[](validatorCount);
            for (uint256 i = 0; i < validatorCount; i++) {
                nodeIds[i] = nodeId;
            }

            // Call createValidators with the nodeIds array and validatorCount
            validatorIndices = createValidators(nodeIds, 1);

            beaconChain.advanceEpoch_NoRewards();

            registerValidators(nodeIds);
        }

        state.stakingNodeBalancesBefore[nodeId] += validatorCount * 32 ether;
        runSystemStateInvariants(state.totalAssetsBefore, state.totalSupplyBefore, state.stakingNodeBalancesBefore);

        // verify withdrawal credentials
        {

            CredentialProofs memory _proofs = beaconChain.getCredentialProofs(validatorIndices);
            vm.startPrank(actors.ops.STAKING_NODES_OPERATOR);
            IPod(address(stakingNodesManager.nodes(nodeId))).verifyWithdrawalCredentials({
                beaconTimestamp: _proofs.beaconTimestamp,
                stateRootProof: _proofs.stateRootProof,
                validatorIndices: validatorIndices,
                validatorFieldsProofs: _proofs.validatorFieldsProofs,
                validatorFields: _proofs.validatorFields
            });
            vm.stopPrank();

            // check that unverifiedStakedETH is 0 and podOwnerShares is 100 ETH (amount)
            // _testVerifyWithdrawalCredentials();
        }

        runSystemStateInvariants(state.totalAssetsBefore, state.totalSupplyBefore, state.stakingNodeBalancesBefore);

    }

    function startAndVerifyCheckpoint(uint256 _nodeId, TestState memory state, uint40[] memory validatorIndices) internal {
        // start checkpoint
        {
            vm.startPrank(actors.ops.STAKING_NODES_OPERATOR);
            stakingNodesManager.nodes(_nodeId).startCheckpoint(true);
            vm.stopPrank();
        }

        runSystemStateInvariants(state.totalAssetsBefore, state.totalSupplyBefore, state.stakingNodeBalancesBefore);

        // verify checkpoints
        {
            IStakingNode _node = stakingNodesManager.nodes(_nodeId);
            CheckpointProofs memory _cpProofs = beaconChain.getCheckpointProofs(validatorIndices, _node.eigenPod().currentCheckpointTimestamp());
            IPod(address(_node.eigenPod())).verifyCheckpointProofs({
                balanceContainerProof: _cpProofs.balanceContainerProof,
                proofs: _cpProofs.balanceProofs
            });
        }
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
            vm.startPrank(actors.ops.STAKING_NODES_WITHDRAWER);
            stakingNodesManager.nodes(nodeId).completeQueuedWithdrawals(_withdrawals);
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
            vm.startPrank(actors.admin.STAKING_NODES_DELEGATOR);
            stakingNodesManager.nodes(nodeId).completeQueuedWithdrawalsAsShares(_withdrawals);
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
            vm.prank(actors.ops.WITHDRAWAL_MANAGER);
            withdrawalsProcessor.completeAndProcessWithdrawalsForNode(
                withdrawalAction,
                _withdrawals
            );
        }
    }

}
