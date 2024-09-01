// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IEigenPod} from "lib/eigenlayer-contracts/src/contracts/interfaces/IEigenPod.sol";

import {IStakingNode} from "../../../src/interfaces/IStakingNode.sol";
import {IStakingNodesManager} from "../../../src/interfaces/IStakingNodesManager.sol";
import {IWithdrawalQueueManager} from "../../../src/interfaces/IWithdrawalQueueManager.sol";

import "./Base.t.sol";

interface IPod {
    function verifyWithdrawalCredentials(uint64 beaconTimestamp, BeaconChainProofs.StateRootProof calldata stateRootProof, uint40[] calldata validatorIndices, bytes[] calldata validatorFieldsProofs, bytes32[][] calldata validatorFields) external;
    function verifyCheckpointProofs(BeaconChainProofs.BalanceContainerProof calldata balanceContainerProof, BeaconChainProofs.BalanceProof[] calldata proofs) external;
}

interface IStakingNodeVars {
    function queuedSharesAmount() external view returns (uint256);
    function withdrawnETH() external view returns (uint256);
}

contract M3WithdrawalsTest is Base {

    address public user;

    uint40 public validatorIndex;
    uint40[] validatorIndices;
    uint256 public nodeId;

    uint256 public amount;

    //
    // setup
    //

    function setUp() public override {
        super.setUp();
    }

    function test_userWithdrawalWithRewards_Scenario_1() public {
        amount = 100 ether;

        // deposit 100 ETH into ynETH
        {
            user = vm.addr(420);
            vm.deal(user, amount);
            vm.prank(user);
            yneth.depositETH{value: amount}(user);
        }
        // create staking node
        {
            vm.prank(actors.ops.STAKING_NODE_CREATOR);
            stakingNodesManager.createStakingNode();
            nodeId = stakingNodesManager.nodesLength() - 1;
        }

        // Calculate validator count based on amount
        uint256 validatorCount = amount / 32 ether;

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


        // exit validators
        {
            // IStrategy[] memory _strategies = new IStrategy[](1);
            // _strategies[0] = IStrategy(0xbeaC0eeEeeeeEEeEeEEEEeeEEeEeeeEeeEEBEaC0); // beacon chain eth strat
            // vm.roll(block.number + delegationManager.getWithdrawalDelay(_strategies));

            for (uint256 i = 0; i < validatorIndices.length; i++) {
                beaconChain.exitValidator(validatorIndices[i]);
            }
            beaconChain.advanceEpoch_NoRewards();
        }

        // start checkpoint
        {
            vm.startPrank(actors.ops.STAKING_NODES_OPERATOR);
            stakingNodesManager.nodes(nodeId).startCheckpoint(true);
            vm.stopPrank();
        }

        // verify checkpoints
        // {
        //     uint40[] memory _validators = new uint40[](1);
        //     _validators[0] = validatorIndex;
        //     IStakingNode _node = stakingNodesManager.nodes(nodeId);
        //     CheckpointProofs memory _cpProofs = beaconChain.getCheckpointProofs(_validators, _node.eigenPod().currentCheckpointTimestamp());
        //     IPod(address(_node.eigenPod())).verifyCheckpointProofs({
        //         balanceContainerProof: _cpProofs.balanceContainerProof,
        //         proofs: _cpProofs.balanceProofs
        //     });

        // }

        // // queue withdrawals
        // {
        //     vm.startPrank(actors.ops.STAKING_NODES_OPERATOR);
        //     stakingNodesManager.nodes(nodeId).queueWithdrawals(amount);
        //     vm.stopPrank();

        //     // check that queuedSharesAmount is 100 ETH (amount)
        //     _testQueueWithdrawals();
        // }

        // // create Withdrawal struct
        // IDelegationManager.Withdrawal[] memory _withdrawals = new IDelegationManager.Withdrawal[](1);
        // {
        //     uint256[] memory _shares = new uint256[](1);
        //     _shares[0] = amount;
        //     IStrategy[] memory _strategies = new IStrategy[](1);
        //     _strategies[0] = IStrategy(0xbeaC0eeEeeeeEEeEeEEEEeeEEeEeeeEeeEEBEaC0); // beacon chain eth strat
        //     address _stakingNode = address(stakingNodesManager.nodes(nodeId));
        //     _withdrawals[0] = IDelegationManager.Withdrawal({
        //         staker: _stakingNode,
        //         delegatedTo: delegationManager.delegatedTo(_stakingNode),
        //         withdrawer: _stakingNode,
        //         nonce: delegationManager.cumulativeWithdrawalsQueued(_stakingNode) - 1,
        //         startBlock: uint32(block.number),
        //         strategies: _strategies,
        //         shares: _shares
        //     });   
        // }

        // // exit validators
        // {
        //     IStrategy[] memory _strategies = new IStrategy[](1);
        //     _strategies[0] = IStrategy(0xbeaC0eeEeeeeEEeEeEEEEeeEEeEeeeEeeEEBEaC0); // beacon chain eth strat
        //     vm.roll(block.number + delegationManager.getWithdrawalDelay(_strategies));
        //     beaconChain.exitValidator(validatorIndex);
        //     beaconChain.advanceEpoch_NoRewards();
        // }

        // // start checkpoint
        // {
        //     vm.startPrank(actors.ops.STAKING_NODES_OPERATOR);
        //     stakingNodesManager.nodes(nodeId).startCheckpoint(true);
        //     vm.stopPrank();

        //     // make sure startCheckpoint cant be called again, which means that the checkpoint has started
        //     _testStartCheckpoint();
        // }

        // // verify checkpoints after withdrawal request
        // {
        //     uint40[] memory _validators = new uint40[](1);
        //     _validators[0] = validatorIndex;
        //     IStakingNode _node = stakingNodesManager.nodes(nodeId);
        //     CheckpointProofs memory _cpProofs = beaconChain.getCheckpointProofs(_validators, _node.eigenPod().currentCheckpointTimestamp());
        //     IPod(address(_node.eigenPod())).verifyCheckpointProofs({
        //         balanceContainerProof: _cpProofs.balanceContainerProof,
        //         proofs: _cpProofs.balanceProofs
        //     });

        //     // check that proofsRemaining is 0 and podOwnerShares is still 100 ETH (amount)
        //     _testVerifyCheckpointsAfterWithdrawalRequest();
        // }

        // // complete queued withdrawals
        // {
        //     vm.startPrank(actors.ops.STAKING_NODES_OPERATOR);
        //     stakingNodesManager.nodes(nodeId).completeQueuedWithdrawals();
        //     vm.stopPrank();

        //     // check that balance is 100 ETH (amount) and queuedSharesAmount is 0
        //     _testCompleteQueuedWithdrawals();
        // }

        // // process principal withdrawals
        // {
        //     uint256 _ynethBalanceBefore = yneth.totalDepositedInPool();
        //     stakingNodesManager.processPrincipalWithdrawals(_withdrawals);

        //     // check that yneth balance and ynETHRedemptionAssetsVaultInstance balance are updated correctly
        //     _testProcessPrincipalWithdrawals(_ynethBalanceBefore);
        // }

        // // finalize requests and claim withdrawal
        // {
        //     uint256 _tokenId = testRequestWithdrawal(amount);
        //     uint256 _userETHBalanceBefore = address(user).balance;
        //     uint256 _expectedAmountOut = yneth.previewRedeem(amount);
        //     uint256 _expectedAmountOutUser = _expectedAmountOut;
        //     uint256 _expectedAmountOutFeeReceiver;
        //     if (ynETHWithdrawalQueueManager.withdrawalFee() > 0) {
        //         uint256 _feeAmount = _expectedAmountOut * ynETHWithdrawalQueueManager.withdrawalFee() / ynETHWithdrawalQueueManager.FEE_PRECISION();
        //         _expectedAmountOutUser = _expectedAmountOut - _feeAmount;
        //         _expectedAmountOutFeeReceiver = _feeAmount;
        //     }
        //     uint256 _feeReceiverETHBalanceBefore = ynETHWithdrawalQueueManager.feeReceiver().balance;
        //     uint256 _withdrawalQueueManagerBalanceBefore = yneth.balanceOf(address(ynETHWithdrawalQueueManager));

        //     testWithdraw(); // process the withdrawal
        //     vm.prank(actors.ops.REQUEST_FINALIZER);
        //     ynETHWithdrawalQueueManager.finalizeRequestsUpToIndex(_tokenId + 1);

        //     vm.prank(user);
        //     ynETHWithdrawalQueueManager.claimWithdrawal(_tokenId, user);

        //     IWithdrawalQueueManager.WithdrawalRequest memory _withdrawalRequest = ynETHWithdrawalQueueManager.withdrawalRequest(_tokenId);
        //     assertEq(_withdrawalRequest.processed, true, "testClaimWithdrawal: E0");
        //     assertEq(yneth.balanceOf(address(ynETHWithdrawalQueueManager)), _withdrawalQueueManagerBalanceBefore - amount, "testClaimWithdrawal: E1");
        //     assertApproxEqAbs(address(user).balance, _userETHBalanceBefore + _expectedAmountOutUser, 10_000, "testClaimWithdrawal: E2");
        //     assertApproxEqAbs(ynETHWithdrawalQueueManager.feeReceiver().balance, _feeReceiverETHBalanceBefore + _expectedAmountOutFeeReceiver, 10_000, "testClaimWithdrawal: E3");
        // }
    }
}