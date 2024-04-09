// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {UpgradeableBeacon} from "lib/openzeppelin-contracts/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {IPausable} from "lib/eigenlayer-contracts/src/contracts/interfaces/IPausable.sol";
import {IDelegationManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IDelegationManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
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

contract StakingNodeTestBase is IntegrationBaseTest {

    function setupStakingNode(uint256 depositAmount) public returns (IStakingNode, IEigenPod) {

        address addr1 = vm.addr(100);

        require(depositAmount % 32 ether == 0, "depositAmount must be a multiple of 32 ether");

        uint256 validatorCount = depositAmount / 32 ether;

        vm.deal(addr1, depositAmount);

        vm.prank(addr1);
        yneth.depositETH{value: depositAmount}(addr1);

        vm.prank(actors.STAKING_NODE_CREATOR);
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
        
        bytes32 depositRoot = depositContractEth2.get_deposit_root();
        vm.prank(actors.VALIDATOR_MANAGER);
        stakingNodesManager.registerValidators(depositRoot, validatorData);

        uint256 actualETHBalance = stakingNodeInstance.getETHBalance();
        assertEq(actualETHBalance, depositAmount, "ETH balance does not match expected value");

        IEigenPod eigenPodInstance = stakingNodeInstance.eigenPod();

        return (stakingNodeInstance, eigenPodInstance);
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
        // Validators are configured to send consensus layer rewards directly to the EigenPod address.
        // These rewards are then sweeped into the StakingNode's balance as part of the withdrawal process.
        uint256 rewardsSweeped = 1 ether;
        vm.deal(address(this), rewardsSweeped);
        (bool success,) = eigenPodAddress.call{value: rewardsSweeped}("");
        require(success, "Failed to send rewards to EigenPod");

        // trigger withdraw before restaking succesfully
        vm.startPrank(actors.STAKING_NODES_ADMIN);
        stakingNodeInstance.withdrawNonBeaconChainETHBalanceWei();
        vm.stopPrank();

        IDelayedWithdrawalRouter delayedWithdrawalRouter = stakingNodesManager.delayedWithdrawalRouter();
        uint256 withdrawalDelayBlocks = delayedWithdrawalRouter.withdrawalDelayBlocks();
        vm.roll(block.number + withdrawalDelayBlocks + 1);

        delayedWithdrawalRouter.claimDelayedWithdrawals(address(stakingNodeInstance), type(uint256).max);

        uint256 balanceBeforeClaim = address(consensusLayerReceiver).balance;
        vm.prank(actors.STAKING_NODES_ADMIN);
        stakingNodeInstance.processWithdrawals(0, address(stakingNodeInstance).balance);
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


contract StakingNodeWithdrawWithoutRestaking is StakingNodeTestBase {
    using stdStorage for StdStorage;


    function testWithdrawBeforeRestakingAndClaimDelayedWithdrawals() public {

        (IStakingNode stakingNodeInstance, IEigenPod eigenPodInstance) = setupStakingNode(32 ether);

       address payable eigenPodAddress = payable(address(eigenPodInstance));
        // Validators are configured to send consensus layer rewards directly to the EigenPod address.
        // These rewards are then sweeped into the StakingNode's balance as part of the withdrawal process.
        uint256 rewardsSweeped = 1 ether;
        vm.deal(address(this), rewardsSweeped);
        (bool success,) = eigenPodAddress.call{value: rewardsSweeped}("");
        require(success, "Failed to send rewards to EigenPod");

        // trigger withdraw before restaking succesfully
        vm.startPrank(actors.STAKING_NODES_ADMIN);
        stakingNodeInstance.withdrawNonBeaconChainETHBalanceWei();
        vm.stopPrank();

        IDelayedWithdrawalRouter delayedWithdrawalRouter = stakingNodesManager.delayedWithdrawalRouter();
        uint256 withdrawalDelayBlocks = delayedWithdrawalRouter.withdrawalDelayBlocks();
        vm.roll(block.number + withdrawalDelayBlocks + 1);

        delayedWithdrawalRouter.claimDelayedWithdrawals(address(stakingNodeInstance), type(uint256).max);

        uint256 balanceBeforeClaim = address(consensusLayerReceiver).balance;
        vm.prank(actors.STAKING_NODES_ADMIN);
        stakingNodeInstance.processWithdrawals(0, address(stakingNodeInstance).balance);
        uint256 balanceAfterClaim = address(consensusLayerReceiver).balance;
        uint256 rewardsAmount = balanceAfterClaim - balanceBeforeClaim;

        assertEq(rewardsAmount, rewardsSweeped, "Rewards amount does not match expected value");
    }

   function testWithdrawBeforeRestakingAndClaimDelayedWithdrawalsForALargeAmount() public {

        (IStakingNode stakingNodeInstance, IEigenPod eigenPodInstance) = setupStakingNode(32 ether);

       address payable eigenPodAddress = payable(address(eigenPodInstance));
        // Validators are configured to send consensus layer rewards directly to the EigenPod address.
        // These rewards are then sweeped into the StakingNode's balance as part of the withdrawal process.
        uint256 rewardsSweeped = 1000 ether;
        vm.deal(address(this), rewardsSweeped);
        (bool success,) = eigenPodAddress.call{value: rewardsSweeped}("");
        require(success, "Failed to send rewards to EigenPod");

        // trigger withdraw before restaking succesfully
        vm.startPrank(actors.STAKING_NODES_ADMIN);
        stakingNodeInstance.withdrawNonBeaconChainETHBalanceWei();
        vm.stopPrank();

        IDelayedWithdrawalRouter delayedWithdrawalRouter = stakingNodesManager.delayedWithdrawalRouter();
        uint256 withdrawalDelayBlocks = delayedWithdrawalRouter.withdrawalDelayBlocks();
        vm.roll(block.number + withdrawalDelayBlocks + 1);

        delayedWithdrawalRouter.claimDelayedWithdrawals(address(stakingNodeInstance), type(uint256).max);

        uint256 balanceBeforeClaim = address(consensusLayerReceiver).balance;
        vm.prank(actors.STAKING_NODES_ADMIN);
        stakingNodeInstance.processWithdrawals(0, address(stakingNodeInstance).balance);
        uint256 balanceAfterClaim = address(consensusLayerReceiver).balance;
        uint256 rewardsAmount = balanceAfterClaim - balanceBeforeClaim;

        assertEq(rewardsAmount, rewardsSweeped, "Rewards amount does not match expected value");
    }


   function testWithdrawBeforeRestakingAndClaimDelayedWithdrawalsWithValidatorPrincipal() public {

       uint256 activeValidators = 5;

       uint256 depositAmount = activeValidators * 32 ether;

       (IStakingNode stakingNodeInstance, IEigenPod eigenPodInstance) = setupStakingNode(depositAmount);

       address payable eigenPodAddress = payable(address(eigenPodInstance));
        // Validators are configured to send consensus layer rewards directly to the EigenPod address.
        // These rewards are then sweeped into the StakingNode's balance as part of the withdrawal process.
        uint256 rewardsSweeped = depositAmount + 100 ether;
        vm.deal(address(this), rewardsSweeped);
        (bool success,) = eigenPodAddress.call{value: rewardsSweeped}("");
        require(success, "Failed to send rewards to EigenPod");

        // trigger withdraw before restaking succesfully
        vm.startPrank(actors.STAKING_NODES_ADMIN);
        stakingNodeInstance.withdrawNonBeaconChainETHBalanceWei();
        vm.stopPrank();

        IDelayedWithdrawalRouter delayedWithdrawalRouter = stakingNodesManager.delayedWithdrawalRouter();
        vm.roll(block.number + delayedWithdrawalRouter.withdrawalDelayBlocks() + 1);

        delayedWithdrawalRouter.claimDelayedWithdrawals(address(stakingNodeInstance), type(uint256).max);

        uint256 balanceBeforeClaim = address(consensusLayerReceiver).balance;

        uint256 withdrawnValidators = activeValidators - 1;
        uint256 validatorPrincipal = withdrawnValidators * 32 ether;

        vm.prank(actors.STAKING_NODES_ADMIN);
        stakingNodeInstance.processWithdrawals(validatorPrincipal, address(stakingNodeInstance).balance);
        uint256 balanceAfterClaim = address(consensusLayerReceiver).balance;
        uint256 rewardsAmount = balanceAfterClaim - balanceBeforeClaim;

        assertEq(stakingNodeInstance.getETHBalance(), depositAmount - validatorPrincipal, "StakingNode ETH balance does not match expected value");

        uint256 expectedRewards = rewardsSweeped - validatorPrincipal;
        assertEq(rewardsAmount, expectedRewards, "Rewards amount does not match expected value");
    }

    function testWithdrawalPrincipalAmountTooHigh() public {

        uint256 activeValidators = 5;

        uint256 depositAmount = activeValidators * 32 ether;
        uint256 validatorPrincipal = depositAmount; // Total principal for all validators

        (IStakingNode stakingNodeInstance, IEigenPod eigenPodInstance) = setupStakingNode(depositAmount);

        // Simulate rewards being sweeped into the StakingNode's balance
        uint256 rewardsSweeped = 5 * 32 ether;
        address payable eigenPodAddress = payable(address(eigenPodInstance));
        vm.deal(address(this), rewardsSweeped);
        (bool success,) = eigenPodAddress.call{value: rewardsSweeped}("");
        require(success, "Failed to send rewards to EigenPod");

        // trigger withdraw before restaking succesfully
        vm.startPrank(actors.STAKING_NODES_ADMIN);
        stakingNodeInstance.withdrawNonBeaconChainETHBalanceWei();
        vm.stopPrank();

        // Simulate time passing for withdrawal delay
        IDelayedWithdrawalRouter delayedWithdrawalRouter = stakingNodesManager.delayedWithdrawalRouter();
        vm.roll(block.number + delayedWithdrawalRouter.withdrawalDelayBlocks() + 1);

        delayedWithdrawalRouter.claimDelayedWithdrawals(address(stakingNodeInstance), type(uint256).max);

        uint256 tooLargeValidatorPrincipal = validatorPrincipal + 1 ether;
        uint256 expectedAllocatedETH = depositAmount;

        // Attempt to claim withdrawals with a validator principal that exceeds total claimable amount
        vm.prank(actors.STAKING_NODES_ADMIN);
        vm.expectRevert(abi.encodeWithSelector(StakingNode.WithdrawalPrincipalAmountTooHigh.selector, tooLargeValidatorPrincipal, expectedAllocatedETH));
        stakingNodeInstance.processWithdrawals(tooLargeValidatorPrincipal, address(stakingNodeInstance).balance);
    }
}

contract StakingNodeVerifyWithdrawalCredentials is StakingNodeTestBase {
    using stdStorage for StdStorage;

    function skiptestVerifyWithdrawalCredentialsRevertingWhenPaused() public {

        ProofUtils proofUtils = new ProofUtils();

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
        vm.prank(actors.STAKING_NODES_ADMIN);
        stakingNodeInstance.verifyWithdrawalCredentials(
            oracleTimestamp,
            stateRootProof,
            validatorIndexes,
            validatorFieldsProofs,
            validatorFields
        );
    }

    function testCreateEigenPodReturnsEigenPodAddressAfterCreated() public {
        vm.prank(actors.STAKING_NODE_CREATOR);
        IStakingNode stakingNodeInstance = stakingNodesManager.createStakingNode();
        IEigenPod eigenPodInstance = stakingNodeInstance.eigenPod();
        assertEq(address(eigenPodInstance), address(stakingNodeInstance.eigenPod()));
    }

    function testClaimDelayedWithdrawals() public {

        vm.prank(actors.STAKING_NODE_CREATOR);
        IStakingNode stakingNodeInstance = stakingNodesManager.createStakingNode();

        vm.prank(actors.STAKING_NODES_ADMIN);
        vm.expectRevert();
        stakingNodeInstance.processWithdrawals(1, address(stakingNodeInstance).balance);
    }

    function testDelegateFailWhenNotAdmin() public {
        vm.prank(actors.STAKING_NODE_CREATOR);
        IStakingNode stakingNodeInstance = stakingNodesManager.createStakingNode();
        vm.expectRevert();
        stakingNodeInstance.delegate(address(this));
    }

    function testStakingNodeDelegate() public {
        vm.prank(actors.STAKING_NODE_CREATOR);
        IStakingNode stakingNodeInstance = stakingNodesManager.createStakingNode();
        IDelegationManager delegationManager = stakingNodesManager.delegationManager();
        IPausable pauseDelegationManager = IPausable(address(delegationManager));
        vm.prank(chainAddresses.eigenlayer.DELEGATION_PAUSER_ADDRESS);
        pauseDelegationManager.unpause(0);

        // register as operator
        delegationManager.registerAsOperator(
            IDelegationManager.OperatorDetails({
                earningsReceiver: address(this),
                delegationApprover: address(0),
                stakerOptOutWindowBlocks: 1
            }), 
            "ipfs://some-ipfs-hash"
        );        vm.prank(actors.STAKING_NODES_ADMIN);
        stakingNodeInstance.delegate(address(this));
    }

    function testStakingNodeUndelegate() public {
        vm.prank(actors.STAKING_NODE_CREATOR);
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
        
        vm.prank(actors.STAKING_NODES_ADMIN);
        stakingNodeInstance.delegate(address(this));

        // // Attempt to undelegate
        vm.expectRevert();
        stakingNodeInstance.undelegate();

        IStrategyManager strategyManager = stakingNodesManager.strategyManager();
        uint256 stakerStrategyListLength = strategyManager.stakerStrategyListLength(address(stakingNodeInstance));
        assertEq(stakerStrategyListLength, 0, "Staker strategy list length should be 0.");
        
        // Now actually undelegate with the correct role
        vm.prank(actors.STAKING_NODES_ADMIN);
        stakingNodeInstance.undelegate();
        
        // Verify undelegation
        address delegatedAddress = delegationManager.delegatedTo(address(stakingNodeInstance));
        assertEq(delegatedAddress, address(0), "Delegation should be cleared after undelegation.");
    }

    function testImplementViewFunction() public {
        vm.prank(actors.STAKING_NODE_CREATOR);
        IStakingNode stakingNodeInstance = stakingNodesManager.createStakingNode();
        assertEq(stakingNodeInstance.implementation(), address(stakingNodeImplementation));
    }

    function skiptestVerifyWithdrawalCredentialsWithStrategyUnpaused() public {

        ProofUtils proofUtils = new ProofUtils();

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

        vm.prank(actors.STAKING_NODES_ADMIN);
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

        ProofUtils proofUtils = new ProofUtils();

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

        vm.prank(actors.STAKING_NODES_ADMIN);
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

        ProofUtils proofUtils = new ProofUtils();

        uint256 depositAmount = 32 ether;
        (IStakingNode stakingNodeInstance,) = setupStakingNode(depositAmount);

		uint64 oracleTimestamp = uint64(block.timestamp);

		BeaconChainProofs.StateRootProof memory stateRootProof = proofUtils._getStateRootProof();

		uint40[] memory validatorIndexes = new uint40[](1);

		validatorIndexes[0] = uint40(proofUtils.getValidatorIndex());

        bytes[] memory validatorFieldsProofs = proofUtils._getValidatorFieldsProof();

		bytes32[][] memory validatorFields = new bytes32[][](1);
        validatorFields[0] = proofUtils.getValidatorFields();

        vm.prank(actors.STAKING_NODES_ADMIN);
        stakingNodeInstance.verifyWithdrawalCredentials(
            oracleTimestamp,
            stateRootProof,
            validatorIndexes,
            validatorFieldsProofs,
            validatorFields
        ); 
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
