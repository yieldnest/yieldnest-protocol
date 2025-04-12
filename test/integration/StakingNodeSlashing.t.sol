// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IStakingNode} from "src/interfaces/IStakingNode.sol";
import {StakingNode} from "src/StakingNode.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";
import {ISignatureUtilsMixinTypes} from "lib/eigenlayer-contracts/src/contracts/interfaces/ISignatureUtilsMixin.sol";
import {BytesLib} from "lib/eigenlayer-contracts/src/test/utils/BytesLib.sol";
import {EigenPod} from "lib/eigenlayer-contracts/src/contracts/pods/EigenPod.sol";
import {EigenPodManager} from "lib/eigenlayer-contracts/src/contracts/pods/EigenPodManager.sol";
import {IStrategy} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {StakingNodeTestBase} from "./StakingNodeTestBase.sol";
import {SlashingLib} from "lib/eigenlayer-contracts/src/contracts/libraries/SlashingLib.sol";
import {IAllocationManager, IAllocationManagerTypes} from "lib/eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {OperatorSet} from "lib/eigenlayer-contracts/src/contracts/libraries/OperatorSetLib.sol";
import {AllocationManagerStorage} from "lib/eigenlayer-contracts/src/contracts/core/AllocationManagerStorage.sol";
import {MockAVS} from "test/mocks/MockAVS.sol";
import {IDelegationManagerTypes} from "lib/eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {BeaconChainMock} from "lib/eigenlayer-contracts/src/test/integration/mocks/BeaconChainMock.t.sol";

contract StakingNodeOperatorSlashing is StakingNodeTestBase {
    using stdStorage for StdStorage;
    using BytesLib for bytes;
    using SlashingLib for *;


    address user = vm.addr(156_737);
    uint40[] validatorIndices;

    address avs;
    address operator1 = address(0x9999);
    address operator2 = address(0x8888);

    uint256 nodeId;
    IStakingNode stakingNodeInstance;
    IAllocationManager allocationManager;
    uint256 validatorCount = 2;
    uint256 totalDepositedAmount;

    function setUp() public override {
        super.setUp();

        avs = address(new MockAVS());

        address[] memory operators = new address[](2);
        operators[0] = operator1;
        operators[1] = operator2;

        for (uint256 i = 0; i < operators.length; i++) {
            vm.prank(operators[i]);
            delegationManager.registerAsOperator(address(0),1, "ipfs://some-ipfs-hash");
        }

        vm.roll(block.number + 2);

        nodeId = createStakingNodes(1)[0];
        stakingNodeInstance = stakingNodesManager.nodes(nodeId);

        vm.prank(actors.admin.STAKING_NODES_DELEGATOR);
        stakingNodeInstance.delegate(
            operator1, ISignatureUtilsMixinTypes.SignatureWithExpiry({signature: "", expiry: 0}), bytes32(0)
        );

        allocationManager = IAllocationManager(chainAddresses.eigenlayer.ALLOCATION_MANAGER_ADDRESS);
        IStrategy[] memory strategies = new IStrategy[](1);
        strategies[0] = IStrategy(stakingNodeInstance.beaconChainETHStrategy());
        IAllocationManagerTypes.CreateSetParams[] memory createSetParams = new IAllocationManagerTypes.CreateSetParams[](1);
        createSetParams[0] = IAllocationManagerTypes.CreateSetParams({
            operatorSetId: 1,
            strategies: strategies
        });
    
        vm.startPrank(avs);
        allocationManager.updateAVSMetadataURI(avs, "ipfs://some-metadata-uri");
        allocationManager.createOperatorSets(avs, createSetParams);
        vm.stopPrank();

        uint32 allocationConfigurationDelay = AllocationManagerStorage(address(allocationManager)).ALLOCATION_CONFIGURATION_DELAY();

        uint32[] memory operatorSetIds = new uint32[](1); 
        operatorSetIds[0] = uint32(1);
        IAllocationManagerTypes.RegisterParams memory registerParams = IAllocationManagerTypes.RegisterParams({
            avs: avs,
            operatorSetIds: operatorSetIds,
            data: ""
        });
        OperatorSet memory operatorSet = OperatorSet({
            avs: avs,
            id: 1
        });
        uint64[] memory newMagnitudes = new uint64[](1);
        newMagnitudes[0] = uint64(1 ether);
        IAllocationManagerTypes.AllocateParams[] memory allocateParams = new IAllocationManagerTypes.AllocateParams[](1);
        allocateParams[0] = IAllocationManagerTypes.AllocateParams({
            operatorSet: operatorSet,
            strategies: strategies,
            newMagnitudes: newMagnitudes
        });
    
        vm.roll(block.number + allocationConfigurationDelay + 2);
        vm.startPrank(operator1);
        allocationManager.registerForOperatorSets(operator1, registerParams);
        allocationManager.modifyAllocations(operator1, allocateParams);
        vm.stopPrank();

        vm.roll(block.number + allocationConfigurationDelay + 2);

        uint256 depositAmount = 32 ether;
        totalDepositedAmount = depositAmount * validatorCount;
        user = vm.addr(156_737);
        vm.deal(user, 1000 ether);
        yneth.depositETH{value: totalDepositedAmount}(user);

        // Create and setup validators
        validatorIndices = createValidators(repeat(nodeId, validatorCount), validatorCount);
        beaconChain.advanceEpoch_NoRewards();
        registerValidators(repeat(nodeId, validatorCount));
        beaconChain.advanceEpoch_NoRewards();

        for (uint256 i = 0; i < validatorCount; i++) {
            _verifyWithdrawalCredentials(nodeId, validatorIndices[i]);
        }
        beaconChain.advanceEpoch_NoRewards();
    }

    function testSlashedOperatorBeforeQueuedWithdrawals(uint256 slashingPercent) public {

        vm.assume(slashingPercent > 0 && slashingPercent <= 1 ether);

        // Capture initial state
        StateSnapshot memory initialState = takeSnapshot(nodeId);
        IStrategy beaconChainETHStrategy = stakingNodeInstance.beaconChainETHStrategy();
        uint256 beaconChainSlashingFactorBefore = eigenPodManager.beaconChainSlashingFactor(address(stakingNodeInstance));
        uint256 operatorMaxMagnitudeBefore = allocationManager.getMaxMagnitude(operator1, beaconChainETHStrategy);

        // Start and verify checkpoint for all validators
        startAndVerifyCheckpoint(nodeId, validatorIndices);

        {
            IStrategy[] memory strategies = new IStrategy[](1);
            strategies[0] = IStrategy(stakingNodeInstance.beaconChainETHStrategy());
            uint256[] memory wadsToSlash = new uint256[](1);
            wadsToSlash[0] = slashingPercent; // slash 30% of the operator's stake
            IAllocationManagerTypes.SlashingParams memory slashingParams = IAllocationManagerTypes.SlashingParams({
                operator: operator1,
                operatorSetId: 1,
                strategies: strategies,
                wadsToSlash: wadsToSlash,
                description: "Slashing operator1"
            });

            vm.prank(avs);
            allocationManager.slashOperator(avs, slashingParams);

            stakingNodeInstance.stakingNodesManager().updateTotalETHStaked();
        }

        {
            // Get final state
            StateSnapshot memory finalState = takeSnapshot(nodeId);
            uint256 beaconChainSlashingFactorAfter = eigenPodManager.beaconChainSlashingFactor(address(stakingNodeInstance));
            uint256 operatorMaxMagnitudeAfter = allocationManager.getMaxMagnitude(operator1, beaconChainETHStrategy);

            uint256 slashedAmountInWei = totalDepositedAmount.mulWad(slashingPercent);
            // Assert
            assertEq(beaconChainSlashingFactorBefore, beaconChainSlashingFactorAfter, "Beacon chain slashing factor should not change");
            assertLt(operatorMaxMagnitudeAfter, operatorMaxMagnitudeBefore, "Operator max magnitude should decrease due to slashing");
            assertEq(finalState.totalAssets, initialState.totalAssets - slashedAmountInWei, "Total assets should decrease by slashed amount");
            assertEq(finalState.totalSupply, initialState.totalSupply, "Total supply should remain unchanged");
            assertEq(
                finalState.stakingNodeBalance,
                initialState.stakingNodeBalance - slashedAmountInWei,
                "Staking node balance should decrease by slashed amount"
            );
            assertEq(
                finalState.queuedShares,
                initialState.queuedShares,
                "Queued shares should remain unchanged"
            );
            assertEq(finalState.withdrawnETH, initialState.withdrawnETH, "Withdrawn ETH should remain unchanged");
            assertEq(
                finalState.unverifiedStakedETH,
                initialState.unverifiedStakedETH,
                "Unverified staked ETH should remain unchanged"
            );
            assertEq(
                finalState.podOwnerDepositShares,
                initialState.podOwnerDepositShares,
                "Pod owner shares should remain unchanged"
            );
        }
    }

    function testSlashedOperatorBetweenQueuedAndCompletedWithdrawals() public {

        // Capture initial state
        StateSnapshot memory initialState = takeSnapshot(nodeId);
        IStrategy beaconChainETHStrategy = stakingNodeInstance.beaconChainETHStrategy();
        uint256 beaconChainSlashingFactorBefore = eigenPodManager.beaconChainSlashingFactor(address(stakingNodeInstance));
        uint256 operatorMaxMagnitudeBefore = allocationManager.getMaxMagnitude(operator1, beaconChainETHStrategy);

        uint256 withdrawalAmount = 32 ether;
        uint256 expectedWithdrawalAmount;
        {
            // Queue withdrawals for all validators
            vm.prank(actors.ops.STAKING_NODES_WITHDRAWER);
            bytes32[] memory withdrawalRoots = stakingNodeInstance.queueWithdrawals(withdrawalAmount);

            uint256 queuedSharesAmountBeforeSlashing = stakingNodeInstance.queuedSharesAmount();
            assertEq(queuedSharesAmountBeforeSlashing, withdrawalAmount, "Queued shares should be equal to withdrawal amount");

            // Exit validator
            beaconChain.exitValidator(validatorIndices[0]);
            beaconChain.advanceEpoch_NoRewards();

            // Start and verify checkpoint for all validators
            startAndVerifyCheckpoint(nodeId, validatorIndices);

            uint256 slashingPercent = 0.3 ether;
            {
                IStrategy[] memory strategies = new IStrategy[](1);
                strategies[0] = IStrategy(stakingNodeInstance.beaconChainETHStrategy());
                uint256[] memory wadsToSlash = new uint256[](1);
                wadsToSlash[0] = slashingPercent; // slash 30% of the operator's stake
                IAllocationManagerTypes.SlashingParams memory slashingParams = IAllocationManagerTypes.SlashingParams({
                    operator: operator1,
                    operatorSetId: 1,
                    strategies: strategies,
                    wadsToSlash: wadsToSlash,
                    description: "Slashing operator1"
                });

                vm.prank(avs);
                allocationManager.slashOperator(avs, slashingParams);

                // expect revert when completing withdrawals due to syncQueuedShares not done
                _completeQueuedWithdrawals(withdrawalRoots, nodeId, true);

                vm.prank(actors.admin.STAKING_NODES_DELEGATOR);
                stakingNodeInstance.syncQueuedShares();
            }
            {
                uint256 nodeBalanceReceived;
                uint256 nodeBalanceBeforeWithdrawal = address(stakingNodeInstance).balance;
                _completeQueuedWithdrawals(withdrawalRoots, nodeId, false);
                uint256 nodeBalanceAfterWithdrawal = address(stakingNodeInstance).balance;
                nodeBalanceReceived = nodeBalanceAfterWithdrawal - nodeBalanceBeforeWithdrawal;
                expectedWithdrawalAmount = withdrawalAmount.mulWad(1 ether - slashingPercent);
                assertEq(nodeBalanceReceived, expectedWithdrawalAmount, "Node's ETH balance should increase by expected withdrawal amount");
            }
        }

        stakingNodeInstance.stakingNodesManager().updateTotalETHStaked();

        {
            // Get final state
            StateSnapshot memory finalState = takeSnapshot(nodeId);
            uint256 beaconChainSlashingFactorAfter = eigenPodManager.beaconChainSlashingFactor(address(stakingNodeInstance));
            uint256 operatorMaxMagnitudeAfter = allocationManager.getMaxMagnitude(operator1, beaconChainETHStrategy);
            uint256 slashedAmount = totalDepositedAmount - totalDepositedAmount.mulWad(operatorMaxMagnitudeAfter);

            // Assert
            assertEq(beaconChainSlashingFactorBefore, beaconChainSlashingFactorAfter, "Beacon chain slashing factor should not change");
            assertLt(operatorMaxMagnitudeAfter, operatorMaxMagnitudeBefore, "Operator max magnitude should decrease due to slashing");
            assertEq(finalState.totalAssets, initialState.totalAssets - slashedAmount, "Total assets should decrease by slashed amount");
            assertEq(finalState.totalSupply, initialState.totalSupply, "Total supply should remain unchanged");
            assertEq(
                finalState.stakingNodeBalance,
                initialState.stakingNodeBalance - slashedAmount,
                "Staking node balance should decrease by slashed amount"
            );
            assertEq(
                finalState.queuedShares,
                initialState.queuedShares,
                "Queued shares should remain unchanged"
            );
            assertEq(finalState.withdrawnETH, initialState.withdrawnETH + expectedWithdrawalAmount, "Withdrawn ETH should remain unchanged");
            assertEq(
                finalState.unverifiedStakedETH,
                initialState.unverifiedStakedETH,
                "Unverified staked ETH should remain unchanged"
            );
            assertEq(
                finalState.podOwnerDepositShares,
                initialState.podOwnerDepositShares - int256(withdrawalAmount),
                "Pod owner shares should remain unchanged"
            );
        }
    }

    function testSlashedOperatorAfterCompletedWithdrawals() public {

        // Capture initial state
        StateSnapshot memory initialState = takeSnapshot(nodeId);
        IStrategy beaconChainETHStrategy = stakingNodeInstance.beaconChainETHStrategy();
        uint256 beaconChainSlashingFactorBefore = eigenPodManager.beaconChainSlashingFactor(address(stakingNodeInstance));
        uint256 operatorMaxMagnitudeBefore = allocationManager.getMaxMagnitude(operator1, beaconChainETHStrategy);

        // Queue and complete withdrawals before slashing
        uint256 withdrawalAmount = 32 ether;
        bytes32[] memory withdrawalRoots;
        {
            vm.prank(actors.ops.STAKING_NODES_WITHDRAWER);
            withdrawalRoots = stakingNodeInstance.queueWithdrawals(withdrawalAmount);

            beaconChain.exitValidator(validatorIndices[0]);
            beaconChain.advanceEpoch_NoRewards();
            startAndVerifyCheckpoint(nodeId, validatorIndices);

            uint256 nodeBalanceBeforeWithdrawal = address(stakingNodeInstance).balance;
            _completeQueuedWithdrawals(withdrawalRoots, nodeId, false);
            uint256 nodeBalanceAfterWithdrawal = address(stakingNodeInstance).balance;
            uint256 nodeBalanceReceived = nodeBalanceAfterWithdrawal - nodeBalanceBeforeWithdrawal;
            assertEq(nodeBalanceReceived, withdrawalAmount, "Node should receive full withdrawal amount before slashing");
        }

        // Perform slashing after withdrawals
        uint256 slashingPercent = 0.3 ether;
        {
            IStrategy[] memory strategies = new IStrategy[](1);
            strategies[0] = IStrategy(stakingNodeInstance.beaconChainETHStrategy());
            uint256[] memory wadsToSlash = new uint256[](1);
            wadsToSlash[0] = slashingPercent;

            IAllocationManagerTypes.SlashingParams memory slashingParams = IAllocationManagerTypes.SlashingParams({
                operator: operator1,
                operatorSetId: 1,
                strategies: strategies,
                wadsToSlash: wadsToSlash,
                description: "Slashing operator1 after withdrawals"
            });

            vm.prank(avs);
            allocationManager.slashOperator(avs, slashingParams);
        }

        stakingNodeInstance.stakingNodesManager().updateTotalETHStaked();

        // Verify final state
        {
            StateSnapshot memory finalState = takeSnapshot(nodeId);
            uint256 beaconChainSlashingFactorAfter = eigenPodManager.beaconChainSlashingFactor(address(stakingNodeInstance));
            uint256 operatorMaxMagnitudeAfter = allocationManager.getMaxMagnitude(operator1, beaconChainETHStrategy);
            uint256 remainingDeposit = totalDepositedAmount - withdrawalAmount;
            uint256 slashedAmount = remainingDeposit - remainingDeposit.mulWad(1 ether - slashingPercent);
            uint256 expectedTotalAssets = withdrawalAmount + remainingDeposit - slashedAmount;

            // Assertions
            assertEq(beaconChainSlashingFactorBefore, beaconChainSlashingFactorAfter, "Beacon chain slashing factor should not change");
            assertLt(operatorMaxMagnitudeAfter, operatorMaxMagnitudeBefore, "Operator max magnitude should decrease");
            assertEq(finalState.totalAssets, expectedTotalAssets, "Total assets should reflect withdrawal and slashing");
            assertEq(finalState.totalSupply, initialState.totalSupply, "Total supply should remain unchanged");
            assertEq(finalState.withdrawnETH, initialState.withdrawnETH + withdrawalAmount, "Withdrawn ETH should increase by withdrawal amount");
            assertEq(finalState.podOwnerDepositShares, initialState.podOwnerDepositShares - int256(withdrawalAmount), "Pod owner shares should decrease by withdrawal amount");
        }
    }
}

contract StakingNodeValidatorSlashing is StakingNodeTestBase {

    using SlashingLib for *;

    function testQueueWithdrawalsWithSlashedValidator() public {
        uint256 validatorCount = 2;
        uint256 totalDepositedAmount;

        {
            // Setup
            uint256 depositAmount = 32 ether;
            totalDepositedAmount = depositAmount * validatorCount;
            address user = vm.addr(156_737);
            vm.deal(user, 1000 ether);
            yneth.depositETH{value: totalDepositedAmount}(user); // Deposit for validators
        }

        uint256 nodeId = createStakingNodes(1)[0];
        IStakingNode stakingNodeInstance = stakingNodesManager.nodes(nodeId);

        // Setup: Create multiple validators and verify withdrawal credentials
        uint40[] memory validatorIndices = createValidators(repeat(nodeId, validatorCount), validatorCount);
        beaconChain.advanceEpoch_NoRewards();
        registerValidators(repeat(nodeId, validatorCount));

        beaconChain.advanceEpoch_NoRewards();

        for (uint256 i = 0; i < validatorCount; i++) {
            _verifyWithdrawalCredentials(nodeId, validatorIndices[i]);
        }

        beaconChain.advanceEpoch_NoRewards();

        uint256 slashedValidatorCount = 1;
        // Slash some validators
        uint40[] memory slashedValidators = new uint40[](slashedValidatorCount);
        for (uint256 i = 0; i < slashedValidatorCount; i++) {
            slashedValidators[i] = validatorIndices[i];
        }

        // Capture initial state
        StateSnapshot memory initialState = takeSnapshot(nodeId);
            
        beaconChain.slashValidators(slashedValidators, BeaconChainMock.SlashType.Minor);

        beaconChain.advanceEpoch_NoRewards();

        uint256 beaconChainSlashingFactorBefore = eigenPodManager.beaconChainSlashingFactor(address(stakingNodeInstance));

        // Start and verify checkpoint for all validators
        startAndVerifyCheckpoint(nodeId, validatorIndices);

        uint256 beaconChainSlashingFactorAfter = eigenPodManager.beaconChainSlashingFactor(address(stakingNodeInstance));

         // Queue withdrawals
        uint256 withdrawalAmount = 1 ether;
        vm.prank(actors.ops.STAKING_NODES_WITHDRAWER);
        bytes32[] memory withdrawalRoots = stakingNodeInstance.queueWithdrawals(withdrawalAmount);
        (IDelegationManagerTypes.Withdrawal memory withdrawal, ) = delegationManager.getQueuedWithdrawal(withdrawalRoots[0]);
        uint256 scaledShares = withdrawal.scaledShares[0];
        uint256 withdrawableShares = scaledShares.mulWad(beaconChainSlashingFactorAfter);

        // Get final state
        StateSnapshot memory finalState = takeSnapshot(nodeId);

        uint256 slashedAmountInWei = beaconChain.MINOR_SLASH_AMOUNT_GWEI() * 1e9;
        // Assert
        assertLt(beaconChainSlashingFactorAfter, beaconChainSlashingFactorBefore, "Beacon chain slashing factor should decrease due to slashing");
        assertEq(finalState.totalAssets, initialState.totalAssets, "Total assets should remain unchanged");
        assertEq(finalState.totalSupply, initialState.totalSupply, "Total supply should remain unchanged");
        assertEq(
            finalState.stakingNodeBalance,
            initialState.stakingNodeBalance - slashedAmountInWei,
            "Staking node balance should decrease by slashed amount"
        );
        assertEq(
            finalState.queuedShares,
            initialState.queuedShares + withdrawableShares,
            "Queued shares should increase by withdrawal amount"
        );
        assertEq(finalState.withdrawnETH, initialState.withdrawnETH, "Withdrawn ETH should remain unchanged");
        assertEq(
            finalState.unverifiedStakedETH,
            initialState.unverifiedStakedETH,
            "Unverified staked ETH should remain unchanged"
        );
        assertEq(
            finalState.podOwnerDepositShares,
            initialState.podOwnerDepositShares - int256(withdrawalAmount),
            "Pod owner shares should decrease by withdrawalAmount"
        );
    }

     function testCompleteQueuedWithdrawalsWithSlashedValidatorsBeforeQueuing() public {
        uint256 validatorCount = 2;
        uint256 totalDepositedAmount;

        {
            // Setup
            uint256 depositAmount = 32 ether;
            totalDepositedAmount = depositAmount * validatorCount;
            address user = vm.addr(156_737);
            vm.deal(user, 1000 ether);
            yneth.depositETH{value: totalDepositedAmount}(user); // Deposit for validators
        }

        uint256 nodeId = createStakingNodes(1)[0];
        IStakingNode stakingNodeInstance = stakingNodesManager.nodes(nodeId);

        // Setup: Create multiple validators and verify withdrawal credentials
        uint40[] memory validatorIndices = createValidators(repeat(nodeId, validatorCount), validatorCount);
        beaconChain.advanceEpoch_NoRewards();
        registerValidators(repeat(nodeId, validatorCount));

        beaconChain.advanceEpoch_NoRewards();

        for (uint256 i = 0; i < validatorCount; i++) {
            _verifyWithdrawalCredentials(nodeId, validatorIndices[i]);
        }

        beaconChain.advanceEpoch_NoRewards();

        uint256 slashedValidatorCount = 1;
        // Slash some validators
        uint40[] memory slashedValidators = new uint40[](slashedValidatorCount);
        for (uint256 i = 0; i < slashedValidatorCount; i++) {
            slashedValidators[i] = validatorIndices[i];
        }
            
        beaconChain.slashValidators(slashedValidators, BeaconChainMock.SlashType.Minor);

        beaconChain.advanceEpoch_NoRewards();

        // Exit remaining validators
        uint256 exitedValidatorCount = validatorCount - slashedValidatorCount;
        for (uint256 i = slashedValidatorCount; i < validatorCount; i++) {
            beaconChain.exitValidator(validatorIndices[i]);
        }

        // Advance the beacon chain by one epoch without rewards
        beaconChain.advanceEpoch_NoRewards();

        // Capture initial state
        StateSnapshot memory before = takeSnapshot(nodeId);

        // Start and verify checkpoint for all validators
        startAndVerifyCheckpoint(nodeId, validatorIndices);

        // Calculate expected withdrawal amount (slashed validators lose 1 ETH each)
        uint256 withdrawalAmount = (32 ether * exitedValidatorCount);

        // Queue withdrawals for all validators
        vm.prank(actors.ops.STAKING_NODES_WITHDRAWER);
        bytes32[] memory withdrawalRoots = stakingNodeInstance.queueWithdrawals(withdrawalAmount);

        _completeQueuedWithdrawals(withdrawalRoots, nodeId, false);

        // Capture final state
        StateSnapshot memory afterCompletion = takeSnapshot(nodeId);
        uint256 _beaconChainSlashingFactor = eigenPodManager.beaconChainSlashingFactor(address(stakingNodeInstance));
        uint256 expectedWithdrawalAmount = withdrawalAmount.mulWad(_beaconChainSlashingFactor);
        uint256 slashedAmount = totalDepositedAmount - totalDepositedAmount.mulWad(_beaconChainSlashingFactor);

        // Assertions
        assertEq(
            afterCompletion.withdrawnETH,
            before.withdrawnETH + expectedWithdrawalAmount,
            "Withdrawn ETH should increase by the expected withdrawal amount"
        );
        assertEq(
            afterCompletion.podOwnerDepositShares,
            before.podOwnerDepositShares - int256(withdrawalAmount),
            "Pod owner shares should decrease by withdrawalAmount"
        );
        assertEq(
            afterCompletion.stakingNodeBalance + slashedAmount,
            before.stakingNodeBalance,
            "Staking node balance should decrease by slashedAmount"
        );
    }

    function testCompleteQueuedWithdrawalsWithSlashedValidatorsBetweenQueuingAndCompletion() public {
        uint256 validatorCount = 2;
        uint256 totalDepositedAmount;

        {
            // Setup
            uint256 depositAmount = 32 ether;
            totalDepositedAmount = depositAmount * validatorCount;
            address user = vm.addr(156_737);
            vm.deal(user, 1000 ether);
            yneth.depositETH{value: totalDepositedAmount}(user); // Deposit for validators
        }

        uint256 nodeId = createStakingNodes(1)[0];
        IStakingNode stakingNodeInstance = stakingNodesManager.nodes(nodeId);

        // Setup: Create multiple validators and verify withdrawal credentials
        uint40[] memory validatorIndices = createValidators(repeat(nodeId, validatorCount), validatorCount);
        beaconChain.advanceEpoch_NoRewards();
        registerValidators(repeat(nodeId, validatorCount));

        beaconChain.advanceEpoch_NoRewards();

        for (uint256 i = 0; i < validatorCount; i++) {
            _verifyWithdrawalCredentials(nodeId, validatorIndices[i]);
        }

        beaconChain.advanceEpoch_NoRewards();

        uint256 slashedValidatorCount = 1;
        // Slash some validators
        uint40[] memory slashedValidators = new uint40[](slashedValidatorCount);
        for (uint256 i = 0; i < slashedValidatorCount; i++) {
            slashedValidators[i] = validatorIndices[i];
        }
            

        // Advance the beacon chain by one epoch without rewards
        beaconChain.advanceEpoch_NoRewards();

        // Capture initial state
        StateSnapshot memory before = takeSnapshot(nodeId);

        uint256 exitedValidatorCount = validatorCount - slashedValidatorCount;

        // Calculate expected withdrawal amount (slashed validators lose 1 ETH each)
        uint256 withdrawalAmount = (32 ether * exitedValidatorCount);

        // Queue withdrawals for all validators
        vm.prank(actors.ops.STAKING_NODES_WITHDRAWER);
        bytes32[] memory withdrawalRoots = stakingNodeInstance.queueWithdrawals(withdrawalAmount);

        {
            uint256 queuedSharesAmountBeforeSlashing = stakingNodeInstance.queuedSharesAmount();
            assertEq(queuedSharesAmountBeforeSlashing, withdrawalAmount, "Queued shares should be equal to withdrawal amount");

            beaconChain.slashValidators(slashedValidators, BeaconChainMock.SlashType.Minor);

            // Exit remaining validators
            for (uint256 i = slashedValidatorCount; i < validatorCount; i++) {
                beaconChain.exitValidator(validatorIndices[i]);
            }

            beaconChain.advanceEpoch_NoRewards();

            // Start and verify checkpoint for all validators
            startAndVerifyCheckpoint(nodeId, validatorIndices);

            _completeQueuedWithdrawals(withdrawalRoots, nodeId, true);

            vm.prank(actors.admin.STAKING_NODES_DELEGATOR);
            stakingNodeInstance.syncQueuedShares();

            uint256 queuedSharesAmountAfterSlashing = stakingNodeInstance.queuedSharesAmount();
            assertLt(queuedSharesAmountAfterSlashing, queuedSharesAmountBeforeSlashing, "Queued shares should decrease after slashing");
        }

        {
            uint256 _beaconChainSlashingFactor = eigenPodManager.beaconChainSlashingFactor(address(stakingNodeInstance));
            uint256 expectedWithdrawalAmount = withdrawalAmount.mulWad(_beaconChainSlashingFactor);
            uint256 slashedAmount = totalDepositedAmount - totalDepositedAmount.mulWad(_beaconChainSlashingFactor);

            // Assertions
             uint256 nodeBalanceBeforeWithdrawal = address(stakingNodeInstance).balance;
            _completeQueuedWithdrawals(withdrawalRoots, nodeId, false);
            uint256 nodeBalanceAfterWithdrawal = address(stakingNodeInstance).balance;

            // Capture final state
            StateSnapshot memory afterCompletion = takeSnapshot(nodeId);

            assertEq(nodeBalanceAfterWithdrawal - nodeBalanceBeforeWithdrawal, expectedWithdrawalAmount, "Node's ETH balance should increase by expected withdrawal amount");

            assertEq(
                afterCompletion.withdrawnETH,
                before.withdrawnETH + expectedWithdrawalAmount,
                "Withdrawn ETH should increase by the expected withdrawal amount"
            );
            assertEq(
                afterCompletion.podOwnerDepositShares,
                before.podOwnerDepositShares - int256(withdrawalAmount),
                "Pod owner shares should decrease by withdrawalAmount"
            );
            assertEq(
                afterCompletion.stakingNodeBalance + slashedAmount,
                before.stakingNodeBalance,
                "Staking node balance should decrease by slashedAmount"
            );
        }
    }

    function testCompleteQueuedWithdrawalsWithSlashedValidatorsAfterCompletion() public {
        uint256 validatorCount = 2;
        uint256 totalDepositedAmount;

        {
            // Setup
            uint256 depositAmount = 32 ether;
            totalDepositedAmount = depositAmount * validatorCount;
            address user = vm.addr(156_737);
            vm.deal(user, 1000 ether);
            yneth.depositETH{value: totalDepositedAmount}(user); // Deposit for validators
        }

        uint256 nodeId = createStakingNodes(1)[0];
        IStakingNode stakingNodeInstance = stakingNodesManager.nodes(nodeId);

        // Setup: Create multiple validators and verify withdrawal credentials
        uint40[] memory validatorIndices = createValidators(repeat(nodeId, validatorCount), validatorCount);
        beaconChain.advanceEpoch_NoRewards();
        registerValidators(repeat(nodeId, validatorCount));

        beaconChain.advanceEpoch_NoRewards();

        for (uint256 i = 0; i < validatorCount; i++) {
            _verifyWithdrawalCredentials(nodeId, validatorIndices[i]);
        }

        beaconChain.advanceEpoch_NoRewards();

        uint256 slashedValidatorCount = 1;
        // Slash some validators
        uint40[] memory slashedValidators = new uint40[](slashedValidatorCount);
        for (uint256 i = 0; i < slashedValidatorCount; i++) {
            slashedValidators[i] = validatorIndices[i];
        }

        // Exit remaining validators
        uint256 exitedValidatorCount = validatorCount - slashedValidatorCount;
        for (uint256 i = slashedValidatorCount; i < validatorCount; i++) {
            beaconChain.exitValidator(validatorIndices[i]);
        }

        // Advance the beacon chain by one epoch without rewards
        beaconChain.advanceEpoch_NoRewards();

        // Capture initial state
        StateSnapshot memory before = takeSnapshot(nodeId);

        // Start and verify checkpoint for all validators
        startAndVerifyCheckpoint(nodeId, validatorIndices);

        // Calculate expected withdrawal amount (slashed validators lose 1 ETH each)
        uint256 withdrawalAmount = (32 ether * exitedValidatorCount);

        // Queue withdrawals for all validators
        vm.prank(actors.ops.STAKING_NODES_WITHDRAWER);
        bytes32[] memory withdrawalRoots = stakingNodeInstance.queueWithdrawals(withdrawalAmount);

        _completeQueuedWithdrawals(withdrawalRoots, nodeId, false);

        beaconChain.slashValidators(slashedValidators, BeaconChainMock.SlashType.Minor);

        beaconChain.advanceEpoch_NoRewards();

        // Capture final state
        StateSnapshot memory afterCompletion = takeSnapshot(nodeId);
        uint256 _beaconChainSlashingFactor = eigenPodManager.beaconChainSlashingFactor(address(stakingNodeInstance));
        uint256 expectedWithdrawalAmount = withdrawalAmount.mulWad(_beaconChainSlashingFactor);
        uint256 slashedAmount = totalDepositedAmount - totalDepositedAmount.mulWad(_beaconChainSlashingFactor);

        // Assertions
        assertEq(
            afterCompletion.withdrawnETH,
            before.withdrawnETH + expectedWithdrawalAmount,
            "Withdrawn ETH should increase by the expected withdrawal amount"
        );
        assertEq(
            afterCompletion.podOwnerDepositShares,
            before.podOwnerDepositShares - int256(withdrawalAmount),
            "Pod owner shares should decrease by withdrawalAmount"
        );
        assertEq(
            afterCompletion.stakingNodeBalance + slashedAmount,
            before.stakingNodeBalance,
            "Staking node balance should decrease by slashedAmount"
        );
    }

}