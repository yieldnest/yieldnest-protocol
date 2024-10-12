// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IEigenPod} from "lib/eigenlayer-contracts/src/contracts/interfaces/IEigenPod.sol";
import {Math} from "lib/openzeppelin-contracts/contracts/utils/math/Math.sol";

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

contract M3WithdrawalsWithRewardsTest is Base {

    address public user;

    uint40 public validatorIndex;
    uint40[] validatorIndices;
    uint256 public nodeId;

    uint256 public amount;

    struct TestState {
        uint256 totalAssetsBefore;
        uint256 totalSupplyBefore;
        uint256[] stakingNodeBalancesBefore;
        uint256 previousYnETHRedemptionAssetsVaultBalance;
        uint256 previousYnETHBalance;
        uint256 validatorCount;
    }


    function setUp() public override {
        super.setUp();
    }

    function registerVerifiedValidators(uint256 totalDepositAmountInNewNode) internal returns (TestState memory state) {

        amount = totalDepositAmountInNewNode;
        // deposit entire amount
        {
            user = vm.addr(420);
            vm.deal(user, amount);
            vm.prank(user);
            yneth.depositETH{value: amount}(user);

            // Log ynETH balance for user
            uint256 userYnETHBalance = yneth.balanceOf(user);
            console.log("User ynETH balance after deposit:", userYnETHBalance);
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

    function startAndVerifyCheckpoint(uint256 nodeId, TestState memory state) private {
        // start checkpoint
        {
            vm.startPrank(actors.ops.STAKING_NODES_OPERATOR);
            stakingNodesManager.nodes(nodeId).startCheckpoint(true);
            vm.stopPrank();
        }

        runSystemStateInvariants(state.totalAssetsBefore, state.totalSupplyBefore, state.stakingNodeBalancesBefore);

        // verify checkpoints
        {
            IStakingNode _node = stakingNodesManager.nodes(nodeId);
            CheckpointProofs memory _cpProofs = beaconChain.getCheckpointProofs(validatorIndices, _node.eigenPod().currentCheckpointTimestamp());
            IPod(address(_node.eigenPod())).verifyCheckpointProofs({
                balanceContainerProof: _cpProofs.balanceContainerProof,
                proofs: _cpProofs.balanceProofs
            });
        }
    }


    struct QueuedWithdrawalInfo {
        uint256 nodeId;
        uint256 withdrawnAmount;
    }

    function getDelegationManagerWithdrawals(QueuedWithdrawalInfo[] memory queuedWithdrawals) private view returns (IDelegationManager.Withdrawal[] memory) {
        // create Withdrawal struct
        IDelegationManager.Withdrawal[] memory _withdrawals = new IDelegationManager.Withdrawal[](queuedWithdrawals.length);
        {
            for (uint256 i = 0; i < queuedWithdrawals.length; i++) {
                uint256[] memory _shares = new uint256[](1);
                _shares[0] = queuedWithdrawals[i].withdrawnAmount;
                IStrategy[] memory _strategies = new IStrategy[](1);
                _strategies[0] = IStrategy(0xbeaC0eeEeeeeEEeEeEEEEeeEEeEeeeEeeEEBEaC0); // beacon chain eth strat
                address _stakingNode = address(stakingNodesManager.nodes(queuedWithdrawals[i].nodeId));
                _withdrawals[i] = IDelegationManager.Withdrawal({
                    staker: _stakingNode,
                    delegatedTo: delegationManager.delegatedTo(_stakingNode),
                    withdrawer: _stakingNode,
                    nonce: delegationManager.cumulativeWithdrawalsQueued(_stakingNode) - 1,
                    startBlock: uint32(block.number),
                    strategies: _strategies,
                    shares: _shares
                });   
            }
        }
        
        return _withdrawals;
    }

    function completeQueuedWithdrawals(QueuedWithdrawalInfo[] memory queuedWithdrawals) private {
        // create Withdrawal struct
        IDelegationManager.Withdrawal[] memory _withdrawals = getDelegationManagerWithdrawals(queuedWithdrawals);

        {
            IStrategy[] memory _strategies = new IStrategy[](1);
            _strategies[0] = IStrategy(0xbeaC0eeEeeeeEEeEeEEEEeeEEeEeeeEeeEEBEaC0); // beacon chain eth strat

            // advance time to allow completion
            vm.roll(block.number + delegationManager.getWithdrawalDelay(_strategies));
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

    function completeAndProcessWithdrawals(
        IStakingNodesManager.WithdrawalAction memory withdrawalAction,
        QueuedWithdrawalInfo[] memory queuedWithdrawals
    ) public {


        IDelegationManager.Withdrawal[] memory _withdrawals = getDelegationManagerWithdrawals(queuedWithdrawals);

        {
            IStrategy[] memory _strategies = new IStrategy[](1);
            _strategies[0] = IStrategy(0xbeaC0eeEeeeeEEeEeEEEEeeEEeEeeeEeeEEBEaC0); // beacon chain eth strat

            // advance time to allow completion
            vm.roll(block.number + delegationManager.getWithdrawalDelay(_strategies));
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
        completeQueuedWithdrawals(withdrawalInfos);

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
        completeQueuedWithdrawals(withdrawalInfos);

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
        completeQueuedWithdrawals(withdrawalInfos);

        runSystemStateInvariants(state.totalAssetsBefore, state.totalSupplyBefore, state.stakingNodeBalancesBefore);
        
        // Assert that the node's podOwnerShares is accumulatedRewards after completing withdrawals
        assertEq(
            eigenPodManager.podOwnerShares(address(stakingNodesManager.nodes(nodeId))),
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
        beaconChain.slashValidators(validatorIndices);
        beaconChain.advanceEpoch();

        // queue withdrawals
        {
            vm.startPrank(actors.ops.STAKING_NODES_WITHDRAWER);
            stakingNodesManager.nodes(nodeId).queueWithdrawals(withdrawnAmount);
            vm.stopPrank();
        }

        runSystemStateInvariants(state.totalAssetsBefore, state.totalSupplyBefore, state.stakingNodeBalancesBefore);

        startAndVerifyCheckpoint(nodeId, state);

        // Print withdrawableRestakedExecutionLayerGwei for each EigenPod
        IEigenPod pod = stakingNodesManager.nodes(nodeId).eigenPod();
        uint64 withdrawableGwei = pod.withdrawableRestakedExecutionLayerGwei();
        console.log("Withdrawable GWEI for EigenPod:", withdrawableGwei);

        uint256 totalSlashAmount = beaconChain.SLASH_AMOUNT_GWEI() * state.validatorCount * 1e9;
        state.totalAssetsBefore = state.totalAssetsBefore + accumulatedRewards - totalSlashAmount;
        state.stakingNodeBalancesBefore[nodeId] = state.stakingNodeBalancesBefore[nodeId] + accumulatedRewards - totalSlashAmount;
        runSystemStateInvariants(state.totalAssetsBefore, state.totalSupplyBefore, state.stakingNodeBalancesBefore);

        QueuedWithdrawalInfo[] memory withdrawalInfos = new QueuedWithdrawalInfo[](1);
        withdrawalInfos[0] = QueuedWithdrawalInfo({
            nodeId: nodeId,
            withdrawnAmount: withdrawnAmount
        });
        completeQueuedWithdrawals(withdrawalInfos);

        runSystemStateInvariants(state.totalAssetsBefore, state.totalSupplyBefore, state.stakingNodeBalancesBefore);
    }

    function test_userWithdrawalWithRewards_Scenario_4_slashAllValidatorsWithNoRewardsAndWithdrawEverything() public {

        // exactly 2 validators
        TestState memory state = registerVerifiedValidators(64 ether);

        uint256 withdrawnAmount = amount;

        // NOTE: This triggers the a exit of all validators
        beaconChain.slashValidators(validatorIndices);
        beaconChain.advanceEpoch();

        // queue withdrawals
        {
            vm.startPrank(actors.ops.STAKING_NODES_WITHDRAWER);
            stakingNodesManager.nodes(nodeId).queueWithdrawals(withdrawnAmount);
            vm.stopPrank();
        }

        runSystemStateInvariants(state.totalAssetsBefore, state.totalSupplyBefore, state.stakingNodeBalancesBefore);

        startAndVerifyCheckpoint(nodeId, state);

        uint256 totalSlashAmount = beaconChain.SLASH_AMOUNT_GWEI() * state.validatorCount * 1e9;
        state.totalAssetsBefore = state.totalAssetsBefore - totalSlashAmount;
        state.stakingNodeBalancesBefore[nodeId] = state.stakingNodeBalancesBefore[nodeId] - totalSlashAmount;
        runSystemStateInvariants(state.totalAssetsBefore, state.totalSupplyBefore, state.stakingNodeBalancesBefore);

        QueuedWithdrawalInfo[] memory withdrawalInfos = new QueuedWithdrawalInfo[](1);
        withdrawalInfos[0] = QueuedWithdrawalInfo({
            nodeId: nodeId,
            withdrawnAmount: withdrawnAmount
        });
        completeQueuedWithdrawals(withdrawalInfos);

        runSystemStateInvariants(state.totalAssetsBefore, state.totalSupplyBefore, state.stakingNodeBalancesBefore);

        // Assert that the node's queuedSharesAmount is 0 after completing withdrawals
        assertEq(
            IStakingNodeVars(address(stakingNodesManager.nodes(nodeId))).queuedSharesAmount(),
            0,
            "Node's queuedSharesAmount should be 0 after completing withdrawals"
        );
        // Assert that the node's podOwnerShares is 0
        assertEq(
            eigenPodManager.podOwnerShares(address(stakingNodesManager.nodes(nodeId))),
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
        beaconChain.slashValidators(validatorIndices);
        beaconChain.advanceEpoch();

        startAndVerifyCheckpoint(nodeId, state);

        uint256 totalSlashAmount = beaconChain.SLASH_AMOUNT_GWEI() * state.validatorCount * 1e9;
        state.totalAssetsBefore = state.totalAssetsBefore - totalSlashAmount;
        state.stakingNodeBalancesBefore[nodeId] = state.stakingNodeBalancesBefore[nodeId] - totalSlashAmount;
        runSystemStateInvariants(state.totalAssetsBefore, state.totalSupplyBefore, state.stakingNodeBalancesBefore);

        // check podOwnerShares are now negative becaose validators were slashed after withdrawals were queued up
        assertEq(
            eigenPodManager.podOwnerShares(address(stakingNodesManager.nodes(nodeId))),
            0 - int256(totalSlashAmount),
            "Node's podOwnerShares should be 0 after completing withdrawals"
        );

        QueuedWithdrawalInfo[] memory withdrawalInfos = new QueuedWithdrawalInfo[](1);
        withdrawalInfos[0] = QueuedWithdrawalInfo({
            nodeId: nodeId,
            withdrawnAmount: withdrawnAmount
        });
        completeQueuedWithdrawals(withdrawalInfos);

        runSystemStateInvariants(state.totalAssetsBefore, state.totalSupplyBefore, state.stakingNodeBalancesBefore);
    }
}