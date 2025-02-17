// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IEigenPod, IEigenPodErrors} from "lib/eigenlayer-contracts/src/contracts/interfaces/IEigenPod.sol";

import {IStakingNode} from "src/interfaces/IStakingNode.sol";
import {IStakingNodesManager} from "src/interfaces/IStakingNodesManager.sol";
import {IWithdrawalQueueManager} from "src/interfaces/IWithdrawalQueueManager.sol";

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
    uint256 public nodeId;

    uint256 public constant AMOUNT = 32 ether;

    //
    // setup
    //

    function setUp() public override {
        super.setUp();

        // deposit 32 ETH into ynETH
        {
            user = vm.addr(420);
            vm.deal(user, AMOUNT);
            vm.prank(user);
            yneth.depositETH{value: AMOUNT}(user);
        }
    }

    //
    // setup user withdrawal tests
    //

    function testVerifyWithdrawalCredentials() public {

        // create staking node
        {
            vm.prank(actors.ops.STAKING_NODE_CREATOR);
            stakingNodesManager.createStakingNode();
            nodeId = stakingNodesManager.nodesLength() - 1;
        }

        // create validator
        {
            bytes memory _withdrawalCredentials = stakingNodesManager.getWithdrawalCredentials(nodeId);
            validatorIndex = beaconChain.newValidator{ value: AMOUNT }(_withdrawalCredentials);
            beaconChain.advanceEpoch_NoRewards();
        }

        // register validator
        {
            bytes memory _dummyPubkey = new bytes(48);
            IStakingNodesManager.ValidatorData[] memory _data = new IStakingNodesManager.ValidatorData[](1);
            _data[0] = IStakingNodesManager.ValidatorData({
                publicKey: _dummyPubkey,
                signature: ZERO_SIGNATURE,
                depositDataRoot: stakingNodesManager.generateDepositRoot(
                    _dummyPubkey,
                    ZERO_SIGNATURE,
                    stakingNodesManager.getWithdrawalCredentials(nodeId),
                    AMOUNT
                ),
                nodeId: nodeId
            });
            vm.prank(actors.ops.VALIDATOR_MANAGER);
            stakingNodesManager.registerValidators(_data);
        }

        // verify withdrawal credentials
        {
            uint40[] memory _validators = new uint40[](1);
            _validators[0] = validatorIndex;
            CredentialProofs memory _proofs = beaconChain.getCredentialProofs(_validators);
            vm.startPrank(actors.ops.STAKING_NODES_OPERATOR);
            IPod(address(stakingNodesManager.nodes(nodeId))).verifyWithdrawalCredentials({
                beaconTimestamp: _proofs.beaconTimestamp,
                stateRootProof: _proofs.stateRootProof,
                validatorIndices: _validators,
                validatorFieldsProofs: _proofs.validatorFieldsProofs,
                validatorFields: _proofs.validatorFields
            });
            vm.stopPrank();

            // check that unverifiedStakedETH is 0 and podOwnerShares is 32 ETH (AMOUNT)
            _testVerifyWithdrawalCredentials();
        }
    }

    function testVerifyCheckpoints() public skipOnHolesky {

        // setup env
        {
            testVerifyWithdrawalCredentials();
            beaconChain.advanceEpoch();
        }

        // start checkpoint
        {
            vm.startPrank(actors.ops.STAKING_NODES_OPERATOR);
            stakingNodesManager.nodes(nodeId).startCheckpoint(true);
            vm.stopPrank();

            // make sure startCheckpoint cant be called again, which means that the checkpoint has started
            _testStartCheckpoint();
        }

        // verify checkpoints
        {
            uint40[] memory _validators = new uint40[](1);
            _validators[0] = validatorIndex;
            IStakingNode _node = stakingNodesManager.nodes(nodeId);
            CheckpointProofs memory _cpProofs = beaconChain.getCheckpointProofs(_validators, _node.eigenPod().currentCheckpointTimestamp());
            IPod(address(_node.eigenPod())).verifyCheckpointProofs({
                balanceContainerProof: _cpProofs.balanceContainerProof,
                proofs: _cpProofs.balanceProofs
            });

            // check that proofsRemaining is 0 and podOwnerShares is still 32 ETH (AMOUNT)
            _testVerifyCheckpointsBeforeWithdrawalRequest();
        }
    }

    function testWithdrawSingleValidator() public skipOnHolesky {
        testWithdraw();
    }

    function testWithdraw() internal {

        // setup env
        {
            testVerifyCheckpoints();
        }

        // queue withdrawals
        {
            vm.startPrank(actors.ops.STAKING_NODES_WITHDRAWER);
            stakingNodesManager.nodes(nodeId).queueWithdrawals(AMOUNT);
            vm.stopPrank();

            // check that queuedSharesAmount is 32 ETH (AMOUNT)
            _testQueueWithdrawals();
        }

        // create Withdrawal struct
        IDelegationManagerTypes.Withdrawal[] memory _withdrawals = new IDelegationManagerTypes.Withdrawal[](1);
        {
            uint256[] memory _shares = new uint256[](1);
            _shares[0] = AMOUNT;
            IStrategy[] memory _strategies = new IStrategy[](1);
            _strategies[0] = IStrategy(0xbeaC0eeEeeeeEEeEeEEEEeeEEeEeeeEeeEEBEaC0); // beacon chain eth strat
            address _stakingNode = address(stakingNodesManager.nodes(nodeId));
            _withdrawals[0] = IDelegationManagerTypes.Withdrawal({
                staker: _stakingNode,
                delegatedTo: delegationManager.delegatedTo(_stakingNode),
                withdrawer: _stakingNode,
                nonce: delegationManager.cumulativeWithdrawalsQueued(_stakingNode) - 1,
                startBlock: uint32(block.number),
                strategies: _strategies,
                scaledShares: _shares
            });   
        }

        // exit validators
        {
            IStrategy[] memory _strategies = new IStrategy[](1);
            _strategies[0] = IStrategy(0xbeaC0eeEeeeeEEeEeEEEEeeEEeEeeeEeeEEBEaC0); // beacon chain eth strat
            vm.roll(block.number + delegationManager.minWithdrawalDelayBlocks() + 1);
            beaconChain.exitValidator(validatorIndex);
            beaconChain.advanceEpoch_NoRewards();
        }

        // start checkpoint
        {
            vm.startPrank(actors.ops.STAKING_NODES_OPERATOR);
            stakingNodesManager.nodes(nodeId).startCheckpoint(true);
            vm.stopPrank();

            // make sure startCheckpoint cant be called again, which means that the checkpoint has started
            _testStartCheckpoint();
        }

        // verify checkpoints
        {
            uint40[] memory _validators = new uint40[](1);
            _validators[0] = validatorIndex;
            IStakingNode _node = stakingNodesManager.nodes(nodeId);
            CheckpointProofs memory _cpProofs = beaconChain.getCheckpointProofs(_validators, _node.eigenPod().currentCheckpointTimestamp());
            IPod(address(_node.eigenPod())).verifyCheckpointProofs({
                balanceContainerProof: _cpProofs.balanceContainerProof,
                proofs: _cpProofs.balanceProofs
            });

            // check that proofsRemaining is 0 and podOwnerShares is 0 ETH (it will actually be 1000000000 bc of EL accounting tricks)
            _testVerifyCheckpointsAfterWithdrawalRequest();
        }

        // complete queued withdrawals
        {
            vm.startPrank(actors.ops.STAKING_NODES_WITHDRAWER);
            stakingNodesManager.nodes(nodeId).completeQueuedWithdrawals(_withdrawals);
            vm.stopPrank();

            // check that queuedSharesAmount is 0, and withdrawnETH is 32 ETH (AMOUNT), and staking pod balance is 32 ETH (AMOUNT)
            _testCompleteQueuedWithdrawals();
        }

        // process principal withdrawals
        uint256 _ynethBalanceBefore = address(yneth).balance;
        uint256 _ynETHRedemptionAssetsBalanceBefore = address(ynETHRedemptionAssetsVaultInstance).balance;
        {
            IStakingNodesManager.WithdrawalAction[] memory _actions = new IStakingNodesManager.WithdrawalAction[](1);
            _actions[0] = IStakingNodesManager.WithdrawalAction({
                nodeId: nodeId,
                amountToReinvest: AMOUNT / 2, // 16 ETH
                amountToQueue: AMOUNT / 2, // 16 ETH
                rewardsAmount: 0
            });
            vm.prank(actors.ops.WITHDRAWAL_MANAGER);
            stakingNodesManager.processPrincipalWithdrawals({
                actions: _actions
            });

            // check that totalDepositedInPool is 16 ETH, ynETH balance is 16 ETH, and ynETHRedemptionAssetsVault balance is 16 ETH
            _testProcessPrincipalWithdrawals(_ynethBalanceBefore, _ynETHRedemptionAssetsBalanceBefore);
        }
    }

    //
    // user withdrawal tests
    //

    function testRequestWithdrawal(uint256 _amount) public returns (uint256 _tokenId) {

        uint256 _userAmountBefore = yneth.balanceOf(user);
        vm.assume(_amount <= _userAmountBefore / 2 && _amount > 0); // `/ 2` bc we distribute only half of what the user has deposited

        uint256 _pendingRequestedRedemptionAmountBefore = ynETHWithdrawalQueueManager.pendingRequestedRedemptionAmount();
        uint256 _withdrawalQueueManagerBalanceBefore = yneth.balanceOf(address(ynETHWithdrawalQueueManager));
        vm.startPrank(user);
        yneth.approve(address(ynETHWithdrawalQueueManager), _amount);
        _tokenId = ynETHWithdrawalQueueManager.requestWithdrawal(_amount);
        vm.stopPrank();

        assertEq(yneth.balanceOf(user), _userAmountBefore - _amount, "testRequestWithdrawal: E0");
        assertEq(yneth.balanceOf(address(ynETHWithdrawalQueueManager)), _withdrawalQueueManagerBalanceBefore + _amount, "testRequestWithdrawal: E1");

        IWithdrawalQueueManager.WithdrawalRequest memory _withdrawalRequest = ynETHWithdrawalQueueManager.withdrawalRequest(_tokenId);
        assertEq(_withdrawalRequest.amount, _amount, "testRequestWithdrawal: E2");
        assertEq(_withdrawalRequest.redemptionRateAtRequestTime, ynETHRedemptionAssetsVaultInstance.redemptionRate(), "testRequestWithdrawal: E3");
        assertEq(_withdrawalRequest.creationTimestamp, block.timestamp, "testRequestWithdrawal: E4");
        assertEq(_withdrawalRequest.processed, false, "testRequestWithdrawal: E5");
        assertEq(_withdrawalRequest.feeAtRequestTime, ynETHWithdrawalQueueManager.withdrawalFee(), "testRequestWithdrawal: E6");
        assertEq(ynETHWithdrawalQueueManager.pendingRequestedRedemptionAmount(), _pendingRequestedRedemptionAmountBefore + ynETHWithdrawalQueueManager.calculateRedemptionAmount(_amount, ynETHRedemptionAssetsVaultInstance.redemptionRate()), "testRequestWithdrawal: E6");
    }

    function testClaimWithdrawal(uint256 _amount) public skipOnHolesky {
        vm.assume(_amount > 1 ether);

        uint256 _tokenId = testRequestWithdrawal(_amount);
        uint256 _userETHBalanceBefore = address(user).balance;
        uint256 _expectedAmountOut = yneth.previewRedeem(_amount);
        uint256 _expectedAmountOutUser = _expectedAmountOut;
        uint256 _expectedAmountOutFeeReceiver;
        if (ynETHWithdrawalQueueManager.withdrawalFee() > 0) {
            uint256 _feeAmount = _expectedAmountOut * ynETHWithdrawalQueueManager.withdrawalFee() / ynETHWithdrawalQueueManager.FEE_PRECISION();
            _expectedAmountOutUser = _expectedAmountOut - _feeAmount;
            _expectedAmountOutFeeReceiver = _feeAmount;

        }
        uint256 _feeReceiverETHBalanceBefore = ynETHWithdrawalQueueManager.feeReceiver().balance;
        uint256 _withdrawalQueueManagerBalanceBefore = yneth.balanceOf(address(ynETHWithdrawalQueueManager));

        testWithdraw(); // process the withdrawal
        vm.prank(actors.ops.REQUEST_FINALIZER);
        uint256 finalizationId = ynETHWithdrawalQueueManager.finalizeRequestsUpToIndex(_tokenId + 1);


        IWithdrawalQueueManager.WithdrawalClaim[] memory claims = new IWithdrawalQueueManager.WithdrawalClaim[](1);
        claims[0] = IWithdrawalQueueManager.WithdrawalClaim({
            tokenId: _tokenId,
            finalizationId: finalizationId,
            receiver: user
        });
        vm.prank(user);
        ynETHWithdrawalQueueManager.claimWithdrawals(claims);

        IWithdrawalQueueManager.WithdrawalRequest memory _withdrawalRequest = ynETHWithdrawalQueueManager.withdrawalRequest(_tokenId);
        assertEq(_withdrawalRequest.processed, true, "testClaimWithdrawal: E0");
        assertEq(yneth.balanceOf(address(ynETHWithdrawalQueueManager)), _withdrawalQueueManagerBalanceBefore - _amount, "testClaimWithdrawal: E1");
        assertApproxEqAbs(address(user).balance, _userETHBalanceBefore + _expectedAmountOutUser, 10_000, "testClaimWithdrawal: E2");
        assertApproxEqAbs(ynETHWithdrawalQueueManager.feeReceiver().balance, _feeReceiverETHBalanceBefore + _expectedAmountOutFeeReceiver, 10_000, "testClaimWithdrawal: E3");
    }

    //
    // internal helpers
    //

    function _testVerifyWithdrawalCredentials() internal {
        assertEq(stakingNodesManager.nodes(nodeId).unverifiedStakedETH(), 0, "_testVerifyWithdrawalCredentials: E0");
        assertEq(uint256(eigenPodManager.podOwnerDepositShares(address(stakingNodesManager.nodes(nodeId)))), AMOUNT, "_testVerifyWithdrawalCredentials: E1");
    }

    function _testStartCheckpoint() internal {
        IStakingNode _node = stakingNodesManager.nodes(nodeId);
        vm.expectRevert(IEigenPodErrors.CheckpointAlreadyActive.selector);
        vm.prank(actors.ops.STAKING_NODES_OPERATOR);
        _node.startCheckpoint(true);
    }

    function _testVerifyCheckpointsBeforeWithdrawalRequest() internal {
        IEigenPod.Checkpoint memory _checkpoint = stakingNodesManager.nodes(nodeId).eigenPod().currentCheckpoint();
        assertEq(_checkpoint.proofsRemaining, 0, "_testVerifyCheckpointsBeforeWithdrawalRequest: E0");
        assertApproxEqAbs(uint256(eigenPodManager.podOwnerDepositShares(address(stakingNodesManager.nodes(nodeId)))), AMOUNT, 1000000000, "_testVerifyCheckpointsBeforeWithdrawalRequest: E1");
    }

    function _testQueueWithdrawals() internal {
        assertEq(IStakingNodeVars(address(stakingNodesManager.nodes(nodeId))).queuedSharesAmount(), AMOUNT, "_testQueueWithdrawals: E0");
    }

    function _testVerifyCheckpointsAfterWithdrawalRequest() internal {
        IEigenPod.Checkpoint memory _checkpoint = stakingNodesManager.nodes(nodeId).eigenPod().currentCheckpoint();
        assertEq(_checkpoint.proofsRemaining, 0, "_testVerifyCheckpointsAfterWithdrawalRequest: E0");
        assertEq(uint256(eigenPodManager.podOwnerDepositShares(address(stakingNodesManager.nodes(nodeId)))), 1000000000, "_testVerifyCheckpointsAfterWithdrawalRequest: E1");
    }

    function _testCompleteQueuedWithdrawals() internal {
        assertEq(address(stakingNodesManager.nodes(nodeId)).balance, AMOUNT, "_testCompleteQueuedWithdrawals: E0");
        assertEq(IStakingNodeVars(address(stakingNodesManager.nodes(nodeId))).queuedSharesAmount(), 0, "_testCompleteQueuedWithdrawals: E1");
        assertEq(IStakingNodeVars(address(stakingNodesManager.nodes(nodeId))).withdrawnETH(), AMOUNT, "_testCompleteQueuedWithdrawals: E2");
    }

    function _testProcessPrincipalWithdrawals(uint256 _ynethBalanceBefore, uint256 _ynETHRedemptionAssetsBalanceBefore) internal {
        assertEq(yneth.totalDepositedInPool(), _ynethBalanceBefore + (AMOUNT / 2), "_testProcessPrincipalWithdrawals: E0");
        assertEq(address(yneth).balance, _ynethBalanceBefore + (AMOUNT / 2), "_testProcessPrincipalWithdrawals: E1");
        assertEq(address(ynETHRedemptionAssetsVaultInstance).balance, _ynETHRedemptionAssetsBalanceBefore + AMOUNT / 2, "_testProcessPrincipalWithdrawals: E2");
    }
}