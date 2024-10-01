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

    string DEFAULT_PROOFS_PATH = "lib/eigenlayer-contracts/src/test/test-data/fullWithdrawalProof_Latest.json";

    struct VerifyWithdrawalCredentialsCallParams {
        uint64 oracleTimestamp;
        ValidatorProofs validatorProofs;
        IStakingNode stakingNodeInstance;
    }

    struct ValidatorProofs {
        BeaconChainProofs.StateRootProof stateRootProof;
        uint40[] validatorIndices;
        bytes[] withdrawalCredentialProofs;
        bytes[] validatorFieldsProofs;
        bytes32[][] validatorFields;
    }

    function setupStakingNode(uint256 depositAmount) public returns (IStakingNode, IEigenPod) {

        address addr1 = vm.addr(100);

        require(depositAmount % 32 ether == 0, "depositAmount must be a multiple of 32 ether");

        uint256 validatorCount = depositAmount / 32 ether;

        vm.deal(addr1, depositAmount);

        vm.prank(addr1);
        yneth.depositETH{value: depositAmount}(addr1);

        vm.prank(actors.ops.STAKING_NODE_CREATOR);
        IStakingNode stakingNodeInstance = stakingNodesManager.createStakingNode();

        uint256 nodeId = 0;

        IStakingNodesManager.ValidatorData[] memory validatorData = new IStakingNodesManager.ValidatorData[](validatorCount);
        for (uint256 i = 0; i < validatorCount; i++) {
            bytes memory publicKey = abi.encodePacked(uint256(i));
            publicKey = bytes.concat(publicKey, new bytes(ZERO_PUBLIC_KEY.length - publicKey.length));
            validatorData[i] = IStakingNodesManager.ValidatorData({
                publicKey: publicKey,
                signature: ZERO_SIGNATURE,
                nodeId: nodeId,
                depositDataRoot: bytes32(0)
            });
        }

        bytes memory withdrawalCredentials = stakingNodesManager.getWithdrawalCredentials(nodeId);

        for (uint256 i = 0; i < validatorData.length; i++) {
            uint256 amount = depositAmount / validatorData.length;
            bytes32 depositDataRoot = stakingNodesManager.generateDepositRoot(validatorData[i].publicKey, validatorData[i].signature, withdrawalCredentials, amount);
            validatorData[i].depositDataRoot = depositDataRoot;
        }
        
        vm.prank(actors.ops.VALIDATOR_MANAGER);
        stakingNodesManager.registerValidators(validatorData);

        uint256 actualETHBalance = stakingNodeInstance.getETHBalance();
        assertEq(actualETHBalance, depositAmount, "ETH balance does not match expected value");

        IEigenPod eigenPodInstance = stakingNodeInstance.eigenPod();

        return (stakingNodeInstance, eigenPodInstance);
    }

    function _getLatestBlockRoot() public returns (bytes32) {
        return getLatestBlockRoot();
    }

    function getWithdrawalCredentialParams() public returns (ValidatorProofs memory) {
        ValidatorProofs memory validatorProofs;
        
        validatorProofs.validatorIndices = new uint40[](1);
        validatorProofs.withdrawalCredentialProofs = new bytes[](1);
        validatorProofs.validatorFieldsProofs = new bytes[](1);
        validatorProofs.validatorFields = new bytes32[][](1);

        // Set beacon state root, validatorIndex
        validatorProofs.stateRootProof.beaconStateRoot = getBeaconStateRoot();
        validatorProofs.stateRootProof.proof = getStateRootProof();
        validatorProofs.validatorIndices[0] = uint40(getValidatorIndex());
        validatorProofs.withdrawalCredentialProofs[0] = abi.encodePacked(getWithdrawalCredentialProof()); // Validator fields are proven here
        // validatorProofs.validatorFieldsProofs[0] = getWithdrawalCredentialProof();
        validatorProofs.validatorFields[0] = getValidatorFields();

        return validatorProofs;
    }

    function bytes32ToData(bytes32 data) public pure returns (address) {
        return address(uint160(uint256(data)));
    }

    function getWithdrawalAddress() public returns (address) {
        bytes32[] memory validatorFields = getValidatorFields();
        return bytes32ToData(validatorFields[1]);
    }
}


contract StakingNodeEigenPod is StakingNodeTestBase {

   // FIXME: update or delete to accomdate for M3
    function testCreateNodeAndVerifyPodStateIsValid() public {

        uint depositAmount = 32 ether;

        (IStakingNode stakingNodeInstance, IEigenPod eigenPodInstance) = setupStakingNode(depositAmount);

        // Collapsed variable declarations into direct usage within assertions and conditions

        // TODO: double check this is the desired state for a pod.
        // we can't delegate on mainnet at this time so one should be able to farm points without delegating
        assertEq(eigenPodInstance.withdrawableRestakedExecutionLayerGwei(), 0, "Restaked Gwei should be 0");
        assertEq(address(eigenPodManager), address(eigenPodInstance.eigenPodManager()), "EigenPodManager should match");
        assertEq(eigenPodInstance.podOwner(), address(stakingNodeInstance), "Pod owner address does not match");

        address payable eigenPodAddress = payable(address(eigenPodInstance));
        // simulate ETH entering the pod by direct transfer as non-beacon chain ETH
        uint256 rewardsSweeped = 1 ether;
        vm.deal(address(this), rewardsSweeped);
        (bool success,) = eigenPodAddress.call{value: rewardsSweeped}("");
        require(success, "Failed to send rewards to EigenPod");

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
    
    function testVerifyWithdrawalCredentialsForOneValidator() public {

        uint256 nodeId = createStakingNodes(1)[0];
        // Call createValidators with the nodeIds array and validatorCount
        validatorIndices = createValidators(repeat(nodeId, 1), 1);
        beaconChain.advanceEpoch_NoRewards();
        registerValidators(repeat(nodeId, 1));

        
         // Capture state before verification
         uint256 totalAssetsBefore = yneth.totalAssets();
         uint256 totalSupplyBefore = yneth.totalSupply();
         uint256 stakingNodeBalanceBefore = stakingNodesManager.nodes(nodeId).getETHBalance();
         uint256 queuedSharesBefore = stakingNodesManager.nodes(nodeId).queuedShares();
         uint256 withdrawnETHBefore = stakingNodesManager.nodes(nodeId).withdrawnETH();
         uint256 unverifiedStakedETHBefore = stakingNodesManager.nodes(nodeId).unverifiedStakedETH();

         _verifyWithdrawalCredentials(nodeId, validatorIndices[0]);

         // Capture state after verification
         uint256 totalAssetsAfter = yneth.totalAssets();
         uint256 totalSupplyAfter = yneth.totalSupply();
         uint256 stakingNodeBalanceAfter = stakingNodesManager.nodes(nodeId).getETHBalance();
         uint256 queuedSharesAfter = stakingNodesManager.nodes(nodeId).queuedShares();
         uint256 withdrawnETHAfter = stakingNodesManager.nodes(nodeId).withdrawnETH();
         uint256 unverifiedStakedETHAfter = stakingNodesManager.nodes(nodeId).unverifiedStakedETH();

         // Assert that ynETH totalAssets, totalSupply, and staking Node balance, queuedShares and withdrawnETH stay the same
         assertEq(totalAssetsAfter, totalAssetsBefore, "Total assets should not change");
         assertEq(totalSupplyAfter, totalSupplyBefore, "Total supply should not change");
         assertEq(stakingNodeBalanceAfter, stakingNodeBalanceBefore, "Staking node balance should not change");
         assertEq(queuedSharesAfter, queuedSharesBefore, "Queued shares should not change");
         assertEq(withdrawnETHAfter, withdrawnETHBefore, "Withdrawn ETH should not change");

         // Assert that unverifiedStakedETH decreases
         assertLt(unverifiedStakedETHAfter, unverifiedStakedETHBefore, "Unverified staked ETH should decrease");

         // Additional checks
         assertEq(unverifiedStakedETHAfter, 0, "Unverified staked ETH should be 0 after verification");
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

            // check that proofsRemaining is 0 and podOwnerShares is still 32 ETH (AMOUNT)
            IEigenPod.Checkpoint memory _checkpoint = stakingNodesManager.nodes(nodeId).eigenPod().currentCheckpoint();
            assertEq(_checkpoint.proofsRemaining, 0, "_testVerifyCheckpointsBeforeWithdrawalRequest: E0");
            assertApproxEqAbs(uint256(eigenPodManager.podOwnerShares(address(stakingNodesManager.nodes(nodeId)))), AMOUNT, 1000000000, "_testVerifyCheckpointsBeforeWithdrawalRequest: E1");
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

        // verify checkpoints
        {
            uint40[] memory _validators = validatorIndices;
            IStakingNode _node = stakingNodesManager.nodes(nodeId);
            CheckpointProofs memory _cpProofs = beaconChain.getCheckpointProofs(_validators, _node.eigenPod().currentCheckpointTimestamp());
            IEigenPodSimplified(address(_node.eigenPod())).verifyCheckpointProofs({
                balanceContainerProof: _cpProofs.balanceContainerProof,
                proofs: _cpProofs.balanceProofs
            });

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

    function createStakingNodes(uint nodeCount) public returns (uint256[] memory) {
        uint256[] memory nodeIds = new uint256[](nodeCount);
        for (uint256 i = 0; i < nodeCount; i++) {
            vm.prank(actors.ops.STAKING_NODE_CREATOR);
            IStakingNode node = stakingNodesManager.createStakingNode();
            nodeIds[i] = node.nodeId();
        }
        return nodeIds;
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
