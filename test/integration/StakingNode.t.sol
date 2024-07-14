// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {UpgradeableBeacon} from "lib/openzeppelin-contracts/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {OwnableUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {IPausable} from "lib/eigenlayer-contracts/src/contracts/interfaces/IPausable.sol";
import {IDelegationManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IBeaconChainOracle} from "lib/eigenlayer-contracts/src/contracts/interfaces/IBeaconChainOracle.sol";
import {IntegrationBaseTest} from "test/integration/IntegrationBaseTest.sol";
import {IStakingNode} from "src/interfaces/IStakingNode.sol";
import {IStakingNodesManager} from "src/interfaces/IStakingNodesManager.sol";
import {IEigenPod} from "lib/eigenlayer-contracts/src/contracts/interfaces/IEigenPod.sol";
import {IDelayedWithdrawalRouter} from "lib/eigenlayer-contracts/src/contracts/interfaces/IDelayedWithdrawalRouter.sol";
import {BeaconChainProofs} from "lib/eigenlayer-contracts/src/contracts/libraries/BeaconChainProofs.sol";
import {IStrategyManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol"; 
import {StakingNode} from "src/StakingNode.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol"; 
import {ProofUtils} from "test/utils/ProofUtils.sol";
import {ISignatureUtils} from "lib/eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";
import { MockEigenLayerBeaconOracle } from "../mocks/MockEigenLayerBeaconOracle.sol";
import {BytesLib} from "lib/eigenlayer-contracts/src/contracts/libraries/BytesLib.sol";
import { EigenPod } from "lib/eigenlayer-contracts/src/contracts/pods/EigenPod.sol";
import {MockEigenPod} from "../mocks/MockEigenPod.sol";
import { MockEigenPodManager } from "../mocks/MockEigenPodManager.sol";
import { MockStakingNode } from "../mocks/MockStakingNode.sol";
import { EigenPodManager } from "lib/eigenlayer-contracts/src/contracts/pods/EigenPodManager.sol";
import {IETHPOSDeposit} from "lib/eigenlayer-contracts/src/contracts/interfaces/IETHPOSDeposit.sol";
import {IEigenPodManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IEigenPodManager.sol";
import {IEigenPod} from "lib/eigenlayer-contracts/src/contracts/interfaces/IEigenPod.sol";
import {IDelayedWithdrawalRouter} from "lib/eigenlayer-contracts/src/contracts/interfaces/IDelayedWithdrawalRouter.sol";
import { TransparentUpgradeableProxy } from "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { ProofParsingV1 } from "test/eigenlayer-utils/ProofParsingV1.sol";
import {Utils} from "script/Utils.sol";


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

    function testCreateNodeAndVerifyPodStateIsValid() public {

        uint depositAmount = 32 ether;

        (IStakingNode stakingNodeInstance, IEigenPod eigenPodInstance) = setupStakingNode(depositAmount);

        // Collapsed variable declarations into direct usage within assertions and conditions

        // TODO: double check this is the desired state for a pod.
        // we can't delegate on mainnet at this time so one should be able to farm points without delegating
        assertEq(eigenPodInstance.withdrawableRestakedExecutionLayerGwei(), 0, "Restaked Gwei should be 0");
        assertEq(address(eigenPodManager), address(eigenPodInstance.eigenPodManager()), "EigenPodManager should match");
        assertEq(eigenPodInstance.podOwner(), address(stakingNodeInstance), "Pod owner address does not match");
        assertEq(eigenPodInstance.mostRecentWithdrawalTimestamp(), 0, "Most recent withdrawal block should be greater than 0");

        address payable eigenPodAddress = payable(address(eigenPodInstance));
        // simulate ETH entering the pod by direct transfer as non-beacon chain ETH
        uint256 rewardsSweeped = 1 ether;
        vm.deal(address(this), rewardsSweeped);
        (bool success,) = eigenPodAddress.call{value: rewardsSweeped}("");
        require(success, "Failed to send rewards to EigenPod");

        // trigger non beacon chain ETH withdrawal
        vm.startPrank(actors.ops.STAKING_NODES_OPERATOR);
        stakingNodeInstance.withdrawNonBeaconChainETHBalanceWei();
        vm.stopPrank();

        IDelayedWithdrawalRouter delayedWithdrawalRouter = stakingNodesManager.delayedWithdrawalRouter();
        uint256 withdrawalDelayBlocks = delayedWithdrawalRouter.withdrawalDelayBlocks();
        vm.roll(block.number + withdrawalDelayBlocks + 1);

        delayedWithdrawalRouter.claimDelayedWithdrawals(address(stakingNodeInstance), type(uint256).max);

        uint256 balanceBeforeClaim = address(consensusLayerReceiver).balance;
        vm.prank(actors.ops.STAKING_NODES_OPERATOR);
        stakingNodeInstance.processDelayedWithdrawals();
        uint256 balanceAfterClaim = address(consensusLayerReceiver).balance;
        uint256 rewardsAmount = balanceAfterClaim - balanceBeforeClaim;

        assertEq(rewardsAmount, rewardsSweeped, "Rewards amount does not match expected value");

        rewardsDistributor.processRewards();

        uint256 fee = uint256(rewardsDistributor.feesBasisPoints());
        uint256 finalRewardsReceived = rewardsAmount - (rewardsAmount * fee / 10000);

        // Assert total assets after claiming delayed withdrawals
        uint256 totalAssets = yneth.totalAssets();
        assertEq(totalAssets, finalRewardsReceived + depositAmount, "Total assets after claiming delayed withdrawals do not match expected value");
    }
}


contract StakingNodeWithdrawNonBeaconChainETHBalanceWei is StakingNodeTestBase {
    using stdStorage for StdStorage;

    function testWithdrawNonBeaconChainETHBalanceWeiAndProcessNonBeaconChainETHWithdrawals() public {

        (IStakingNode stakingNodeInstance, IEigenPod eigenPodInstance) = setupStakingNode(32 ether);

       address payable eigenPodAddress = payable(address(eigenPodInstance));
        // simulate ETH entering the pod by direct transfer as non-beacon chain ETH
        uint256 rewardsSweeped = 1 ether;
        vm.deal(address(this), rewardsSweeped);
        (bool success,) = eigenPodAddress.call{value: rewardsSweeped}("");
        require(success, "Failed to send rewards to EigenPod");

        // trigger withdrawNonBeaconChainETHBalanceWei succesfully
        vm.startPrank(actors.ops.STAKING_NODES_OPERATOR);
        stakingNodeInstance.withdrawNonBeaconChainETHBalanceWei();
        vm.stopPrank();

        IDelayedWithdrawalRouter delayedWithdrawalRouter = stakingNodesManager.delayedWithdrawalRouter();
        uint256 withdrawalDelayBlocks = delayedWithdrawalRouter.withdrawalDelayBlocks();
        vm.roll(block.number + withdrawalDelayBlocks + 1);

        delayedWithdrawalRouter.claimDelayedWithdrawals(address(stakingNodeInstance), type(uint256).max);

        uint256 balanceBeforeClaim = address(consensusLayerReceiver).balance;
        vm.prank(actors.ops.STAKING_NODES_OPERATOR);
        stakingNodeInstance.processDelayedWithdrawals();
        uint256 balanceAfterClaim = address(consensusLayerReceiver).balance;
        uint256 rewardsAmount = balanceAfterClaim - balanceBeforeClaim;

        assertEq(rewardsAmount, rewardsSweeped, "Rewards amount does not match expected value");
    }

   function testWithdrawNonBeaconChainETHBalanceWeiAndProcessNonBeaconChainETHWithdrawalsForALargeAmount() public {

        (IStakingNode stakingNodeInstance, IEigenPod eigenPodInstance) = setupStakingNode(32 ether);

       address payable eigenPodAddress = payable(address(eigenPodInstance));
       
        // a large amount of ETH from an arbitrary source is sent to the EigenPod
        uint256 rewardsSweeped = 1000 ether;
        vm.deal(address(this), rewardsSweeped);
        (bool success,) = eigenPodAddress.call{value: rewardsSweeped}("");
        require(success, "Failed to send rewards to EigenPod");

        // trigger withdraw before restaking succesfully
        vm.startPrank(actors.ops.STAKING_NODES_OPERATOR);
        stakingNodeInstance.withdrawNonBeaconChainETHBalanceWei();
        vm.stopPrank();

        IDelayedWithdrawalRouter delayedWithdrawalRouter = stakingNodesManager.delayedWithdrawalRouter();
        uint256 withdrawalDelayBlocks = delayedWithdrawalRouter.withdrawalDelayBlocks();
        vm.roll(block.number + withdrawalDelayBlocks + 1);

        delayedWithdrawalRouter.claimDelayedWithdrawals(address(stakingNodeInstance), type(uint256).max);

        uint256 balanceBeforeClaim = address(consensusLayerReceiver).balance;
        vm.prank(actors.ops.STAKING_NODES_OPERATOR);
        stakingNodeInstance.processDelayedWithdrawals();
        uint256 balanceAfterClaim = address(consensusLayerReceiver).balance;
        uint256 rewardsAmount = balanceAfterClaim - balanceBeforeClaim;

        assertEq(rewardsAmount, rewardsSweeped, "Rewards amount does not match expected value");
    }

   function testProcessNonBeaconChainETHWithdrawalsWithExistingValidatorPrincipal() public {

       uint256 activeValidators = 5;

       uint256 depositAmount = activeValidators * 32 ether;

       (IStakingNode stakingNodeInstance, IEigenPod eigenPodInstance) = setupStakingNode(depositAmount);

       address payable eigenPodAddress = payable(address(eigenPodInstance));
        // Arbitrary rewards sent to the Eigenpod
        uint256 rewardsSweeped = 100 ether;
        vm.deal(address(this), rewardsSweeped);
        (bool success,) = eigenPodAddress.call{value: rewardsSweeped}("");
        require(success, "Failed to send rewards to EigenPod");

        // trigger withdraw before restaking succesfully
        vm.startPrank(actors.ops.STAKING_NODES_OPERATOR);
        stakingNodeInstance.withdrawNonBeaconChainETHBalanceWei();
        vm.stopPrank();

        IDelayedWithdrawalRouter delayedWithdrawalRouter = stakingNodesManager.delayedWithdrawalRouter();
        vm.roll(block.number + delayedWithdrawalRouter.withdrawalDelayBlocks() + 1);

        delayedWithdrawalRouter.claimDelayedWithdrawals(address(stakingNodeInstance), type(uint256).max);

        uint256 balanceBeforeClaim = address(consensusLayerReceiver).balance;

        vm.prank(actors.ops.STAKING_NODES_OPERATOR);
        stakingNodeInstance.processDelayedWithdrawals();
        uint256 balanceAfterClaim = address(consensusLayerReceiver).balance;
        uint256 rewardsAmount = balanceAfterClaim - balanceBeforeClaim;

        assertEq(stakingNodeInstance.getETHBalance(), depositAmount, "StakingNode ETH balance does not match expected value");
        assertEq(rewardsAmount, rewardsSweeped, "Rewards amount does not match expected value");
    }

    function testProcessNonBeaconChainETHWithdrawalsWhenETHArrivesFromBeaconChainAsWell() public {

       uint256 activeValidators = 5;

       uint256 depositAmount = activeValidators * 32 ether;

       (IStakingNode stakingNodeInstance, IEigenPod eigenPodInstance) = setupStakingNode(depositAmount);

       address payable eigenPodAddress = payable(address(eigenPodInstance));
        // Arbitrary rewards sent to the Eigenpod
        uint256 rewardsSweeped = 100 ether;
        vm.deal(address(this), rewardsSweeped);
        (bool success,) = eigenPodAddress.call{value: rewardsSweeped}("");
        require(success, "Failed to send rewards to EigenPod");

        uint256 withdrawnValidators = 1;
        uint256 withdrawnPrincipal = withdrawnValidators * 32 ether;

        // this increases the balance of the EigenPod without triggering
        // receive or fallback just like beacon chain ETH rewards or withdrawals would
        vm.deal(eigenPodAddress, eigenPodAddress.balance + withdrawnPrincipal);
        uint256 expectedBalance = rewardsSweeped + withdrawnPrincipal;
        assertEq(address(eigenPodInstance).balance, expectedBalance, "EigenPod balance does not match expected value");

        // trigger withdraw before restaking succesfully
        vm.startPrank(actors.ops.STAKING_NODES_OPERATOR);
        stakingNodeInstance.withdrawNonBeaconChainETHBalanceWei();
        vm.stopPrank();


        IDelayedWithdrawalRouter delayedWithdrawalRouter = stakingNodesManager.delayedWithdrawalRouter();
        vm.roll(block.number + delayedWithdrawalRouter.withdrawalDelayBlocks() + 1);

        delayedWithdrawalRouter.claimDelayedWithdrawals(address(stakingNodeInstance), type(uint256).max);

        uint256 balanceBeforeClaim = address(consensusLayerReceiver).balance;

        vm.prank(actors.ops.STAKING_NODES_OPERATOR);
        stakingNodeInstance.processDelayedWithdrawals();
        uint256 balanceAfterClaim = address(consensusLayerReceiver).balance;
        uint256 rewardsAmount = balanceAfterClaim - balanceBeforeClaim;

        // assertEq(stakingNodeInstance.getETHBalance(), depositAmount, "StakingNode ETH balance does not match expected value");
        assertEq(rewardsAmount, rewardsSweeped, "Rewards amount does not match expected value");
    }
}

contract StakingNodeVerifyWithdrawalCredentials is StakingNodeTestBase {
    using stdStorage for StdStorage;
    using BytesLib for bytes;

    address newMockStakingNodeImplementation;

    function setUp() public override {
        super.setUp();
        // Set the implementation of the StakingNode to be MockStakingNode
        newMockStakingNodeImplementation = address(new MockStakingNode());
        vm.prank(actors.admin.STAKING_ADMIN);
        stakingNodesManager.upgradeStakingNodeImplementation(newMockStakingNodeImplementation);
    }

    function skiptestVerifyWithdrawalCredentialsRevertingWhenPaused() public {

        ProofUtils proofUtils = new ProofUtils(DEFAULT_PROOFS_PATH);

        uint256 depositAmount = 32 ether;
        (IStakingNode stakingNodeInstance,) = setupStakingNode(depositAmount);

        uint64 oracleTimestamp = uint64(block.timestamp);

		BeaconChainProofs.StateRootProof memory stateRootProof = proofUtils._getStateRootProof();

		uint40[] memory validatorIndexes = new uint40[](1);

		validatorIndexes[0] = uint40(proofUtils.getValidatorIndex());

        bytes[] memory validatorFieldsProofs = proofUtils._getValidatorFieldsProof();

		bytes32[][] memory validatorFields = new bytes32[][](1);
        validatorFields[0] = proofUtils.getValidatorFields();

        uint256 shares = strategyManager.stakerStrategyShares(address(stakingNodeInstance), stakingNodeInstance.beaconChainETHStrategy());
        assertEq(shares, depositAmount, "Shares do not match deposit amount");

        vm.expectRevert("Pausable: index is paused");
        vm.prank(actors.ops.STAKING_NODES_OPERATOR);
        stakingNodeInstance.verifyWithdrawalCredentials(
            oracleTimestamp,
            stateRootProof,
            validatorIndexes,
            validatorFieldsProofs,
            validatorFields
        );
    }

    function testCreateEigenPodReturnsEigenPodAddressAfterCreated() public {
        vm.prank(actors.ops.STAKING_NODE_CREATOR);
        IStakingNode stakingNodeInstance = stakingNodesManager.createStakingNode();
        IEigenPod eigenPodInstance = stakingNodeInstance.eigenPod();
        assertEq(address(eigenPodInstance), address(stakingNodeInstance.eigenPod()));
    }

    function testClaimDelayedWithdrawals() public {

        vm.prank(actors.ops.STAKING_NODE_CREATOR);
        IStakingNode stakingNodeInstance = stakingNodesManager.createStakingNode();

        vm.prank(actors.ops.STAKING_NODES_OPERATOR);
        vm.expectRevert();
        stakingNodeInstance.processDelayedWithdrawals();
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
                earningsReceiver: operator,
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
                earningsReceiver: address(this),
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
                    earningsReceiver: operators[i],
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
        assertEq(stakingNodeInstance.implementation(), address(newMockStakingNodeImplementation));
    }

    function testVerifyWithdrawalCredentialsWithWrongWithdrawalAddress() public {

        ProofUtils proofUtils = new ProofUtils(DEFAULT_PROOFS_PATH);

        uint256 depositAmount = 32 ether;
        (IStakingNode stakingNodeInstance,) = setupStakingNode(depositAmount);

        uint64 oracleTimestamp = uint64(block.timestamp);
        MockEigenLayerBeaconOracle mockBeaconOracle = new MockEigenLayerBeaconOracle();

        address eigenPodManagerOwner = OwnableUpgradeable(address(eigenPodManager)).owner();
        vm.prank(eigenPodManagerOwner);
        eigenPodManager.updateBeaconChainOracle(IBeaconChainOracle(address(mockBeaconOracle)));

        bytes32 latestBlockRoot = proofUtils.getLatestBlockRoot();
        mockBeaconOracle.setOracleBlockRootAtTimestamp(latestBlockRoot);

		BeaconChainProofs.StateRootProof memory stateRootProof = proofUtils._getStateRootProof();

		uint40[] memory validatorIndexes = new uint40[](1);

		validatorIndexes[0] = uint40(proofUtils.getValidatorIndex());

        bytes[] memory validatorFieldsProofs = new bytes[](1);
        validatorFieldsProofs[0] = proofUtils._getValidatorFieldsProof()[0];

		bytes32[][] memory validatorFields = new bytes32[][](1);
        validatorFields[0] = proofUtils.getValidatorFields();

        // address eigenPodAddress = address(stakingNodeInstance.eigenPod());
        // validatorFields[0][1] = (abi.encodePacked(bytes1(uint8(1)), bytes11(0), eigenPodAddress)).toBytes32(0);

        vm.prank(actors.ops.STAKING_NODES_OPERATOR);
        vm.expectRevert("EigenPod.verifyCorrectWithdrawalCredentials: Proof is not for this EigenPod");
        stakingNodeInstance.verifyWithdrawalCredentials(
            oracleTimestamp,
            stateRootProof,
            validatorIndexes,
            validatorFieldsProofs,
            validatorFields
        ); 
    }

    function setupVerifyWithdrawalCredentialsForProofFileForForeignValidator(
        string memory path
    ) public returns(VerifyWithdrawalCredentialsCallParams memory params) {

        setJSON(path);

        uint256 depositAmount = 32 ether;
        (IStakingNode stakingNodeInstance,) = setupStakingNode(depositAmount);

        uint64 oracleTimestamp = uint64(block.timestamp);
        MockEigenLayerBeaconOracle mockBeaconOracle = new MockEigenLayerBeaconOracle();

        address eigenPodManagerOwner = OwnableUpgradeable(address(eigenPodManager)).owner();
        vm.prank(eigenPodManagerOwner);
        eigenPodManager.updateBeaconChainOracle(IBeaconChainOracle(address(mockBeaconOracle)));
        
        // set existing EigenPod to be the EigenPod of the StakingNode for the 
        // purpose of testing verifyWithdrawalCredentials
        address eigenPodAddress = getWithdrawalAddress();

        MockStakingNode(payable(address(stakingNodeInstance)))
            .setEigenPod(IEigenPod(eigenPodAddress));

        {
            // Upgrade the implementation of EigenPod to be able to alter its owner
            EigenPod existingEigenPod = EigenPod(payable(address(stakingNodeInstance.eigenPod())));

            MockEigenPod mockEigenPod = new MockEigenPod(
                IETHPOSDeposit(existingEigenPod.ethPOS()),
                IDelayedWithdrawalRouter(address(delayedWithdrawalRouter)),
                IEigenPodManager(address(eigenPodManager)),
                existingEigenPod.MAX_RESTAKED_BALANCE_GWEI_PER_VALIDATOR(),
                existingEigenPod.GENESIS_TIME()
            );

            address mockEigenPodAddress = address(mockEigenPod);
            IEigenPodManager eigenPodManagerInstance = IEigenPodManager(eigenPodManager);
            address eigenPodBeaconAddress = address(eigenPodManagerInstance.eigenPodBeacon());
            UpgradeableBeacon eigenPodBeacon = UpgradeableBeacon(eigenPodBeaconAddress);
            address eigenPodBeaconOwner = Ownable(eigenPodBeaconAddress).owner();
            vm.prank(eigenPodBeaconOwner);
            eigenPodBeacon.upgradeTo(mockEigenPodAddress);
        }

        MockEigenPod mockEigenPodInstance = MockEigenPod(payable(address(stakingNodeInstance.eigenPod())));
        mockEigenPodInstance.setPodOwner(address(stakingNodeInstance));


        ValidatorProofs memory validatorProofs = getWithdrawalCredentialParams();
        bytes32 validatorPubkeyHash = BeaconChainProofs.getPubkeyHash(validatorProofs.validatorFields[0]);
        IEigenPod.ValidatorInfo memory zeroedValidatorInfo = IEigenPod.ValidatorInfo({
            validatorIndex: 0,
            restakedBalanceGwei: 0,
            mostRecentBalanceUpdateTimestamp: 0,
            status: IEigenPod.VALIDATOR_STATUS.INACTIVE
        });
        mockEigenPodInstance.setValidatorInfo(validatorPubkeyHash, zeroedValidatorInfo);

        {
            // Upgrade the implementation of EigenPod to be able to alter the owner of the pod being tested
            MockEigenPodManager mockEigenPodManager = new MockEigenPodManager(EigenPodManager(address(eigenPodManager)));
            address payable eigenPodManagerPayable = payable(address(eigenPodManager));
            ITransparentUpgradeableProxy eigenPodManagerProxy = ITransparentUpgradeableProxy(eigenPodManagerPayable);

            address proxyAdmin = Utils.getTransparentUpgradeableProxyAdminAddress(eigenPodManagerPayable);
            vm.prank(proxyAdmin);
            eigenPodManagerProxy.upgradeTo(address(mockEigenPodManager));
        }

        {
            // mock latest blockRoot
            MockEigenPodManager mockEigenPodManagerInstance = MockEigenPodManager(address(eigenPodManager));
            mockEigenPodManagerInstance.setHasPod(address(stakingNodeInstance), stakingNodeInstance.eigenPod());

            bytes32 latestBlockRoot = _getLatestBlockRoot();
            mockBeaconOracle.setOracleBlockRootAtTimestamp(latestBlockRoot);
        }


        params.oracleTimestamp = oracleTimestamp;
        params.stakingNodeInstance = stakingNodeInstance;
        params.validatorProofs = validatorProofs;
    }
    

    function testVerifyWithdrawalCredentialsSuccesfully_32ETH() public {
        if (block.chainid != 1) {
            return; // Skip test if not on Ethereum Mainnet
        }
        VerifyWithdrawalCredentialsCallParams memory params
            = setupVerifyWithdrawalCredentialsForProofFileForForeignValidator("test/data/ValidatorFieldsProof_1293592_8746783.json");

        uint64 oracleTimestamp = params.oracleTimestamp;
        IStakingNode stakingNodeInstance = params.stakingNodeInstance;
        ValidatorProofs memory validatorProofs = params.validatorProofs;

        uint256 stakingNodeETHBalanceBeforeVerification = stakingNodeInstance.getETHBalance();
        uint256 ynETHTotalAssetsBeforeVerification = yneth.totalAssets();

        vm.prank(actors.ops.STAKING_NODES_OPERATOR);
        stakingNodeInstance.verifyWithdrawalCredentials(
            oracleTimestamp,
            validatorProofs.stateRootProof,
            validatorProofs.validatorIndices,
            validatorProofs.withdrawalCredentialProofs,
            validatorProofs.validatorFields
        );
        
        int256 expectedShares = int256(uint256(BeaconChainProofs.getEffectiveBalanceGwei(validatorProofs.validatorFields[0])) * 1e9);
        int256 actualShares = eigenPodManager.podOwnerShares(address(stakingNodeInstance));
        assertEq(actualShares, expectedShares, "Staking node shares do not match expected shares");

        assertEq(stakingNodeETHBalanceBeforeVerification, stakingNodeInstance.getETHBalance(), "Staking node ETH balance should not change after verification");
        assertEq(ynETHTotalAssetsBeforeVerification, yneth.totalAssets(), "Total assets should not change after verification");
    }

    function testVerifyWithdrawalCredentialsSuccesfully_1ETH() public {
        if (block.chainid != 1) {
            return; // Skip test if not on Ethereum Mainnet
        }

        // Validator index tested: 1293592
        //
        // Note that this validator has 2 deposits performed in sequence: https://beaconcha.in/validator/1293592#deposits
        // for 1 ETH and 31 ETH respectively.
        // Which is NOT the case with YieldNest Validators, which are always allocated with 32 ETH from the get go.
        // This effectively emulates a slashing-like situation where the balance goes to 1 ETH
        // And the totalAssets of the protocol should now *decrease* accordingly by 31 ETH.

        uint256 expectedDecreaseAmount = 31 ether;

        VerifyWithdrawalCredentialsCallParams memory params
            = setupVerifyWithdrawalCredentialsForProofFileForForeignValidator("test/data/ValidatorFieldsProof_1293592_8654000.json");

        uint64 oracleTimestamp = params.oracleTimestamp;
        IStakingNode stakingNodeInstance = params.stakingNodeInstance;
        ValidatorProofs memory validatorProofs = params.validatorProofs;

        uint256 stakingNodeETHBalanceBeforeVerification = stakingNodeInstance.getETHBalance();
        uint256 ynETHTotalAssetsBeforeVerification = yneth.totalAssets();

        vm.prank(actors.ops.STAKING_NODES_OPERATOR);
        stakingNodeInstance.verifyWithdrawalCredentials(
            oracleTimestamp,
            validatorProofs.stateRootProof,
            validatorProofs.validatorIndices,
            validatorProofs.withdrawalCredentialProofs,
            validatorProofs.validatorFields
        );
        
        int256 expectedShares = int256(uint256(BeaconChainProofs.getEffectiveBalanceGwei(validatorProofs.validatorFields[0])) * 1e9);
        int256 actualShares = eigenPodManager.podOwnerShares(address(stakingNodeInstance));
        assertEq(actualShares, expectedShares, "Staking node shares do not match expected shares");

        assertEq(stakingNodeETHBalanceBeforeVerification - expectedDecreaseAmount, stakingNodeInstance.getETHBalance(), "Staking node ETH balance should not change after verification");
        assertEq(ynETHTotalAssetsBeforeVerification - expectedDecreaseAmount, yneth.totalAssets(), "Total assets should not change after verification");
    }

    function skiptestVerifyWithdrawalCredentialsWithStrategyUnpaused() public {

        ProofUtils proofUtils = new ProofUtils(DEFAULT_PROOFS_PATH);

        uint256 depositAmount = 32 ether;
        (IStakingNode stakingNodeInstance,) = setupStakingNode(depositAmount);

        uint64 oracleTimestamp = uint64(block.timestamp);

		BeaconChainProofs.StateRootProof memory stateRootProof = proofUtils._getStateRootProof();

		uint40[] memory validatorIndexes = new uint40[](1);

		validatorIndexes[0] = uint40(proofUtils.getValidatorIndex());

        bytes[] memory validatorFieldsProofs = new bytes[](1);
        validatorFieldsProofs[0] = proofUtils._getValidatorFieldsProof()[0];

		bytes32[][] memory validatorFields = new bytes32[][](1);
        validatorFields[0] = proofUtils.getValidatorFields();


        vm.prank(actors.ops.STAKING_NODES_OPERATOR);
        stakingNodeInstance.verifyWithdrawalCredentials(
            oracleTimestamp,
            stateRootProof,
            validatorIndexes,
            validatorFieldsProofs,
            validatorFields
        ); 

        uint256 shares = strategyManager.stakerStrategyShares(
            address(stakingNodeInstance), 
            stakingNodeInstance.beaconChainETHStrategy()
        );
        assertEq(shares, depositAmount, "Shares do not match deposit amount");
    }

    function skiptestVerifyWithdrawalCredentialsMismatchedValidatorIndexAndProofsLengths() public {

        ProofUtils proofUtils = new ProofUtils(DEFAULT_PROOFS_PATH);

        uint256 depositAmount = 32 ether;
        (IStakingNode stakingNodeInstance,) = setupStakingNode(depositAmount);

        uint64 oracleTimestamp = uint64(block.timestamp);

		BeaconChainProofs.StateRootProof memory stateRootProof = proofUtils._getStateRootProof();

		uint40[] memory validatorIndexes = new uint40[](1);

		validatorIndexes[0] = uint40(proofUtils.getValidatorIndex());

        bytes[] memory validatorFieldsProofs = new bytes[](1);
        validatorFieldsProofs[0] = proofUtils._getValidatorFieldsProof()[0];

		bytes32[][] memory validatorFields = new bytes32[][](1);
        validatorFields[0] = proofUtils.getValidatorFields();

        vm.prank(actors.ops.STAKING_NODES_OPERATOR);
        stakingNodeInstance.verifyWithdrawalCredentials(
            oracleTimestamp,
            stateRootProof,
            validatorIndexes,
            validatorFieldsProofs,
            validatorFields
        );    
    }

    event LogUintMessage(string message, uint256 value);
    event LogAddressMessage(string message, address value);
    event LogBytesMessage(string message, bytes value);

    function skiptestVerifyWithdrawalCredentialsMismatchedProofsAndValidatorFieldsLengths() public {

        ProofUtils proofUtils = new ProofUtils(DEFAULT_PROOFS_PATH);

        uint256 depositAmount = 32 ether;
        (IStakingNode stakingNodeInstance,) = setupStakingNode(depositAmount);

		uint64 oracleTimestamp = uint64(block.timestamp);

		BeaconChainProofs.StateRootProof memory stateRootProof = proofUtils._getStateRootProof();

		uint40[] memory validatorIndexes = new uint40[](1);

		validatorIndexes[0] = uint40(proofUtils.getValidatorIndex());

        bytes[] memory validatorFieldsProofs = proofUtils._getValidatorFieldsProof();

		bytes32[][] memory validatorFields = new bytes32[][](1);
        validatorFields[0] = proofUtils.getValidatorFields();

        vm.prank(actors.ops.STAKING_NODES_OPERATOR);
        stakingNodeInstance.verifyWithdrawalCredentials(
            oracleTimestamp,
            stateRootProof,
            validatorIndexes,
            validatorFieldsProofs,
            validatorFields
        ); 
    }
}

contract StakingNodeStakedETHAllocationTests is StakingNodeTestBase {

    event AllocatedStakedETH(uint256 previousAmount, uint256 newAmount);

    function testAllocateStakedETH() public {
        (IStakingNode stakingNodeInstance,) = setupStakingNode(32 ether);
        uint256 initialETHBalance = stakingNodeInstance.getETHBalance();
        uint256 amountToAllocate = 10 ether;

        vm.expectEmit(true, true, false, true);
        emit AllocatedStakedETH(initialETHBalance, amountToAllocate);
        vm.prank(address(stakingNodesManager));
        stakingNodeInstance.allocateStakedETH(amountToAllocate);

        uint256 newETHBalance = stakingNodeInstance.getETHBalance();
        assertEq(newETHBalance, initialETHBalance + amountToAllocate, "ETH balance did not increase by the allocated amount");
    }

    function testAllocateStakedETHFailsWhenNotStakingNodesManager() public {
        (IStakingNode stakingNodeInstance,) = setupStakingNode(32 ether);
        uint256 amountToAllocate = 10 ether;

        vm.expectRevert(StakingNode.NotStakingNodesManager.selector);
        vm.prank(actors.eoa.DEFAULT_SIGNER);
        stakingNodeInstance.allocateStakedETH(amountToAllocate);
    }

    function testGetETHBalanceWithAllocationAndEigenPodDeposit() public {
        (IStakingNode stakingNodeInstance, IEigenPod eigenPodInstance) = setupStakingNode(32 ether);
        uint256 initialETHBalance = stakingNodeInstance.getETHBalance();
        uint256 amountToAllocate = 10 ether;
        uint256 amountToDepositInEigenPod = 5 ether;

        // Allocate ETH to the staking node
        vm.prank(address(stakingNodesManager));
        stakingNodeInstance.allocateStakedETH(amountToAllocate);

        // Deposit ETH directly to the EigenPod
        address payable eigenPodAddress = payable(address(eigenPodInstance));
        vm.deal(address(this), amountToDepositInEigenPod);
        (bool success,) = eigenPodAddress.call{value: amountToDepositInEigenPod}("");
        require(success, "Failed to send ETH to EigenPod");

        uint256 expectedETHBalance = initialETHBalance + amountToAllocate;
        uint256 actualETHBalance = stakingNodeInstance.getETHBalance();

        assertEq(actualETHBalance, expectedETHBalance, "ETH balance does not match expected value after allocation and EigenPod deposit");
    }
}


contract StakingNodeMiscTests is StakingNodeTestBase {

    function testSendingETHToStakingNodeShouldRevert() public {
        (IStakingNode stakingNodeInstance,) = setupStakingNode(32 ether);
        uint256 amountToSend = 1 ether;

        // Attempt to send ETH to the StakingNode contract
        (bool sent, ) = address(stakingNodeInstance).call{value: amountToSend}("");
        assertFalse(sent, "Sending ETH should fail");
    }
}
