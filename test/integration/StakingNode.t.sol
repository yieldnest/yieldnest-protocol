// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {UpgradeableBeacon} from "lib/openzeppelin-contracts/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {OwnableUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {IPausable} from "lib/eigenlayer-contracts/src/contracts/interfaces/IPausable.sol";
import {IDelegationManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IntegrationBaseTest} from "test/integration/IntegrationBaseTest.sol";
import {IStakingNode} from "src/interfaces/IStakingNode.sol";
import {IStakingNodesManager} from "src/interfaces/IStakingNodesManager.sol";
import {IEigenPod} from "lib/eigenlayer-contracts/src/contracts/interfaces/IEigenPod.sol";
import {IStrategyManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol"; 
import {StakingNode} from "src/StakingNode.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol"; 
import {ProofUtils} from "test/utils/ProofUtils.sol";
import {ISignatureUtils} from "lib/eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";
import {BytesLib} from "lib/eigenlayer-contracts/src/contracts/libraries/BytesLib.sol";
import { EigenPod } from "lib/eigenlayer-contracts/src/contracts/pods/EigenPod.sol";
import {MockEigenPod} from "../mocks/MockEigenPod.sol";
import { MockEigenPodManager } from "../mocks/MockEigenPodManager.sol";
import { MockStakingNode } from "../mocks/MockStakingNode.sol";
import { EigenPodManager } from "lib/eigenlayer-contracts/src/contracts/pods/EigenPodManager.sol";
import {IETHPOSDeposit} from "lib/eigenlayer-contracts/src/contracts/interfaces/IETHPOSDeposit.sol";
import {IEigenPodManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IEigenPodManager.sol";
import {IEigenPod} from "lib/eigenlayer-contracts/src/contracts/interfaces/IEigenPod.sol";
import { TransparentUpgradeableProxy } from "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {BeaconChainMock, BeaconChainProofs, CheckpointProofs, CredentialProofs } from "lib/eigenlayer-contracts/src/test/integration/mocks/BeaconChainMock.t.sol";
import { ProofParsingV1 } from "test/eigenlayer-utils/ProofParsingV1.sol";
import {Utils} from "script/Utils.sol";


interface IEigenPodSimplified {
    function verifyWithdrawalCredentials(uint64 beaconTimestamp, BeaconChainProofs.StateRootProof calldata stateRootProof, uint40[] calldata validatorIndices, bytes[] calldata validatorFieldsProofs, bytes32[][] calldata validatorFields) external;
    function verifyCheckpointProofs(BeaconChainProofs.BalanceContainerProof calldata balanceContainerProof, BeaconChainProofs.BalanceProof[] calldata proofs) external;
}

interface ITransparentUpgradeableProxy {
    function upgradeTo(address) external payable;
}

contract StakingNodeTestBase is IntegrationBaseTest, ProofParsingV1 {
    function createStakingNodes(uint nodeCount) public returns (uint256[] memory) {
        uint256[] memory nodeIds = new uint256[](nodeCount);
        for (uint256 i = 0; i < nodeCount; i++) {
            vm.prank(actors.ops.STAKING_NODE_CREATOR);
            IStakingNode node = stakingNodesManager.createStakingNode();
            nodeIds[i] = node.nodeId();
        }
        return nodeIds;
    }

    function _verifyWithdrawalCredentials(uint256 _nodeId, uint40 _validatorIndex) internal {
        uint40[] memory _validators = new uint40[](1);
        _validators[0] = _validatorIndex;

        
        CredentialProofs memory _proofs = beaconChain.getCredentialProofs(_validators);
        vm.startPrank(actors.ops.STAKING_NODES_OPERATOR);
        IEigenPodSimplified(address(stakingNodesManager.nodes(_nodeId))).verifyWithdrawalCredentials({
            beaconTimestamp: _proofs.beaconTimestamp,
            stateRootProof: _proofs.stateRootProof,
            validatorIndices: _validators,
            validatorFieldsProofs: _proofs.validatorFieldsProofs,
            validatorFields: _proofs.validatorFields
        });
        vm.stopPrank();
    }
}


contract StakingNodeEigenPod is StakingNodeTestBase {

   // FIXME: update or delete to accomdate for M3
    function testCreateNodeAndVerifyPodStateIsValid() public {

        uint depositAmount = 32 ether;

        address user = vm.addr(156737);

        // Create a user address and fund it with 1000 ETH
        vm.deal(user, 1000 ether);

        yneth.depositETH{value: depositAmount }(user);

        uint256[] memory nodeIds = createStakingNodes(1);
        IStakingNode stakingNodeInstance = stakingNodesManager.nodes(nodeIds[0]);
        IEigenPod eigenPodInstance = stakingNodeInstance.eigenPod();


        // TODO: double check this is the desired state for a pod.
        // we can't delegate on mainnet at this time so one should be able to farm points without delegating
        assertEq(eigenPodInstance.withdrawableRestakedExecutionLayerGwei(), 0, "Restaked Gwei should be 0");
        assertEq(address(eigenPodManager), address(eigenPodInstance.eigenPodManager()), "EigenPodManager should match");
        assertEq(eigenPodInstance.podOwner(), address(stakingNodeInstance), "Pod owner address does not match");

        address payable eigenPodAddress = payable(address(eigenPodInstance));
        // Get initial pod owner shares
        int256 initialPodOwnerShares = eigenPodManager.podOwnerShares(address(stakingNodeInstance));
        // Assert that initial pod owner shares are 0
        assertEq(initialPodOwnerShares, 0, "Initial pod owner shares should be 0");

        // simulate ETH entering the pod by direct transfer as non-beacon chain ETH
        uint256 rewardsSweeped = 1 ether;
        vm.deal(address(this), rewardsSweeped);
        (bool success,) = eigenPodAddress.call{value: rewardsSweeped}("");
        require(success, "Failed to send rewards to EigenPod");

        // Get final pod owner shares
        int256 finalPodOwnerShares = eigenPodManager.podOwnerShares(address(stakingNodeInstance));

        // Assert that pod owner shares remain the same
        assertEq(initialPodOwnerShares, 0, "Pod owner shares should not change");
    }
    
    function testCreateNodeVerifyPodStateAndCheckpoint() public {
        uint256 depositAmount = 32 ether;
        address user = vm.addr(156737);

        // Fund user and deposit ETH
        vm.deal(user, 1000 ether);
        yneth.depositETH{value: depositAmount}(user);

        // Create staking node and get instances
        uint256[] memory nodeIds = createStakingNodes(1);
        IStakingNode stakingNodeInstance = stakingNodesManager.nodes(nodeIds[0]);
        IEigenPod eigenPodInstance = stakingNodeInstance.eigenPod();

        // Simulate ETH entering the pod
        uint256 rewardsSweeped = 1 ether;
        vm.deal(address(this), rewardsSweeped);
        (bool success,) = payable(address(eigenPodInstance)).call{value: rewardsSweeped}("");
        require(success, "Failed to send rewards to EigenPod");

        beaconChain.advanceEpoch_NoRewards();
        // Start checkpoint
        vm.prank(actors.ops.STAKING_NODES_OPERATOR);
        stakingNodeInstance.startCheckpoint(true);
        // Checkpoint ends since no active validators are here

        // Get final pod owner shares
        int256 finalPodOwnerShares = eigenPodManager.podOwnerShares(address(stakingNodeInstance));
        // Assert that the increase matches the swept rewards
        assertEq(uint256(finalPodOwnerShares), rewardsSweeped, "Pod owner shares increase should match swept rewards");
    }
}

contract StakingNodeDelegation is StakingNodeTestBase {
    using stdStorage for StdStorage;
    using BytesLib for bytes;

    function setUp() public override {
        super.setUp();
    }

    function testDelegateFailWhenNotAdmin() public {
        vm.prank(actors.ops.STAKING_NODE_CREATOR);
        IStakingNode stakingNodeInstance = stakingNodesManager.createStakingNode();
        vm.expectRevert();
        stakingNodeInstance.delegate(address(this), ISignatureUtils.SignatureWithExpiry({signature: "", expiry: 0}), bytes32(0));
    }

    function testStakingNodeDelegate() public {
        vm.prank(actors.ops.STAKING_NODE_CREATOR);
        IStakingNode stakingNodeInstance = stakingNodesManager.createStakingNode();
        IDelegationManager delegationManager = stakingNodesManager.delegationManager();
        IPausable pauseDelegationManager = IPausable(address(delegationManager));
        vm.prank(chainAddresses.eigenlayer.DELEGATION_PAUSER_ADDRESS);
        pauseDelegationManager.unpause(0);
        address operator = address(0x123);

        // register as operator
        vm.prank(operator);
        delegationManager.registerAsOperator(
            IDelegationManager.OperatorDetails({
                __deprecated_earningsReceiver: address(1), // unused
                delegationApprover: address(0),
                stakerOptOutWindowBlocks: 1
            }), 
            "ipfs://some-ipfs-hash"
        ); 
        vm.prank(actors.admin.STAKING_NODES_DELEGATOR);
        stakingNodeInstance.delegate(operator, ISignatureUtils.SignatureWithExpiry({signature: "", expiry: 0}), bytes32(0));

        address delegatedOperator = delegationManager.delegatedTo(address(stakingNodeInstance));
        assertEq(delegatedOperator, operator, "Delegation is not set to the right operator.");
    }

    function testStakingNodeUndelegate() public {
        vm.prank(actors.ops.STAKING_NODE_CREATOR);
        IStakingNode stakingNodeInstance = stakingNodesManager.createStakingNode();
        IDelegationManager delegationManager = stakingNodesManager.delegationManager();
        IPausable pauseDelegationManager = IPausable(address(delegationManager));
        
        // Unpause delegation manager to allow delegation
        vm.prank(chainAddresses.eigenlayer.DELEGATION_PAUSER_ADDRESS);
        pauseDelegationManager.unpause(0);

        // Register as operator and delegate
        delegationManager.registerAsOperator(
            IDelegationManager.OperatorDetails({
                __deprecated_earningsReceiver: address(1),
                delegationApprover: address(0),
                stakerOptOutWindowBlocks: 1
            }), 
            "ipfs://some-ipfs-hash"
        );
        
        vm.prank(actors.admin.STAKING_NODES_DELEGATOR);
        stakingNodeInstance.delegate(address(this), ISignatureUtils.SignatureWithExpiry({signature: "", expiry: 0}), bytes32(0));

        // // Attempt to undelegate with the wrong role
        vm.expectRevert();
        stakingNodeInstance.undelegate();

        IStrategyManager strategyManager = stakingNodesManager.strategyManager();
        uint256 stakerStrategyListLength = strategyManager.stakerStrategyListLength(address(stakingNodeInstance));
        assertEq(stakerStrategyListLength, 0, "Staker strategy list length should be 0.");
        
        // Now actually undelegate with the correct role
        vm.prank(actors.admin.STAKING_NODES_DELEGATOR);
        stakingNodeInstance.undelegate();
        
        // Verify undelegation
        address delegatedAddress = delegationManager.delegatedTo(address(stakingNodeInstance));
        assertEq(delegatedAddress, address(0), "Delegation should be cleared after undelegation.");
    }

    function testDelegateUndelegateAndDelegateAgain() public {
        address operator1 = address(0x9999);
        address operator2 = address(0x8888);

        address[] memory operators = new address[](2);
        operators[0] = operator1;
        operators[1] = operator2;

        for (uint i = 0; i < operators.length; i++) {
            vm.prank(operators[i]);
            delegationManager.registerAsOperator(
                IDelegationManager.OperatorDetails({
                    __deprecated_earningsReceiver: address(1),
                    delegationApprover: address(0),
                    stakerOptOutWindowBlocks: 1
                }), 
                "ipfs://some-ipfs-hash"
            );
        }

        vm.prank(actors.ops.STAKING_NODE_CREATOR);
        IStakingNode stakingNodeInstance = stakingNodesManager.createStakingNode();
        IDelegationManager delegationManager = stakingNodesManager.delegationManager();

        // Delegate to operator1
        vm.prank(actors.admin.STAKING_NODES_DELEGATOR);
        stakingNodeInstance.delegate(operator1, ISignatureUtils.SignatureWithExpiry({signature: "", expiry: 0}), bytes32(0));

        address delegatedOperator1 = delegationManager.delegatedTo(address(stakingNodeInstance));
        assertEq(delegatedOperator1, operator1, "Delegation is not set to operator1.");

        // Undelegate
        vm.prank(actors.admin.STAKING_NODES_DELEGATOR);
        stakingNodeInstance.undelegate();

        address undelegatedAddress = delegationManager.delegatedTo(address(stakingNodeInstance));
        assertEq(undelegatedAddress, address(0), "Delegation should be cleared after undelegation.");

        // Delegate to operator2
        vm.prank(actors.admin.STAKING_NODES_DELEGATOR);
        stakingNodeInstance.delegate(operator2, ISignatureUtils.SignatureWithExpiry({signature: "", expiry: 0}), bytes32(0));

        address delegatedOperator2 = delegationManager.delegatedTo(address(stakingNodeInstance));
        assertEq(delegatedOperator2, operator2, "Delegation is not set to operator2.");
    }

    function testImplementViewFunction() public {
        vm.prank(actors.ops.STAKING_NODE_CREATOR);
        IStakingNode stakingNodeInstance = stakingNodesManager.createStakingNode();
        address expectedImplementation = address(stakingNodesManager.upgradeableBeacon().implementation());
        assertEq(stakingNodeInstance.implementation(), expectedImplementation, "Implementation address mismatch");
    }
}

contract StakingNodeVerifyWithdrawalCredentials is StakingNodeTestBase {
    address user = vm.addr(156737);


    uint256 nodeId;
    uint40[] validatorIndices;
    uint256 AMOUNT = 32 ether;

    function setUp() public override {
        super.setUp();

        // Create a user address and fund it with 1000 ETH
        vm.deal(user, 1000 ether);

        yneth.depositETH{value: 1000 ether}(user);
    }
    struct StateSnapshot {
        uint256 totalAssets;
        uint256 totalSupply;
        uint256 stakingNodeBalance;
        uint256 queuedShares;
        uint256 withdrawnETH;
        uint256 unverifiedStakedETH;
        int256 podOwnerShares;
    }

    function takeSnapshot(uint256 nodeId) internal view returns (StateSnapshot memory) {
        return StateSnapshot({
            totalAssets: yneth.totalAssets(),
            totalSupply: yneth.totalSupply(),
            stakingNodeBalance: stakingNodesManager.nodes(nodeId).getETHBalance(),
            queuedShares: stakingNodesManager.nodes(nodeId).getQueuedSharesAmount(),
            withdrawnETH: stakingNodesManager.nodes(nodeId).getWithdrawnETH(),
            unverifiedStakedETH: stakingNodesManager.nodes(nodeId).unverifiedStakedETH(),
            podOwnerShares: eigenPodManager.podOwnerShares(address(stakingNodesManager.nodes(nodeId)))
        });
    }
    
    function testVerifyWithdrawalCredentialsForOneValidator() public {

        uint256 nodeId = createStakingNodes(1)[0];
        // Call createValidators with the nodeIds array and validatorCount
        validatorIndices = createValidators(repeat(nodeId, 1), 1);
        beaconChain.advanceEpoch_NoRewards();
        registerValidators(repeat(nodeId, 1));

        
        // Capture state before verification
        StateSnapshot memory before = takeSnapshot(nodeId);

        _verifyWithdrawalCredentials(nodeId, validatorIndices[0]);

        // Capture state after verification
        StateSnapshot memory afterVerification = takeSnapshot(nodeId);

        // Assert that ynETH totalAssets, totalSupply, and staking Node balance, queuedShares and withdrawnETH stay the same
        assertEq(afterVerification.totalAssets, before.totalAssets, "Total assets should not change");
        assertEq(afterVerification.totalSupply, before.totalSupply, "Total supply should not change");
        assertEq(afterVerification.stakingNodeBalance, before.stakingNodeBalance, "Staking node balance should not change");
        assertEq(afterVerification.queuedShares, before.queuedShares, "Queued shares should not change");
        assertEq(afterVerification.withdrawnETH, before.withdrawnETH, "Withdrawn ETH should not change");

        // Assert that unverifiedStakedETH decreases
        assertLt(afterVerification.unverifiedStakedETH, before.unverifiedStakedETH, "Unverified staked ETH should decrease");

        // Additional checks
        assertEq(afterVerification.unverifiedStakedETH, 0, "Unverified staked ETH should be 0 after verification");
        assertEq(uint256(eigenPodManager.podOwnerShares(address(stakingNodesManager.nodes(nodeId)))), AMOUNT, "Pod owner shares should equal AMOUNT");
    }

    function testVerifyWithdrawalCredentialsTwice() public {
        uint256 nodeId = createStakingNodes(1)[0];
        // Call createValidators with the nodeIds array and validatorCount
        validatorIndices = createValidators(repeat(nodeId, 1), 1);
        beaconChain.advanceEpoch_NoRewards();
        registerValidators(repeat(nodeId, 1));
        
        uint40 validatorIndex = validatorIndices[0];

        // First verification
        _verifyWithdrawalCredentials(nodeId, validatorIndex);

        // Try to verify withdrawal credentials again
        uint40[] memory _validators = new uint40[](1);
        _validators[0] = validatorIndex;
        
        CredentialProofs memory _proofs = beaconChain.getCredentialProofs(_validators);
        vm.startPrank(actors.ops.STAKING_NODES_OPERATOR);
        IEigenPodSimplified node = IEigenPodSimplified(address(stakingNodesManager.nodes(nodeId)));
        vm.expectRevert("EigenPod._verifyWithdrawalCredentials: validator must be inactive to prove withdrawal credentials");
        node.verifyWithdrawalCredentials({
            beaconTimestamp: _proofs.beaconTimestamp,
            stateRootProof: _proofs.stateRootProof,
            validatorIndices: _validators,
            validatorFieldsProofs: _proofs.validatorFieldsProofs,
            validatorFields: _proofs.validatorFields
        });
        vm.stopPrank();
    }

    function testVerifyCheckpointsForOneValidator() public {
        uint256 nodeId = createStakingNodes(1)[0];
        // Call createValidators with the nodeIds array and validatorCount
        validatorIndices = createValidators(repeat(nodeId, 1), 1);
        beaconChain.advanceEpoch_NoRewards();
        registerValidators(repeat(nodeId, 1));
        
        uint40 validatorIndex = validatorIndices[0];

        {
            _verifyWithdrawalCredentials(nodeId, validatorIndex);

            // check that unverifiedStakedETH is 0 and podOwnerShares is 32 ETH (AMOUNT)
            assertEq(stakingNodesManager.nodes(nodeId).unverifiedStakedETH(), 0, "_testVerifyWithdrawalCredentials: E0");
            assertEq(uint256(eigenPodManager.podOwnerShares(address(stakingNodesManager.nodes(nodeId)))), AMOUNT, "_testVerifyWithdrawalCredentials: E1");
        }

        beaconChain.advanceEpoch();
        // Capture initial state
        StateSnapshot memory initialState = takeSnapshot(nodeId);

        // start checkpoint
        {
            vm.startPrank(actors.ops.STAKING_NODES_OPERATOR);
            stakingNodesManager.nodes(nodeId).startCheckpoint(true);
            vm.stopPrank();

            // make sure startCheckpoint cant be called again, which means that the checkpoint has started
            IStakingNode _node = stakingNodesManager.nodes(nodeId);
            vm.expectRevert("EigenPod._startCheckpoint: must finish previous checkpoint before starting another");
            vm.prank(actors.ops.STAKING_NODES_OPERATOR);
            _node.startCheckpoint(true);
        }

        // Assert that state remains unchanged after starting checkpoint
        StateSnapshot memory afterStartCheckpoint = takeSnapshot(nodeId);
        assertEq(afterStartCheckpoint.totalAssets, initialState.totalAssets, "Total assets changed after starting checkpoint");
        assertEq(afterStartCheckpoint.totalSupply, initialState.totalSupply, "Total supply changed after starting checkpoint");
        assertEq(afterStartCheckpoint.stakingNodeBalance, initialState.stakingNodeBalance, "Node balance changed after starting checkpoint");
        assertEq(afterStartCheckpoint.queuedShares, initialState.queuedShares, "Queued shares changed after starting checkpoint");
        assertEq(afterStartCheckpoint.withdrawnETH, initialState.withdrawnETH, "Withdrawn ETH changed after starting checkpoint");
        assertEq(afterStartCheckpoint.unverifiedStakedETH, initialState.unverifiedStakedETH, "Unverified staked ETH changed after starting checkpoint");

        // verify checkpoints
        {
            uint40[] memory _validators = new uint40[](1);
            _validators[0] = validatorIndex;
            IStakingNode _node = stakingNodesManager.nodes(nodeId);
            CheckpointProofs memory _cpProofs = beaconChain.getCheckpointProofs(_validators, _node.eigenPod().currentCheckpointTimestamp());
            IEigenPodSimplified(address(_node.eigenPod())).verifyCheckpointProofs({
                balanceContainerProof: _cpProofs.balanceContainerProof,
                proofs: _cpProofs.balanceProofs
            });

            // check that proofsRemaining is 0
            IEigenPod.Checkpoint memory _checkpoint = stakingNodesManager.nodes(nodeId).eigenPod().currentCheckpoint();
            assertEq(_checkpoint.proofsRemaining, 0, "_testVerifyCheckpointsBeforeWithdrawalRequest: E0");

            // Assert that node balance and shares increased by the amount of rewards
            StateSnapshot memory afterVerification = takeSnapshot(nodeId);
            uint256 rewardsAmount = uint256(afterVerification.podOwnerShares - initialState.podOwnerShares);
            // Calculate expected rewards for one epoch
            uint256 expectedRewards = 1 * 1 * 1e9; // 1 GWEI per Epoch per Validator;
            assertApproxEqAbs(rewardsAmount, expectedRewards, 1, "Rewards amount does not match expected value for one epoch");

            assertEq(afterVerification.stakingNodeBalance, initialState.stakingNodeBalance + rewardsAmount, "Node balance did not increase by rewards amount");

            // Assert that other state variables remain unchanged
            assertEq(afterVerification.totalAssets, initialState.totalAssets + expectedRewards, "Total assets changed after verification");
            assertEq(afterVerification.totalSupply, initialState.totalSupply, "Total supply changed after verification");
            assertEq(afterVerification.queuedShares, initialState.queuedShares, "Queued shares changed after verification");
            assertEq(afterVerification.withdrawnETH, initialState.withdrawnETH, "Withdrawn ETH changed after verification");
            assertEq(afterVerification.unverifiedStakedETH, initialState.unverifiedStakedETH, "Unverified staked ETH changed after verification");
        }
    }


    function testVerifyCheckpointsForManyValidators() public {

        uint256 validatorCount = 10;

        uint256 nodeId = createStakingNodes(1)[0];
        // Call createValidators with the nodeIds array and validatorCount
        validatorIndices = createValidators(repeat(nodeId, 1), validatorCount);
        beaconChain.advanceEpoch_NoRewards();
        registerValidators(repeat(nodeId, validatorCount));
        

        {
            for (uint256 i = 0; i < validatorIndices.length; i++) {
                _verifyWithdrawalCredentials(nodeId, validatorIndices[i]);
            }

            // check that unverifiedStakedETH is 0 and podOwnerShares is 32 ETH (AMOUNT)
            assertEq(stakingNodesManager.nodes(nodeId).unverifiedStakedETH(), 0, "_testVerifyWithdrawalCredentials: E0");
            assertEq(
                uint256(eigenPodManager.podOwnerShares(address(stakingNodesManager.nodes(nodeId)))),
                AMOUNT * validatorCount,
                "_testVerifyWithdrawalCredentials: E1"
            );
        }

        beaconChain.advanceEpoch_NoRewards();

        uint256 exitedValidatorsCount = 5;

        // exit validators
        {
            for (uint256 i = 0; i < exitedValidatorsCount; i++) {
                beaconChain.exitValidator(validatorIndices[i]);
            }
            beaconChain.advanceEpoch_NoRewards();
        }
        // Take snapshot before starting checkpoint
        StateSnapshot memory beforeStart = takeSnapshot(nodeId);

        // start checkpoint
        {
            vm.startPrank(actors.ops.STAKING_NODES_OPERATOR);
            stakingNodesManager.nodes(nodeId).startCheckpoint(true);
            vm.stopPrank();

            // make sure startCheckpoint cant be called again, which means that the checkpoint has started
            IStakingNode _node = stakingNodesManager.nodes(nodeId);
            vm.expectRevert("EigenPod._startCheckpoint: must finish previous checkpoint before starting another");
            vm.prank(actors.ops.STAKING_NODES_OPERATOR);
            _node.startCheckpoint(true);
        }

        // Take snapshot after starting checkpoint
        StateSnapshot memory afterStart = takeSnapshot(nodeId);

        // Assert state after starting checkpoint
        assertEq(afterStart.totalAssets, beforeStart.totalAssets, "Total assets should not change after starting checkpoint");
        assertEq(afterStart.totalSupply, beforeStart.totalSupply, "Total supply should not change after starting checkpoint");
        assertEq(afterStart.stakingNodeBalance, beforeStart.stakingNodeBalance, "Staking node balance should not change after starting checkpoint");
        assertEq(afterStart.queuedShares, beforeStart.queuedShares, "Queued shares should not change after starting checkpoint");
        assertEq(afterStart.withdrawnETH, beforeStart.withdrawnETH, "Withdrawn ETH should not change after starting checkpoint");
        assertEq(afterStart.unverifiedStakedETH, beforeStart.unverifiedStakedETH, "Unverified staked ETH should not change after starting checkpoint");
        assertEq(afterStart.podOwnerShares, beforeStart.podOwnerShares, "Pod owner shares should not change after starting checkpoint");

        // verify checkpoints
        {
            uint40[] memory _validators = validatorIndices;
            IStakingNode _node = stakingNodesManager.nodes(nodeId);
            CheckpointProofs memory _cpProofs = beaconChain.getCheckpointProofs(_validators, _node.eigenPod().currentCheckpointTimestamp());
            IEigenPodSimplified(address(_node.eigenPod())).verifyCheckpointProofs({
                balanceContainerProof: _cpProofs.balanceContainerProof,
                proofs: _cpProofs.balanceProofs
            });

            // Take snapshot after verifying checkpoint
            StateSnapshot memory afterVerify = takeSnapshot(nodeId);

            // Assert state after verifying checkpoint
            assertEq(afterVerify.totalAssets, afterStart.totalAssets, "Total assets should not change after verifying checkpoint");
            assertEq(afterVerify.totalSupply, afterStart.totalSupply, "Total supply should not change after verifying checkpoint");
            assertGe(afterVerify.stakingNodeBalance, afterStart.stakingNodeBalance, "Staking node balance should not decrease after verifying checkpoint");
            assertEq(afterVerify.queuedShares, afterStart.queuedShares, "Queued shares should not change after verifying checkpoint");
            assertEq(afterVerify.withdrawnETH, afterStart.withdrawnETH, "Withdrawn ETH should not change after verifying checkpoint");
            assertEq(afterVerify.unverifiedStakedETH, afterStart.unverifiedStakedETH, "Unverified staked ETH should not change after verifying checkpoint");
            assertGe(afterVerify.podOwnerShares, afterStart.podOwnerShares, "Pod owner shares should not decrease after verifying checkpoint");

            IEigenPod.Checkpoint memory _checkpoint = stakingNodesManager.nodes(nodeId).eigenPod().currentCheckpoint();
            assertEq(_checkpoint.proofsRemaining, 0, "_testVerifyCheckpointsBeforeWithdrawalRequest: E0");
            assertApproxEqAbs(
                uint256(eigenPodManager.podOwnerShares(address(stakingNodesManager.nodes(nodeId)))),
                AMOUNT * validatorCount,
                1000000000,
                "_testVerifyCheckpointsBeforeWithdrawalRequest: E1"
            );
        }
    }
}

// contract StakingNodeStakedETHAllocationTests is StakingNodeTestBase {

//     event AllocatedStakedETH(uint256 previousAmount, uint256 newAmount);

//     function testAllocateStakedETH() public {
//         (IStakingNode stakingNodeInstance,) = setupStakingNode(32 ether);
//         uint256 initialETHBalance = stakingNodeInstance.getETHBalance();
//         uint256 amountToAllocate = 10 ether;

//         vm.expectEmit(true, true, false, true);
//         emit AllocatedStakedETH(initialETHBalance, amountToAllocate);
//         vm.prank(address(stakingNodesManager));
//         stakingNodeInstance.allocateStakedETH(amountToAllocate);

//         uint256 newETHBalance = stakingNodeInstance.getETHBalance();
//         assertEq(newETHBalance, initialETHBalance + amountToAllocate, "ETH balance did not increase by the allocated amount");
//     }

//     function testAllocateStakedETHFailsWhenNotStakingNodesManager() public {
//         (IStakingNode stakingNodeInstance,) = setupStakingNode(32 ether);
//         uint256 amountToAllocate = 10 ether;

//         vm.expectRevert(StakingNode.NotStakingNodesManager.selector);
//         vm.prank(actors.eoa.DEFAULT_SIGNER);
//         stakingNodeInstance.allocateStakedETH(amountToAllocate);
//     }

//     function testGetETHBalanceWithAllocationAndEigenPodDeposit() public {
//         (IStakingNode stakingNodeInstance, IEigenPod eigenPodInstance) = setupStakingNode(32 ether);
//         uint256 initialETHBalance = stakingNodeInstance.getETHBalance();
//         uint256 amountToAllocate = 10 ether;
//         uint256 amountToDepositInEigenPod = 5 ether;

//         // Allocate ETH to the staking node
//         vm.prank(address(stakingNodesManager));
//         stakingNodeInstance.allocateStakedETH(amountToAllocate);

//         // Deposit ETH directly to the EigenPod
//         address payable eigenPodAddress = payable(address(eigenPodInstance));
//         vm.deal(address(this), amountToDepositInEigenPod);
//         (bool success,) = eigenPodAddress.call{value: amountToDepositInEigenPod}("");
//         require(success, "Failed to send ETH to EigenPod");

//         uint256 expectedETHBalance = initialETHBalance + amountToAllocate;
//         uint256 actualETHBalance = stakingNodeInstance.getETHBalance();

//         assertEq(actualETHBalance, expectedETHBalance, "ETH balance does not match expected value after allocation and EigenPod deposit");
//     }
// }


// contract StakingNodeMiscTests is StakingNodeTestBase {

//     function testSendingETHToStakingNodeShouldRevert() public {
//         (IStakingNode stakingNodeInstance,) = setupStakingNode(32 ether);
//         uint256 amountToSend = 1 ether;

//         // Attempt to send ETH to the StakingNode contract
//         (bool sent, ) = address(stakingNodeInstance).call{value: amountToSend}("");
//         assertFalse(sent, "Sending ETH should fail");
//     }
// }
