// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IEigenPod} from "lib/eigenlayer-contracts/src/contracts/interfaces/IEigenPod.sol";
import {Math} from "lib/openzeppelin-contracts/contracts/utils/math/Math.sol";

import {IStakingNode} from "src/interfaces/IStakingNode.sol";
import {IStakingNodesManager} from "src/interfaces/IStakingNodesManager.sol";
import {IWithdrawalQueueManager} from "src/interfaces/IWithdrawalQueueManager.sol";
import {BeaconChainMock, BeaconChainProofs, CheckpointProofs, CredentialProofs, EigenPodManager} from "lib/eigenlayer-contracts/src/test/integration/mocks/BeaconChainMock.t.sol";
import {Utils} from "script/Utils.sol";
import {ContractAddresses} from "script/ContractAddresses.sol";
import {ActorAddresses} from "script/Actors.sol";
import {BeaconChainMock} from "lib/eigenlayer-contracts/src/test/integration/mocks/BeaconChainMock.t.sol";

import {WithdrawalsScenarioTestBase, IPod, IStakingNodeVars} from "./WithdrawalsScenarioTestBase.sol";

contract M3WithdrawalsWithRewardsTest is WithdrawalsScenarioTestBase {

    address public user = vm.addr(420);

    uint256 public amount;
    uint40[] validatorIndices;
    uint256 public nodeId;

    function setUp() public override {
        super.setUp();
    }

    function registerVerifiedValidators(
       uint256 totalDepositAmountInNewNode
    ) private returns (TestState memory state) {
        (state, nodeId, amount, validatorIndices) = super.registerVerifiedValidators(user, totalDepositAmountInNewNode);
    }

    function startAndVerifyCheckpoint(uint256 _nodeId, TestState memory state) private {
        super.startAndVerifyCheckpoint(_nodeId, state, validatorIndices);
    }

    function test_userWithdrawalWithRewards_Scenario_1() public {

        // deposit 100 ETH into ynETH
        TestState memory state = registerVerifiedValidators(100 ether);

        uint256 accumulatedRewards;
        {
            uint256 epochCount = 30;
            // Advance the beacon chain by 100 epochs to simulate rewards accumulation
            for (uint256 i = 0; i < epochCount; i++) {
                beaconChain.advanceEpoch();
            }
            accumulatedRewards += state.validatorCount * epochCount * 1e9; // 1 GWEI per Epoch per Validator
        }


        // exit validators
        {
            for (uint256 i = 0; i < validatorIndices.length; i++) {
                beaconChain.exitValidator(validatorIndices[i]);
            }
            beaconChain.advanceEpoch();
        }

        runSystemStateInvariants(state.totalAssetsBefore, state.totalSupplyBefore, state.stakingNodeBalancesBefore);

        startAndVerifyCheckpoint(nodeId, state);

        // Rewards accumulated are accounted after verifying the checkpoint
        state.totalAssetsBefore += accumulatedRewards;
        state.stakingNodeBalancesBefore[nodeId] += accumulatedRewards;

        runSystemStateInvariants(state.totalAssetsBefore, state.totalSupplyBefore, state.stakingNodeBalancesBefore);

        uint256 withdrawnAmount = 32 ether * validatorIndices.length + accumulatedRewards;

        // queue withdrawals
        {
            vm.startPrank(actors.ops.STAKING_NODES_WITHDRAWER);
            stakingNodesManager.nodes(nodeId).queueWithdrawals(withdrawnAmount);
            vm.stopPrank();
        }

        runSystemStateInvariants(state.totalAssetsBefore, state.totalSupplyBefore, state.stakingNodeBalancesBefore);

        QueuedWithdrawalInfo[] memory withdrawalInfos = new QueuedWithdrawalInfo[](1);
        withdrawalInfos[0] = QueuedWithdrawalInfo({
            nodeId: nodeId,
            withdrawnAmount: withdrawnAmount
        });
        completeQueuedWithdrawals(nodeId, withdrawalInfos);

        runSystemStateInvariants(state.totalAssetsBefore, state.totalSupplyBefore, state.stakingNodeBalancesBefore);

        uint256 userWithdrawalAmount = 90 ether;
        uint256 amountToReinvest = withdrawnAmount - userWithdrawalAmount - accumulatedRewards;

        {
            IStakingNodesManager.WithdrawalAction[] memory _actions = new IStakingNodesManager.WithdrawalAction[](1);
            _actions[0] = IStakingNodesManager.WithdrawalAction({
                nodeId: nodeId,
                amountToReinvest: amountToReinvest,
                amountToQueue: userWithdrawalAmount,
                rewardsAmount: accumulatedRewards
            });
            vm.prank(actors.ops.WITHDRAWAL_MANAGER);
            stakingNodesManager.processPrincipalWithdrawals({
                actions: _actions
            });
        }

        {
            // Calculate fee for accumulated rewards
            uint256 feesBasisPoints = rewardsDistributor.feesBasisPoints();
            uint256 _BASIS_POINTS_DENOMINATOR = 10_000; // Assuming this is the denominator used in RewardsDistributor
            uint256 fees = Math.mulDiv(feesBasisPoints, accumulatedRewards, _BASIS_POINTS_DENOMINATOR);
            
            // Fees on accumulated rewards are substracted from the totalAssets and set to feeReceiver
            state.totalAssetsBefore -= fees;
            // The Balance of the stakingNode decreases by the total amount withdrawn
            state.stakingNodeBalancesBefore[nodeId] -= (amountToReinvest + userWithdrawalAmount + accumulatedRewards);
        }

        runSystemStateInvariants(state.totalAssetsBefore, state.totalSupplyBefore, state.stakingNodeBalancesBefore);

        // Calculate user ynETH amount to redeem
        uint256 userYnETHToRedeem = yneth.previewDeposit(userWithdrawalAmount);
        
        // Ensure user has enough ynETH balance
        require(yneth.balanceOf(user) >= userYnETHToRedeem, "User doesn't have enough ynETH balance");

        vm.startPrank(user);
        yneth.approve(address(ynETHWithdrawalQueueManager), userYnETHToRedeem);
        uint256 _tokenId = ynETHWithdrawalQueueManager.requestWithdrawal(userYnETHToRedeem);
        vm.stopPrank();

        vm.prank(actors.ops.REQUEST_FINALIZER);
        uint256 finalizationId = ynETHWithdrawalQueueManager.finalizeRequestsUpToIndex(_tokenId + 1);

        uint256 userBalanceBefore = user.balance;
        vm.prank(user);

        ynETHWithdrawalQueueManager.claimWithdrawal(
            IWithdrawalQueueManager.WithdrawalClaim({
                finalizationId: finalizationId,
                tokenId: _tokenId,
                receiver: user
            })
        );
        uint256 userBalanceAfter = user.balance;
        uint256 actualWithdrawnAmount = userBalanceAfter - userBalanceBefore;
        // Calculate expected withdrawal amount after fee
        uint256 withdrawalFee = ynETHWithdrawalQueueManager.withdrawalFee();
        uint256 expectedWithdrawnAmount = userWithdrawalAmount - (userWithdrawalAmount * withdrawalFee / ynETHWithdrawalQueueManager.FEE_PRECISION());
        
        assertApproxEqAbs(actualWithdrawnAmount, expectedWithdrawnAmount, 1e9, "User did not receive expected ETH amount after fee");

    }

    function test_userWithdrawalWithRewards_Scenario_2_queueWithdrawalsBeforeValidatorExit_with_WithdrawalsProcessor() public {

        // deposit 100 ETH into ynETH
        TestState memory state = registerVerifiedValidators(100 ether);

        uint256 accumulatedRewards;
        {
            uint256 epochCount = 30;
            // Advance the beacon chain by 100 epochs to simulate rewards accumulation
            for (uint256 i = 0; i < epochCount; i++) {
                beaconChain.advanceEpoch();
            }

            accumulatedRewards += state.validatorCount * epochCount * 1e9; // 1 GWEI per Epoch per Validator
        }

        // NOTE: Withdrawal is Queued BEFORE exiting validators. does not include rewards in this case.

        uint256 withdrawnAmount = 32 ether * validatorIndices.length;

        // queue withdrawals
        {
            vm.startPrank(actors.ops.STAKING_NODES_WITHDRAWER);
            stakingNodesManager.nodes(nodeId).queueWithdrawals(withdrawnAmount);
            vm.stopPrank();
        }

        // exit validators
        {
            for (uint256 i = 0; i < validatorIndices.length; i++) {
                beaconChain.exitValidator(validatorIndices[i]);
            }
            beaconChain.advanceEpoch();
        }

        runSystemStateInvariants(state.totalAssetsBefore, state.totalSupplyBefore, state.stakingNodeBalancesBefore);

        startAndVerifyCheckpoint(nodeId, state);

        // Rewards accumulated are accounted after verifying the checkpoint
        state.totalAssetsBefore += accumulatedRewards;
        state.stakingNodeBalancesBefore[nodeId] += accumulatedRewards;
        runSystemStateInvariants(state.totalAssetsBefore, state.totalSupplyBefore, state.stakingNodeBalancesBefore);

        uint256 userWithdrawalAmount = 90 ether;
        uint256 amountToReinvest = withdrawnAmount - userWithdrawalAmount - accumulatedRewards;

        {
            IStakingNodesManager.WithdrawalAction memory withdrawalAction = IStakingNodesManager.WithdrawalAction({
                nodeId: nodeId,
                amountToReinvest: amountToReinvest,
                amountToQueue: userWithdrawalAmount,
                rewardsAmount: accumulatedRewards
            });
            QueuedWithdrawalInfo[] memory withdrawalInfos = new QueuedWithdrawalInfo[](1);
            withdrawalInfos[0] = QueuedWithdrawalInfo({
                nodeId: nodeId,
                withdrawnAmount: withdrawnAmount
            });

            completeAndProcessWithdrawals(withdrawalAction, withdrawalInfos);
        }

        {
            // Calculate fee for accumulated rewards
            uint256 feesBasisPoints = rewardsDistributor.feesBasisPoints();
            uint256 _BASIS_POINTS_DENOMINATOR = 10_000; // Assuming this is the denominator used in RewardsDistributor
            uint256 fees = Math.mulDiv(feesBasisPoints, accumulatedRewards, _BASIS_POINTS_DENOMINATOR);
            
            // Fees on accumulated rewards are substracted from the totalAssets and set to feeReceiver
            state.totalAssetsBefore -= fees;
            // The Balance of the stakingNode decreases by the total amount withdrawn
            state.stakingNodeBalancesBefore[nodeId] -= (amountToReinvest + userWithdrawalAmount + accumulatedRewards);
        }

        runSystemStateInvariants(state.totalAssetsBefore, state.totalSupplyBefore, state.stakingNodeBalancesBefore);

        // Calculate user ynETH amount to redeem
        uint256 userYnETHToRedeem = yneth.previewDeposit(userWithdrawalAmount);
        
        // Ensure user has enough ynETH balance
        require(yneth.balanceOf(user) >= userYnETHToRedeem, "User doesn't have enough ynETH balance");

        vm.startPrank(user);
        yneth.approve(address(ynETHWithdrawalQueueManager), userYnETHToRedeem);
        uint256 _tokenId = ynETHWithdrawalQueueManager.requestWithdrawal(userYnETHToRedeem);
        vm.stopPrank();

        vm.prank(actors.ops.REQUEST_FINALIZER);
        uint256 finalizationId = ynETHWithdrawalQueueManager.finalizeRequestsUpToIndex(_tokenId + 1);

        uint256 userBalanceBefore = user.balance;
        vm.prank(user);

        ynETHWithdrawalQueueManager.claimWithdrawal(
            IWithdrawalQueueManager.WithdrawalClaim({
                finalizationId: finalizationId,
                tokenId: _tokenId,
                receiver: user
            })
        );
        uint256 userBalanceAfter = user.balance;
        uint256 actualWithdrawnAmount = userBalanceAfter - userBalanceBefore;
        // Calculate expected withdrawal amount after fee
        uint256 withdrawalFee = ynETHWithdrawalQueueManager.withdrawalFee();
        uint256 expectedWithdrawnAmount = userWithdrawalAmount - (userWithdrawalAmount * withdrawalFee / ynETHWithdrawalQueueManager.FEE_PRECISION());
        
        assertApproxEqAbs(actualWithdrawnAmount, expectedWithdrawnAmount, 1e9, "User did not receive expected ETH amount after fee");

    }


    function test_userWithdrawalWithRewards_Scenario_2_queueWithdrawalsBeforeValidatorExit() public {

        // deposit 100 ETH into ynETH
        TestState memory state = registerVerifiedValidators(100 ether);

        uint256 accumulatedRewards;
        {
            uint256 epochCount = 30;
            // Advance the beacon chain by 100 epochs to simulate rewards accumulation
            for (uint256 i = 0; i < epochCount; i++) {
                beaconChain.advanceEpoch();
            }

            accumulatedRewards += state.validatorCount * epochCount * 1e9; // 1 GWEI per Epoch per Validator
        }

        // NOTE: Withdrawal is Queued BEFORE exiting validators. does not include rewards in this case.

        uint256 withdrawnAmount = 32 ether * validatorIndices.length;

        // queue withdrawals
        {
            vm.startPrank(actors.ops.STAKING_NODES_WITHDRAWER);
            stakingNodesManager.nodes(nodeId).queueWithdrawals(withdrawnAmount);
            vm.stopPrank();
        }

        // exit validators
        {
            for (uint256 i = 0; i < validatorIndices.length; i++) {
                beaconChain.exitValidator(validatorIndices[i]);
            }
            beaconChain.advanceEpoch();
        }

        runSystemStateInvariants(state.totalAssetsBefore, state.totalSupplyBefore, state.stakingNodeBalancesBefore);

        startAndVerifyCheckpoint(nodeId, state);

        // Rewards accumulated are accounted after verifying the checkpoint
        state.totalAssetsBefore += accumulatedRewards;
        state.stakingNodeBalancesBefore[nodeId] += accumulatedRewards;
        runSystemStateInvariants(state.totalAssetsBefore, state.totalSupplyBefore, state.stakingNodeBalancesBefore);


        QueuedWithdrawalInfo[] memory withdrawalInfos = new QueuedWithdrawalInfo[](1);
        withdrawalInfos[0] = QueuedWithdrawalInfo({
            nodeId: nodeId,
            withdrawnAmount: withdrawnAmount
        });
        completeQueuedWithdrawals(nodeId, withdrawalInfos);

        runSystemStateInvariants(state.totalAssetsBefore, state.totalSupplyBefore, state.stakingNodeBalancesBefore);

        uint256 userWithdrawalAmount = 90 ether;
        uint256 amountToReinvest = withdrawnAmount - userWithdrawalAmount - accumulatedRewards;

        {
            IStakingNodesManager.WithdrawalAction[] memory _actions = new IStakingNodesManager.WithdrawalAction[](1);
            _actions[0] = IStakingNodesManager.WithdrawalAction({
                nodeId: nodeId,
                amountToReinvest: amountToReinvest,
                amountToQueue: userWithdrawalAmount,
                rewardsAmount: accumulatedRewards
            });
            vm.prank(actors.ops.WITHDRAWAL_MANAGER);
            stakingNodesManager.processPrincipalWithdrawals({
                actions: _actions
            });
        }

        {
            // Calculate fee for accumulated rewards
            uint256 feesBasisPoints = rewardsDistributor.feesBasisPoints();
            uint256 _BASIS_POINTS_DENOMINATOR = 10_000; // Assuming this is the denominator used in RewardsDistributor
            uint256 fees = Math.mulDiv(feesBasisPoints, accumulatedRewards, _BASIS_POINTS_DENOMINATOR);
            
            // Fees on accumulated rewards are substracted from the totalAssets and set to feeReceiver
            state.totalAssetsBefore -= fees;
            // The Balance of the stakingNode decreases by the total amount withdrawn
            state.stakingNodeBalancesBefore[nodeId] -= (amountToReinvest + userWithdrawalAmount + accumulatedRewards);
        }

        runSystemStateInvariants(state.totalAssetsBefore, state.totalSupplyBefore, state.stakingNodeBalancesBefore);

        // Calculate user ynETH amount to redeem
        uint256 userYnETHToRedeem = yneth.previewDeposit(userWithdrawalAmount);
        
        // Ensure user has enough ynETH balance
        require(yneth.balanceOf(user) >= userYnETHToRedeem, "User doesn't have enough ynETH balance");

        vm.startPrank(user);
        yneth.approve(address(ynETHWithdrawalQueueManager), userYnETHToRedeem);
        uint256 _tokenId = ynETHWithdrawalQueueManager.requestWithdrawal(userYnETHToRedeem);
        vm.stopPrank();

        vm.prank(actors.ops.REQUEST_FINALIZER);
        uint256 finalizationId = ynETHWithdrawalQueueManager.finalizeRequestsUpToIndex(_tokenId + 1);

        uint256 userBalanceBefore = user.balance;
        vm.prank(user);

        ynETHWithdrawalQueueManager.claimWithdrawal(
            IWithdrawalQueueManager.WithdrawalClaim({
                finalizationId: finalizationId,
                tokenId: _tokenId,
                receiver: user
            })
        );
        uint256 userBalanceAfter = user.balance;
        uint256 actualWithdrawnAmount = userBalanceAfter - userBalanceBefore;
        // Calculate expected withdrawal amount after fee
        uint256 withdrawalFee = ynETHWithdrawalQueueManager.withdrawalFee();
        uint256 expectedWithdrawnAmount = userWithdrawalAmount - (userWithdrawalAmount * withdrawalFee / ynETHWithdrawalQueueManager.FEE_PRECISION());
        
        assertApproxEqAbs(actualWithdrawnAmount, expectedWithdrawnAmount, 1e9, "User did not receive expected ETH amount after fee");

    }

    function test_userWithdrawalWithRewards_Scenario_3_withdrawEverything() public {

        // exactly 2 validators
        TestState memory state = registerVerifiedValidators(64 ether);

        uint256 accumulatedRewards;
        {
            uint256 epochCount = 30;
            // Advance the beacon chain by 100 epochs to simulate rewards accumulation
            for (uint256 i = 0; i < epochCount; i++) {
                beaconChain.advanceEpoch();
            }

            accumulatedRewards += state.validatorCount * epochCount * 1e9; // 1 GWEI per Epoch per Validator
        }

        // NOTE: Withdrawal is Queued BEFORE exiting validators. does not include rewards in this case.

        uint256 withdrawnAmount = amount;

        // queue withdrawals
        {
            vm.startPrank(actors.ops.STAKING_NODES_WITHDRAWER);
            stakingNodesManager.nodes(nodeId).queueWithdrawals(withdrawnAmount);
            vm.stopPrank();
        }

        // exit validators
        {
            for (uint256 i = 0; i < validatorIndices.length; i++) {
                beaconChain.exitValidator(validatorIndices[i]);
            }
            beaconChain.advanceEpoch();
        }

        runSystemStateInvariants(state.totalAssetsBefore, state.totalSupplyBefore, state.stakingNodeBalancesBefore);

        startAndVerifyCheckpoint(nodeId, state);

        // Rewards accumulated are accounted after verifying the checkpoint
        state.totalAssetsBefore += accumulatedRewards;
        state.stakingNodeBalancesBefore[nodeId] += accumulatedRewards;
        runSystemStateInvariants(state.totalAssetsBefore, state.totalSupplyBefore, state.stakingNodeBalancesBefore);


        QueuedWithdrawalInfo[] memory withdrawalInfos = new QueuedWithdrawalInfo[](1);
        withdrawalInfos[0] = QueuedWithdrawalInfo({
            nodeId: nodeId,
            withdrawnAmount: withdrawnAmount
        });
        completeQueuedWithdrawals(nodeId, withdrawalInfos);

        runSystemStateInvariants(state.totalAssetsBefore, state.totalSupplyBefore, state.stakingNodeBalancesBefore);
        
        // Assert that the node's podOwnerShares is accumulatedRewards after completing withdrawals
        assertEq(
            eigenPodManager.podOwnerDepositShares(address(stakingNodesManager.nodes(nodeId))),
            int256(accumulatedRewards),
            "Node's podOwnerShares should be 0 after completing withdrawals"
        );
    }

    function test_userWithdrawalWithRewards_Scenario_4_slashAllValidatorsAndWithdrawEverything() public {

        // exactly 2 validators
        TestState memory state = registerVerifiedValidators(64 ether);

        uint256 accumulatedRewards;
        {
            uint256 epochCount = 30;
            // Advance the beacon chain by 100 epochs to simulate rewards accumulation
            for (uint256 i = 0; i < epochCount; i++) {
                beaconChain.advanceEpoch();
            }

            accumulatedRewards += state.validatorCount * epochCount * 1e9; // 1 GWEI per Epoch per Validator
        }

        uint256 withdrawnAmount = amount;

        // NOTE: This triggers the a exit of all validators
        beaconChain.slashValidators(validatorIndices, BeaconChainMock.SlashType.Minor);
        beaconChain.advanceEpoch();

        // queue withdrawals
        {
            vm.startPrank(actors.ops.STAKING_NODES_WITHDRAWER);
            stakingNodesManager.nodes(nodeId).queueWithdrawals(withdrawnAmount);
            vm.stopPrank();
        }

        runSystemStateInvariants(state.totalAssetsBefore, state.totalSupplyBefore, state.stakingNodeBalancesBefore);

        startAndVerifyCheckpoint(nodeId, state);

        uint256 totalSlashAmount = beaconChain.MINOR_SLASH_AMOUNT_GWEI() * state.validatorCount * 1e9;
        state.totalAssetsBefore = state.totalAssetsBefore + accumulatedRewards - totalSlashAmount;
        state.stakingNodeBalancesBefore[nodeId] = state.stakingNodeBalancesBefore[nodeId] + accumulatedRewards - totalSlashAmount;
        runSystemStateInvariants(state.totalAssetsBefore, state.totalSupplyBefore, state.stakingNodeBalancesBefore);

        QueuedWithdrawalInfo[] memory withdrawalInfos = new QueuedWithdrawalInfo[](1);
        withdrawalInfos[0] = QueuedWithdrawalInfo({
            nodeId: nodeId,
            withdrawnAmount: withdrawnAmount
        });
        completeQueuedWithdrawals(nodeId, withdrawalInfos);

        runSystemStateInvariants(state.totalAssetsBefore, state.totalSupplyBefore, state.stakingNodeBalancesBefore);
    }

    function test_userWithdrawalWithRewards_Scenario_4_slashAllValidatorsWithNoRewardsAndWithdrawEverything() public {

        // exactly 2 validators
        TestState memory state = registerVerifiedValidators(64 ether);

        uint256 withdrawnAmount = amount;

        // NOTE: This triggers the a exit of all validators
        beaconChain.slashValidators(validatorIndices, BeaconChainMock.SlashType.Minor);
        beaconChain.advanceEpoch();

        // queue withdrawals
        {
            vm.startPrank(actors.ops.STAKING_NODES_WITHDRAWER);
            stakingNodesManager.nodes(nodeId).queueWithdrawals(withdrawnAmount);
            vm.stopPrank();
        }

        runSystemStateInvariants(state.totalAssetsBefore, state.totalSupplyBefore, state.stakingNodeBalancesBefore);

        startAndVerifyCheckpoint(nodeId, state);

        uint256 totalSlashAmount = beaconChain.MINOR_SLASH_AMOUNT_GWEI() * state.validatorCount * 1e9;
        state.totalAssetsBefore = state.totalAssetsBefore - totalSlashAmount;
        state.stakingNodeBalancesBefore[nodeId] = state.stakingNodeBalancesBefore[nodeId] - totalSlashAmount;
        runSystemStateInvariants(state.totalAssetsBefore, state.totalSupplyBefore, state.stakingNodeBalancesBefore);

        QueuedWithdrawalInfo[] memory withdrawalInfos = new QueuedWithdrawalInfo[](1);
        withdrawalInfos[0] = QueuedWithdrawalInfo({
            nodeId: nodeId,
            withdrawnAmount: withdrawnAmount
        });
        completeQueuedWithdrawals(nodeId, withdrawalInfos);

        runSystemStateInvariants(state.totalAssetsBefore, state.totalSupplyBefore, state.stakingNodeBalancesBefore);

        // Assert that the node's queuedSharesAmount is 0 after completing withdrawals
        assertEq(
            IStakingNodeVars(address(stakingNodesManager.nodes(nodeId))).queuedSharesAmount(),
            0,
            "Node's queuedSharesAmount should be 0 after completing withdrawals"
        );
        // Assert that the node's podOwnerShares is 0
        assertEq(
            eigenPodManager.podOwnerDepositShares(address(stakingNodesManager.nodes(nodeId))),
            int256(0),
            "Node's podOwnerShares should be 0 after completing withdrawals"
        );
        // Assert that the node's withdrawnETH is equal to withdrawnAmount minus totalSlashAmount
        uint256 expectedWithdrawnETH = withdrawnAmount - totalSlashAmount;
        assertEq(
            IStakingNodeVars(address(stakingNodesManager.nodes(nodeId))).withdrawnETH(),
            expectedWithdrawnETH,
            "Node's withdrawnETH should be equal to withdrawnAmount minus totalSlashAmount"
        );
    }

    function test_userWithdrawalWithRewards_Scenario_5_slashAllValidatorsWithNoRewardsAndWithdrawEverything() public {

        // exactly 2 validators
        TestState memory state = registerVerifiedValidators(64 ether);

        uint256 withdrawnAmount = amount;

        // Validators are not slashed and no rewards are earned before queueing withdrawals.

        // queue withdrawals
        {
            vm.startPrank(actors.ops.STAKING_NODES_WITHDRAWER);
            stakingNodesManager.nodes(nodeId).queueWithdrawals(withdrawnAmount);
            vm.stopPrank();
        }

        runSystemStateInvariants(state.totalAssetsBefore, state.totalSupplyBefore, state.stakingNodeBalancesBefore);

        // Trigger slashing of validators after withdrawals were queued
        // NOTE: This triggers the a exit of all validators
        beaconChain.slashValidators(validatorIndices, BeaconChainMock.SlashType.Minor);
        beaconChain.advanceEpoch();

        startAndVerifyCheckpoint(nodeId, state);

        uint256 totalSlashAmount = beaconChain.MINOR_SLASH_AMOUNT_GWEI() * state.validatorCount * 1e9;
        state.totalAssetsBefore = state.totalAssetsBefore - totalSlashAmount;
        state.stakingNodeBalancesBefore[nodeId] = state.stakingNodeBalancesBefore[nodeId] - totalSlashAmount;
        runSystemStateInvariants(state.totalAssetsBefore, state.totalSupplyBefore, state.stakingNodeBalancesBefore);

        // Assert that the node's podOwnerShares is 0 and not negative
        assertEq(
            eigenPodManager.podOwnerDepositShares(address(stakingNodesManager.nodes(nodeId))),
            0,
            "Node's podOwnerShares should be 0 after completing withdrawals"
        );

        QueuedWithdrawalInfo[] memory withdrawalInfos = new QueuedWithdrawalInfo[](1);
        withdrawalInfos[0] = QueuedWithdrawalInfo({
            nodeId: nodeId,
            withdrawnAmount: withdrawnAmount
        });
        completeQueuedWithdrawals(nodeId, withdrawalInfos);

        runSystemStateInvariants(state.totalAssetsBefore, state.totalSupplyBefore, state.stakingNodeBalancesBefore);
    }
}