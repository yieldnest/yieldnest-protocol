// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

// import {EigenPod} from "lib/eigenlayer-contracts/src/contracts/pods/EigenPod.sol";

import {IStakingNode} from "../../../src/interfaces/IStakingNode.sol";
import {IStakingNodesManager} from "../../../src/interfaces/IStakingNodesManager.sol";

import "./Base.t.sol";

interface IPod {
    function verifyWithdrawalCredentials(uint64 beaconTimestamp, BeaconChainProofs.StateRootProof calldata stateRootProof, uint40[] calldata validatorIndices, bytes[] calldata validatorFieldsProofs, bytes32[][] calldata validatorFields) external;
    function verifyCheckpointProofs(BeaconChainProofs.BalanceContainerProof calldata balanceContainerProof, BeaconChainProofs.BalanceProof[] calldata proofs) external;
}

contract M3WithdrawalsTest is Base {

    uint40 validatorIndex;

    uint256 AMOUNT = 32 ether;
    uint256 NODE_ID = 0;
    bytes constant  ZERO_SIGNATURE = hex"000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";

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

        // create validator
        {
            bytes memory _withdrawalCredentials = stakingNodesManager.getWithdrawalCredentials(NODE_ID);
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
                    stakingNodesManager.getWithdrawalCredentials(NODE_ID),
                    AMOUNT
                ),
                nodeId: NODE_ID
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
            IPod(address(stakingNodesManager.nodes(NODE_ID))).verifyWithdrawalCredentials({
                beaconTimestamp: _proofs.beaconTimestamp,
                stateRootProof: _proofs.stateRootProof,
                validatorIndices: _validators,
                validatorFieldsProofs: _proofs.validatorFieldsProofs,
                validatorFields: _proofs.validatorFields
            });
            vm.stopPrank();
        }
    }

    function testVerifyCheckpoints() public {

        // setup env
        {
            testVerifyWithdrawalCredentials();
            beaconChain.advanceEpoch();
        }

        // start checkpoint
        {
            vm.startPrank(actors.ops.STAKING_NODES_OPERATOR);
            stakingNodesManager.nodes(NODE_ID).startCheckpoint(true);
            vm.stopPrank();
        }

        // verify checkpoints
        {
            uint40[] memory _validators = new uint40[](1);
            _validators[0] = validatorIndex;
            IStakingNode _node = stakingNodesManager.nodes(NODE_ID);
            CheckpointProofs memory _cpProofs = beaconChain.getCheckpointProofs(_validators, _node.eigenPod().currentCheckpointTimestamp());
            IPod(address(_node.eigenPod())).verifyCheckpointProofs({
                balanceContainerProof: _cpProofs.balanceContainerProof,
                proofs: _cpProofs.balanceProofs
            });
        }
    }

    function testWithdraw() public {

        // setup env
        {
            testVerifyCheckpoints();
        }

        // queue withdrawals
        {
            vm.startPrank(GLOBAL_ADMIN);
            stakingNodesManager.nodes(NODE_ID).queueWithdrawals(AMOUNT);
            vm.stopPrank();
        }

        // exit validators and complete checkpoints
        {
            vm.roll(block.number + delegationManager.getWithdrawalDelay(strategies));
            // _exitValidators(getActiveValidators());
            // beaconChain.advanceEpoch_NoRewards();
            // _startCheckpoint();
            // if (pod.activeValidatorCount() != 0) {
            //     _completeCheckpoint();
            // }
        }

        // // complete queued withdrawals
        // {
        //     vm.roll(block.number + delegationManager.getWithdrawalDelay(strategies));
        // }

        // // process principal withdrawals
        // {
        //     IStakingNodesManager.WithdrawalAction[] memory _actions = new IStakingNodesManager.WithdrawalAction[](1);
        //     _actions[0] = IStakingNodesManager.WithdrawalAction({
        //         nodeId: NODE_ID,
        //         amountToReinvest: AMOUNT / 2, // 16 ETH
        //         amountToQueue: AMOUNT / 2 // 16 ETH
        //     });
        //     vm.prank(GLOBAL_ADMIN);
        //     stakingNodesManager.processPrincipalWithdrawals({
        //         actions: _actions
        //     });
        // }
    }
}