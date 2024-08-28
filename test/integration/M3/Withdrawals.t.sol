// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IEigenPod} from "lib/eigenlayer-contracts/src/contracts/interfaces/IEigenPod.sol";

import {IStakingNode} from "../../../src/interfaces/IStakingNode.sol";
import {IStakingNodesManager} from "../../../src/interfaces/IStakingNodesManager.sol";

import "./Base.t.sol";

interface IPod {
    function verifyWithdrawalCredentials(uint64 beaconTimestamp, BeaconChainProofs.StateRootProof calldata stateRootProof, uint40[] calldata validatorIndices, bytes[] calldata validatorFieldsProofs, bytes32[][] calldata validatorFields) external;
    function verifyCheckpointProofs(BeaconChainProofs.BalanceContainerProof calldata balanceContainerProof, BeaconChainProofs.BalanceProof[] calldata proofs) external;
}

interface IStakingNodeVars {
    function queuedSharesAmount() external view returns (uint256);
}

contract M3WithdrawalsTest is Base {

    uint40 public validatorIndex;
    uint256 public nodeId;

    uint256 public constant AMOUNT = 32 ether;
    bytes public constant ZERO_SIGNATURE = hex"000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";

    function setUp() public override {
        super.setUp();

        // deposit 32 ETH into ynETH
        {
            address _user = vm.addr(420);
            vm.deal(_user, AMOUNT);
            vm.prank(_user);
            yneth.depositETH{value: AMOUNT}(_user);
        }
    }

    function testVerifyWithdrawalCredentials() public {
        if (block.chainid != 17000) return;

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

    function testVerifyCheckpoints() public {
        if (block.chainid != 17000) return;

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

    function testWithdraw() public {
        if (block.chainid != 17000) return;

        // setup env
        {
            testVerifyCheckpoints();
        }

        // queue withdrawals
        {
            vm.startPrank(GLOBAL_ADMIN);
            stakingNodesManager.nodes(nodeId).queueWithdrawals(AMOUNT);
            vm.stopPrank();

            // check that queuedSharesAmount is 32 ETH (AMOUNT)
            _testQueueWithdrawals();
        }

        // create Withdrawal struct
        IDelegationManager.Withdrawal[] memory _withdrawals = new IDelegationManager.Withdrawal[](1);
        {
            uint256[] memory _shares = new uint256[](1);
            _shares[0] = AMOUNT;
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

        // exit validators
        {
            IStrategy[] memory _strategies = new IStrategy[](1);
            _strategies[0] = IStrategy(0xbeaC0eeEeeeeEEeEeEEEEeeEEeEeeeEeeEEBEaC0); // beacon chain eth strat
            vm.roll(block.number + delegationManager.getWithdrawalDelay(_strategies));
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
            uint256[] memory _middlewareTimesIndexes = new uint256[](1);
            _middlewareTimesIndexes[0] = 0;
            vm.startPrank(GLOBAL_ADMIN);
            stakingNodesManager.nodes(nodeId).completeQueuedWithdrawals(_withdrawals, _middlewareTimesIndexes);
            vm.stopPrank();
            // _testCompleteQueuedWithdrawals(); // @todo
        }

        // process principal withdrawals
        {
            IStakingNodesManager.WithdrawalAction[] memory _actions = new IStakingNodesManager.WithdrawalAction[](1);
            _actions[0] = IStakingNodesManager.WithdrawalAction({
                nodeId: nodeId,
                amountToReinvest: AMOUNT / 2, // 16 ETH
                amountToQueue: AMOUNT / 2 // 16 ETH
            });
            vm.prank(GLOBAL_ADMIN);
            stakingNodesManager.processPrincipalWithdrawals({
                actions: _actions
            });
            // _testProcessPrincipalWithdrawals(); // @todo
        }
    }

    //
    // internal helpers
    //

    function _testVerifyWithdrawalCredentials() internal {
        assertEq(stakingNodesManager.nodes(nodeId).unverifiedStakedETH(), 0, "_testVerifyWithdrawalCredentials: E0");
        assertEq(uint256(eigenPodManager.podOwnerShares(address(stakingNodesManager.nodes(nodeId)))), AMOUNT, "_testVerifyWithdrawalCredentials: E1");
    }

    function _testStartCheckpoint() internal {
        IStakingNode _node = stakingNodesManager.nodes(nodeId);
        vm.expectRevert("EigenPod._startCheckpoint: must finish previous checkpoint before starting another");
        vm.prank(actors.ops.STAKING_NODES_OPERATOR);
        _node.startCheckpoint(true);
    }

    function _testVerifyCheckpointsBeforeWithdrawalRequest() internal {
        IEigenPod.Checkpoint memory _checkpoint = stakingNodesManager.nodes(nodeId).eigenPod().currentCheckpoint();
        assertEq(_checkpoint.proofsRemaining, 0, "_testVerifyCheckpointsBeforeWithdrawalRequest: E0");
        assertApproxEqAbs(uint256(eigenPodManager.podOwnerShares(address(stakingNodesManager.nodes(nodeId)))), AMOUNT, 1000000000, "_testVerifyCheckpointsBeforeWithdrawalRequest: E1");
    }

    function _testQueueWithdrawals() internal {
        assertEq(IStakingNodeVars(address(stakingNodesManager.nodes(nodeId))).queuedSharesAmount(), AMOUNT, "_testQueueWithdrawals: E0");
    }

    function _testVerifyCheckpointsAfterWithdrawalRequest() internal {
        IEigenPod.Checkpoint memory _checkpoint = stakingNodesManager.nodes(nodeId).eigenPod().currentCheckpoint();
        assertEq(_checkpoint.proofsRemaining, 0, "_testVerifyCheckpointsAfterWithdrawalRequest: E0");
        assertEq(uint256(eigenPodManager.podOwnerShares(address(stakingNodesManager.nodes(nodeId)))), 1000000000, "_testVerifyCheckpointsAfterWithdrawalRequest: E1");
    }
}