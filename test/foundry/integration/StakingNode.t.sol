// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {StakingNode} from "../../../src/StakingNode.sol";
import {IntegrationBaseTest} from "./IntegrationBaseTest.sol";
import {IStakingNode} from "../../../src/interfaces/IStakingNode.sol";
import {IStakingNodesManager} from "../../../src/interfaces/IStakingNodesManager.sol";
import {IEigenPod} from "../../../src/external/eigenlayer/v0.1.0/interfaces/IEigenPod.sol";
import {IDelayedWithdrawalRouter} from "../../../src/external/eigenlayer/v0.1.0/interfaces/IDelayedWithdrawalRouter.sol";
import {BeaconChainProofs} from "../../../src/external/eigenlayer/v0.1.0/BeaconChainProofs.sol";
import {MainnetEigenPodMock} from "../mocks/mainnet/MainnetEigenPodMock.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol"; 


contract StakingNodeTest is IntegrationBaseTest {
    using stdStorage for StdStorage;

    function testCreateNodeAndAssertETHBalanceWithoutRegisteredValidators() public {
        // Create a staking node
        IStakingNode stakingNodeInstance = stakingNodesManager.createStakingNode();

        uint256 actualETHBalance = stakingNodeImplementation.getETHBalance();
        assertEq(actualETHBalance, 0, "ETH balance does not match expected value");
    }

    function setupStakingNode() public returns (IStakingNode, IEigenPod) {

        address addr1 = vm.addr(100);

        vm.deal(addr1, 100 ether);

        uint256 depositAmount = 32 ether;
        vm.prank(addr1);
        yneth.depositETH{value: depositAmount}(addr1);

        IStakingNode stakingNodeInstance = stakingNodesManager.createStakingNode();

        uint256 nodeId = 0;

        IStakingNodesManager.ValidatorData[] memory validatorData = new IStakingNodesManager.ValidatorData[](1);
        validatorData[0] = IStakingNodesManager.ValidatorData({
            publicKey: ZERO_PUBLIC_KEY,
            signature: ZERO_SIGNATURE,
            nodeId: nodeId,
            depositDataRoot: bytes32(0)
        });

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

    function testCreateNodeAndVerifyPodStateIsValid() public {

        (IStakingNode stakingNodeInstance, IEigenPod eigenPodInstance) = setupStakingNode();

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

    function testWithdrawBeforeRestakingAndClaimDelayedWithdrawals() public {

        (IStakingNode stakingNodeInstance, IEigenPod eigenPodInstance) = setupStakingNode();

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

        (IStakingNode stakingNodeInstance, IEigenPod eigenPodInstance) = setupStakingNode();

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
      

    function testVerifyWithdrawalCredentials() public {

        (IStakingNode stakingNodeInstance, IEigenPod eigenPodInstance) = setupStakingNode();

        MainnetEigenPodMock mainnetEigenPodMock = new MainnetEigenPodMock(eigenPodManager);

        address eigenPodBeaconAddress = eigenPodManager.eigenPodBeacon();
        address beaconOwner = Ownable(eigenPodBeaconAddress).owner();

        UpgradeableBeacon beacon = UpgradeableBeacon(eigenPodBeaconAddress);

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
}

