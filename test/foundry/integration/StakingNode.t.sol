// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IPausable} from "../../../src/external/eigenlayer/v0.1.0/interfaces/IPausable.sol";
import {IDelegationManager} from "../../../src/external/eigenlayer/v0.1.0/interfaces/IDelegationManager.sol";
import {IDelegationTerms} from "../../../src/external/eigenlayer/v0.1.0/interfaces/IDelegationTerms.sol";
import {IntegrationBaseTest} from "./IntegrationBaseTest.sol";
import {IStakingNode} from "../../../src/interfaces/IStakingNode.sol";
import {IStakingNodesManager} from "../../../src/interfaces/IStakingNodesManager.sol";
import {IEigenPod} from "../../../src/external/eigenlayer/v0.1.0/interfaces/IEigenPod.sol";
import {IDelayedWithdrawalRouter} from "../../../src/external/eigenlayer/v0.1.0/interfaces/IDelayedWithdrawalRouter.sol";
import {BeaconChainProofs} from "../../../src/external/eigenlayer/v0.1.0/BeaconChainProofs.sol";
import {MainnetEigenPodMock} from "../mocks/mainnet/MainnetEigenPodMock.sol";
import "../../../src/StakingNode.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol"; 


contract StakingNodeTestBase is IntegrationBaseTest {

    function setupStakingNode(uint depositAmount) public returns (IStakingNode, IEigenPod) {

        address addr1 = vm.addr(100);

        require(depositAmount % 32 ether == 0, "depositAmount must be a multiple of 32 ether");

        uint validatorCount = depositAmount / 32 ether;

        vm.deal(addr1, depositAmount);

        vm.prank(addr1);
        yneth.depositETH{value: depositAmount}(addr1);

        vm.prank(actors.STAKING_NODE_CREATOR);
        IStakingNode stakingNodeInstance = stakingNodesManager.createStakingNode();

        uint256 nodeId = 0;

        IStakingNodesManager.ValidatorData[] memory validatorData = new IStakingNodesManager.ValidatorData[](validatorCount);
        for (uint i = 0; i < validatorCount; i++) {
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

        (IStakingNode stakingNodeInstance, IEigenPod eigenPodInstance) = setupStakingNode(32 ether);

        // Collapsed variable declarations into direct usage within assertions and conditions

        // TODO: double check this is the desired state for a pod.
        // we can't delegate on mainnet at this time so one should be able to farm points without delegating
        assertEq(eigenPodInstance.restakedExecutionLayerGwei(), 0, "Restaked Gwei should be 0");
        assertEq(address(eigenPodManager), address(eigenPodInstance.eigenPodManager()), "EigenPodManager should match");
        assertEq(eigenPodInstance.podOwner(), address(stakingNodeInstance), "Pod owner address does not match");
        assertFalse(eigenPodInstance.hasRestaked(), "Pod should have fully restaked");
        assertEq(eigenPodInstance.mostRecentWithdrawalBlockNumber(), 0, "Most recent withdrawal block should be greater than 0");

        address payable eigenPodAddress = payable(address(eigenPodInstance));
        // Validators are configured to send consensus layer rewards directly to the EigenPod address.
        // These rewards are then sweeped into the StakingNode's balance as part of the withdrawal process.
        uint256 rewardsSweeped = 1 ether;
        vm.deal(eigenPodAddress, rewardsSweeped);

        // trigger withdraw before restaking succesfully
        vm.prank(actors.STAKING_NODES_ADMIN);
        stakingNodeInstance.withdrawBeforeRestaking();

        IDelayedWithdrawalRouter delayedWithdrawalRouter = stakingNodesManager.delayedWithdrawalRouter();
        uint256 withdrawalDelayBlocks = delayedWithdrawalRouter.withdrawalDelayBlocks();
        vm.roll(block.number + withdrawalDelayBlocks + 1);

        uint256 balanceBeforeClaim = address(consensusLayerReceiver).balance;
        vm.prank(actors.STAKING_NODES_ADMIN);
        stakingNodeInstance.claimDelayedWithdrawals(type(uint256).max, 0);
        uint256 balanceAfterClaim = address(consensusLayerReceiver).balance;
        uint256 rewardsAmount = balanceAfterClaim - balanceBeforeClaim;

        assertEq(rewardsAmount, rewardsSweeped, "Rewards amount does not match expected value");
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
        vm.deal(eigenPodAddress, rewardsSweeped);

        // trigger withdraw before restaking succesfully
        vm.prank(actors.STAKING_NODES_ADMIN);
        stakingNodeInstance.withdrawBeforeRestaking();

        IDelayedWithdrawalRouter delayedWithdrawalRouter = stakingNodesManager.delayedWithdrawalRouter();
        uint256 withdrawalDelayBlocks = delayedWithdrawalRouter.withdrawalDelayBlocks();
        vm.roll(block.number + withdrawalDelayBlocks + 1);

        uint256 balanceBeforeClaim = address(consensusLayerReceiver).balance;
        vm.prank(actors.STAKING_NODES_ADMIN);
        stakingNodeInstance.claimDelayedWithdrawals(type(uint256).max, 0);
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
        vm.deal(eigenPodAddress, rewardsSweeped);

        // trigger withdraw before restaking succesfully
        vm.prank(actors.STAKING_NODES_ADMIN);
        stakingNodeInstance.withdrawBeforeRestaking();

        IDelayedWithdrawalRouter delayedWithdrawalRouter = stakingNodesManager.delayedWithdrawalRouter();
        uint256 withdrawalDelayBlocks = delayedWithdrawalRouter.withdrawalDelayBlocks();
        vm.roll(block.number + withdrawalDelayBlocks + 1);

        uint256 balanceBeforeClaim = address(consensusLayerReceiver).balance;
        vm.prank(actors.STAKING_NODES_ADMIN);
        stakingNodeInstance.claimDelayedWithdrawals(type(uint256).max, 0);
        uint256 balanceAfterClaim = address(consensusLayerReceiver).balance;
        uint256 rewardsAmount = balanceAfterClaim - balanceBeforeClaim;

        assertEq(rewardsAmount, rewardsSweeped, "Rewards amount does not match expected value");
    }


   function testWithdrawBeforeRestakingAndClaimDelayedWithdrawalsWithValidatorPrincipal() public {

       uint activeValidators = 5;

       uint depositAmount = activeValidators * 32 ether;

       (IStakingNode stakingNodeInstance, IEigenPod eigenPodInstance) = setupStakingNode(depositAmount);

       address payable eigenPodAddress = payable(address(eigenPodInstance));
        // Validators are configured to send consensus layer rewards directly to the EigenPod address.
        // These rewards are then sweeped into the StakingNode's balance as part of the withdrawal process.
        uint rewardsSweeped = depositAmount + 100 ether;
        vm.deal(eigenPodAddress, rewardsSweeped);

        // trigger withdraw before restaking succesfully
        vm.prank(actors.STAKING_NODES_ADMIN);
        stakingNodeInstance.withdrawBeforeRestaking();

        IDelayedWithdrawalRouter delayedWithdrawalRouter = stakingNodesManager.delayedWithdrawalRouter();
        vm.roll(block.number + delayedWithdrawalRouter.withdrawalDelayBlocks() + 1);

        uint256 balanceBeforeClaim = address(consensusLayerReceiver).balance;

        uint256 withdrawnValidators = activeValidators - 1;
        uint256 validatorPrincipal = withdrawnValidators * 32 ether;

        vm.prank(actors.STAKING_NODES_ADMIN);
        stakingNodeInstance.claimDelayedWithdrawals(type(uint256).max, validatorPrincipal);
        uint256 balanceAfterClaim = address(consensusLayerReceiver).balance;
        uint256 rewardsAmount = balanceAfterClaim - balanceBeforeClaim;

        assertEq(stakingNodeInstance.getETHBalance(), depositAmount - validatorPrincipal, "StakingNode ETH balance does not match expected value");

        uint expectedRewards = rewardsSweeped - validatorPrincipal;
        assertEq(rewardsAmount, expectedRewards, "Rewards amount does not match expected value");
    }

    function testValidatorPrincipalExceedsTotalClaimable() public {

        uint activeValidators = 5;

        uint depositAmount = activeValidators * 32 ether;
        uint validatorPrincipal = depositAmount; // Total principal for all validators

        (IStakingNode stakingNodeInstance, IEigenPod eigenPodInstance) = setupStakingNode(depositAmount);

        // Simulate rewards being sweeped into the StakingNode's balance
        uint rewardsSweeped = 3 * 32 ether;
        address payable eigenPodAddress = payable(address(eigenPodInstance));
        vm.deal(eigenPodAddress, rewardsSweeped);

        // Trigger withdraw before restaking successfully
        vm.prank(actors.STAKING_NODES_ADMIN);
        stakingNodeInstance.withdrawBeforeRestaking();

        // Simulate time passing for withdrawal delay
        IDelayedWithdrawalRouter delayedWithdrawalRouter = stakingNodesManager.delayedWithdrawalRouter();
        vm.roll(block.number + delayedWithdrawalRouter.withdrawalDelayBlocks() + 1);

        uint256 tooLargeValidatorPrincipal = validatorPrincipal;

        // Attempt to claim withdrawals with a validator principal that exceeds total claimable amount
        vm.prank(actors.STAKING_NODES_ADMIN);
        vm.expectRevert(abi.encodeWithSelector(StakingNode.ValidatorPrincipalExceedsTotalClaimable.selector, tooLargeValidatorPrincipal, rewardsSweeped));
        stakingNodeInstance.claimDelayedWithdrawals(type(uint256).max, tooLargeValidatorPrincipal); // Exceeding by 1 ether
    }


    function testWithdrawalPrincipalAmountTooHigh() public {

        uint activeValidators = 5;

        uint depositAmount = activeValidators * 32 ether;
        uint validatorPrincipal = depositAmount; // Total principal for all validators

        (IStakingNode stakingNodeInstance, IEigenPod eigenPodInstance) = setupStakingNode(depositAmount);

        // Simulate rewards being sweeped into the StakingNode's balance
        uint rewardsSweeped = 5 * 32 ether;
        address payable eigenPodAddress = payable(address(eigenPodInstance));
        vm.deal(eigenPodAddress, rewardsSweeped);

        // Trigger withdraw before restaking successfully
        vm.prank(actors.STAKING_NODES_ADMIN);
        stakingNodeInstance.withdrawBeforeRestaking();

        // Simulate time passing for withdrawal delay
        IDelayedWithdrawalRouter delayedWithdrawalRouter = stakingNodesManager.delayedWithdrawalRouter();
        vm.roll(block.number + delayedWithdrawalRouter.withdrawalDelayBlocks() + 1);

        uint256 tooLargeValidatorPrincipal = validatorPrincipal + 1 ether;
        uint256 expectedAllocatedETH = depositAmount;

        // Attempt to claim withdrawals with a validator principal that exceeds total claimable amount
        vm.prank(actors.STAKING_NODES_ADMIN);
        vm.expectRevert(abi.encodeWithSelector(StakingNode.WithdrawalPrincipalAmountTooHigh.selector, tooLargeValidatorPrincipal, expectedAllocatedETH));
        stakingNodeInstance.claimDelayedWithdrawals(type(uint256).max, tooLargeValidatorPrincipal); // Exceeding by 1 ether
    }
}

contract StakingNodeVerifyWithdrawalCredentials is StakingNodeTestBase {
    using stdStorage for StdStorage;

    function testVerifyWithdrawalCredentialsRevertingWhenPaused() public {

        (IStakingNode stakingNodeInstance, IEigenPod eigenPodInstance) = setupStakingNode(32 ether);

        MainnetEigenPodMock mainnetEigenPodMock = new MainnetEigenPodMock(eigenPodManager);

        address eigenPodBeaconAddress = eigenPodManager.eigenPodBeacon();
        address beaconOwner = Ownable(eigenPodBeaconAddress).owner();

        UpgradeableBeacon beacon = UpgradeableBeacon(eigenPodBeaconAddress);
        address previousImplementation = beacon.implementation();

        vm.prank(beaconOwner);
        beacon.upgradeTo(address(mainnetEigenPodMock));


        MainnetEigenPodMock(address(eigenPodInstance)).sethasRestaked(true);

        uint64[] memory oracleBlockNumbers = new uint64[](1);
        oracleBlockNumbers[0] = 0; // Mock value

        uint40[] memory validatorIndexes = new uint40[](1);
        validatorIndexes[0] = 1234567; // Validator index

        BeaconChainProofs.ValidatorFieldsAndBalanceProofs[] memory proofs = new BeaconChainProofs.ValidatorFieldsAndBalanceProofs[](1);
        proofs[0] = BeaconChainProofs.ValidatorFieldsAndBalanceProofs({
            validatorFieldsProof: new bytes(0), // Mock value
            validatorBalanceProof: new bytes(0), // Mock value
            balanceRoot: bytes32(0) // Mock value
        });

        bytes32[][] memory validatorFields = new bytes32[][](1);
        validatorFields[0] = new bytes32[](2);
        validatorFields[0][0] = bytes32(0); // Mock value
        validatorFields[0][1] = bytes32(0); // Mock value

        // Note: Deposits are currently paused as per the PAUSED_DEPOSITS flag in StrategyManager.sol
        // See: https://github.com/Layr-Labs/eigenlayer-contracts/blob/c7bf3817c5e1430672bf8bc80558d8439a2022af/src/contracts/core/StrategyManager.sol#L168
        vm.expectRevert("Pausable: index is paused");
        vm.prank(actors.STAKING_NODES_ADMIN);
        stakingNodeInstance.verifyWithdrawalCredentials(oracleBlockNumbers, validatorIndexes, proofs, validatorFields);

        // go back to previous implementation
        vm.prank(beaconOwner);
        beacon.upgradeTo(previousImplementation);

        // Note: reenable this when verifyWithdrawals works
        // // Note: once deposits are unpaused this should work
        // vm.expectRevert("StrategyManager._removeShares: shareAmount too high");
        // stakingNodeInstance.startWithdrawal(withdrawalAmount);


        // // Note: once deposits are unpaused and a withdrawal is queued, it may be completed
        // vm.expectRevert("StrategyManager.completeQueuedWithdrawal: withdrawal is not pending");
        // WithdrawalCompletionParams memory params = WithdrawalCompletionParams({
        //     middlewareTimesIndex: 0, // Assuming middlewareTimesIndex is not used in this context
        //     amount: withdrawalAmount,
        //     withdrawalStartBlock: uint32(block.number), // Current block number as the start block
        //     delegatedAddress: address(0), // Assuming no delegation address is needed for this withdrawal
        //     nonce: 0 // first nonce is 0
        // });
        // stakingNodeInstance.completeWithdrawal(params);
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
        stakingNodeInstance.claimDelayedWithdrawals(type(uint256).max, 1);
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
        delegationManager.registerAsOperator(IDelegationTerms(address(this)));
        vm.prank(actors.STAKING_NODES_ADMIN);
        stakingNodeInstance.delegate(address(this));
    }

    function testImplementViewFunction() public {
        vm.prank(actors.STAKING_NODE_CREATOR);
        IStakingNode stakingNodeInstance = stakingNodesManager.createStakingNode();
        assertEq(stakingNodeInstance.implementation(), address(stakingNodeImplementation));
    }

    function testVerifyWithdrawalCredentialsWithStrategyUnpaused() public {

        uint256 depositAmount = 32 ether;

        (IStakingNode stakingNodeInstance, IEigenPod eigenPodInstance) = setupStakingNode(depositAmount);

        MainnetEigenPodMock mainnetEigenPodMock = new MainnetEigenPodMock(eigenPodManager);

        address eigenPodBeaconAddress = eigenPodManager.eigenPodBeacon();
        address beaconOwner = Ownable(eigenPodBeaconAddress).owner();

        UpgradeableBeacon beacon = UpgradeableBeacon(eigenPodBeaconAddress);
        address previousImplementation = beacon.implementation();

        vm.prank(beaconOwner);
        beacon.upgradeTo(address(mainnetEigenPodMock));

        MainnetEigenPodMock(address(eigenPodInstance)).sethasRestaked(true);

        {
            // unpausing deposits artificially
            IPausable pausableStrategyManager = IPausable(address(strategyManager));
            address unpauser = pausableStrategyManager.pauserRegistry().unpauser();
            vm.startPrank(unpauser);
            pausableStrategyManager.unpause(0);
            vm.stopPrank();
        }

        {
            uint64[] memory oracleBlockNumbers = new uint64[](1);
            oracleBlockNumbers[0] = 0; // Mock value

            uint40[] memory validatorIndexes = new uint40[](1);
            validatorIndexes[0] = 1234567; // Validator index

            BeaconChainProofs.ValidatorFieldsAndBalanceProofs[] memory proofs = new BeaconChainProofs.ValidatorFieldsAndBalanceProofs[](1);
            proofs[0] = BeaconChainProofs.ValidatorFieldsAndBalanceProofs({
                validatorFieldsProof: new bytes(0), // Mock value
                validatorBalanceProof: new bytes(0), // Mock value
                balanceRoot: bytes32(0) // Mock value
            });

            bytes32[][] memory validatorFields = new bytes32[][](1);
            validatorFields[0] = new bytes32[](2);
            validatorFields[0][0] = bytes32(0); // Mock value
            validatorFields[0][1] = bytes32(0); // Mock value
            vm.prank(actors.STAKING_NODES_ADMIN);
            stakingNodeInstance.verifyWithdrawalCredentials(oracleBlockNumbers, validatorIndexes, proofs, validatorFields);

            // go back to previous implementation
            vm.prank(beaconOwner);
            beacon.upgradeTo(previousImplementation);
        }

        uint shares = strategyManager.stakerStrategyShares(address(stakingNodeInstance), stakingNodeInstance.beaconChainETHStrategy());
        assertEq(shares, depositAmount, "Shares do not match deposit amount");

    }  
}

contract StakingNodeMiscTests is StakingNodeTestBase {

    function testSendingETHToStakingNodeShouldRevert() public {
        (IStakingNode stakingNodeInstance, IEigenPod eigenPodInstance) = setupStakingNode(32 ether);
        uint256 initialBalance = address(stakingNodeInstance).balance;
        uint256 amountToSend = 1 ether;

        // Attempt to send ETH to the StakingNode contract
        (bool sent, ) = address(stakingNodeInstance).call{value: amountToSend}("");
        assertFalse(sent, "Sending ETH should fail");
    }
}