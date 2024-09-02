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
    }


    function setUp() public override {
        super.setUp();
    }

    function test_userWithdrawalWithRewards_Scenario_1() public {
        // Check if we're on the Holesky testnet
        if (block.chainid != 17000) {
            return;
        }
        amount = 100 ether;

        // deposit 100 ETH into ynETH
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


        TestState memory state = TestState({
            totalAssetsBefore: yneth.totalAssets(),
            totalSupplyBefore: yneth.totalSupply(),
            stakingNodeBalancesBefore: getAllStakingNodeBalances(),
            previousYnETHRedemptionAssetsVaultBalance: ynETHRedemptionAssetsVaultInstance.availableRedemptionAssets(),
            previousYnETHBalance: address(yneth).balance
        });

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

        uint256 accumulatedRewards;
        {
            uint256 epochCount = 30;
            // Advance the beacon chain by 100 epochs to simulate rewards accumulation
            for (uint256 i = 0; i < epochCount; i++) {
                beaconChain.advanceEpoch();
            }

            accumulatedRewards += validatorCount * epochCount * 1e9; // 1 GWEI per Epoch per Validator
        }


        // exit validators
        {
            for (uint256 i = 0; i < validatorIndices.length; i++) {
                beaconChain.exitValidator(validatorIndices[i]);
            }
            beaconChain.advanceEpoch();
        }

        runSystemStateInvariants(state.totalAssetsBefore, state.totalSupplyBefore, state.stakingNodeBalancesBefore);


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

        // Rewards accumulated are accounted after verifying the checkpoint
        state.totalAssetsBefore += accumulatedRewards;
        state.stakingNodeBalancesBefore[nodeId] += accumulatedRewards;
        runSystemStateInvariants(state.totalAssetsBefore, state.totalSupplyBefore, state.stakingNodeBalancesBefore);

        uint256 withdrawnAmount = 32 ether * validatorIndices.length + accumulatedRewards;

        // queue withdrawals
        {
            vm.startPrank(actors.ops.STAKING_NODES_OPERATOR);
            stakingNodesManager.nodes(nodeId).queueWithdrawals(withdrawnAmount);
            vm.stopPrank();
        }

        runSystemStateInvariants(state.totalAssetsBefore, state.totalSupplyBefore, state.stakingNodeBalancesBefore);

        // create Withdrawal struct
        IDelegationManager.Withdrawal[] memory _withdrawals = new IDelegationManager.Withdrawal[](1);
        {
            uint256[] memory _shares = new uint256[](1);
            _shares[0] = withdrawnAmount;
            IStrategy[] memory _strategies = new IStrategy[](1);
            _strategies[0] = IStrategy(0xbeaC0eeEeeeeEEeEeEEEEeeEEeEeeeEeeEEBEaC0); // beacon chain eth strat
            address _stakingNode = address(stakingNodesManager.nodes(nodeId));
            _withdrawals[0] = IDelegationManager.Withdrawal({
                staker: _stakingNode,
                delegatedTo: delegationManager.delegatedTo(_stakingNode),
                withdrawer: _stakingNode,
                nonce: delegationManager.cumulativeWithdrawalsQueued(_stakingNode) - 1,
                startBlock: uint32(block.number),
                strategies: _strategies,
                shares: _shares
            });   
        }

        {
            IStrategy[] memory _strategies = new IStrategy[](1);
            _strategies[0] = IStrategy(0xbeaC0eeEeeeeEEeEeEEEEeeEEeEeeeEeeEEBEaC0); // beacon chain eth strat

            // advance time to allow competion
            vm.roll(block.number + delegationManager.getWithdrawalDelay(_strategies));
        }

        // complete queued withdrawals
        {
            uint256[] memory _middlewareTimesIndexes = new uint256[](1);
            _middlewareTimesIndexes[0] = 0;
            vm.startPrank(actors.ops.STAKING_NODES_OPERATOR);
            stakingNodesManager.nodes(nodeId).completeQueuedWithdrawals(_withdrawals, _middlewareTimesIndexes);
            vm.stopPrank();
        }

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
        ynETHWithdrawalQueueManager.finalizeRequestsUpToIndex(_tokenId + 1);

        uint256 userBalanceBefore = user.balance;
        vm.prank(user);
        ynETHWithdrawalQueueManager.claimWithdrawal(_tokenId, user);
        uint256 userBalanceAfter = user.balance;
        uint256 actualWithdrawnAmount = userBalanceAfter - userBalanceBefore;
        // Calculate expected withdrawal amount after fee
        uint256 withdrawalFee = ynETHWithdrawalQueueManager.withdrawalFee();
        uint256 expectedWithdrawnAmount = userWithdrawalAmount - (userWithdrawalAmount * withdrawalFee / ynETHWithdrawalQueueManager.FEE_PRECISION());
        
        assertApproxEqAbs(actualWithdrawnAmount, expectedWithdrawnAmount, 1e9, "User did not receive expected ETH amount after fee");

    }
}