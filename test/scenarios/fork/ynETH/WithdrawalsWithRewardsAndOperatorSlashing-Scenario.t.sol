// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IEigenPod} from "lib/eigenlayer-contracts/src/contracts/interfaces/IEigenPod.sol";
import {Math} from "lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import {IStrategy} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IAllocationManager, IAllocationManagerTypes} from "lib/eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {IStakingNode} from "src/interfaces/IStakingNode.sol";
import {IStakingNodesManager} from "src/interfaces/IStakingNodesManager.sol";
import {IWithdrawalQueueManager} from "src/interfaces/IWithdrawalQueueManager.sol";
import {BeaconChainMock, BeaconChainProofs, CheckpointProofs, CredentialProofs, EigenPodManager} from "lib/eigenlayer-contracts/src/test/integration/mocks/BeaconChainMock.t.sol";
import {Utils} from "script/Utils.sol";
import {ContractAddresses} from "script/ContractAddresses.sol";
import {ActorAddresses} from "script/Actors.sol";
import {BeaconChainMock} from "lib/eigenlayer-contracts/src/test/integration/mocks/BeaconChainMock.t.sol";
import {MockAVS} from "test/mocks/MockAVS.sol";
import {WithdrawalsScenarioTestBase, IPod, IStakingNodeVars} from "./WithdrawalsScenarioTestBase.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";
import {BytesLib} from "lib/eigenlayer-contracts/src/test/utils/BytesLib.sol";
import {SlashingLib} from "lib/eigenlayer-contracts/src/contracts/libraries/SlashingLib.sol";
import {IAllocationManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {AllocationManagerStorage} from "lib/eigenlayer-contracts/src/contracts/core/AllocationManagerStorage.sol";
import {StakingNode} from "src/StakingNode.sol";
import {ISignatureUtilsMixinTypes} from "lib/eigenlayer-contracts/src/contracts/interfaces/ISignatureUtilsMixin.sol";
import {OperatorSet} from "lib/eigenlayer-contracts/src/contracts/libraries/OperatorSetLib.sol";
import {console} from "forge-std/console.sol";
import {IDelegationManager, IDelegationManagerTypes} from "lib/eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";

contract WithdrawalsWithRewardsAndOperatorSlashingTest is WithdrawalsScenarioTestBase {
    using stdStorage for StdStorage;
    using BytesLib for bytes;
    using SlashingLib for *;

    address public user = vm.addr(420);
    address avs;

    uint256 public amount;
    uint40[] validatorIndices;
    uint256 public nodeId;
    IStakingNode stakingNodeInstance;
    IAllocationManager allocationManager;

    address operator1 = address(0x9999);
    address operator2 = address(0x8888);


    function setupAVS(uint256 _nodeId) internal {
       avs = address(new MockAVS());


        address[] memory operators = new address[](2);
        operators[0] = operator1;
        operators[1] = operator2;

        for (uint256 i = 0; i < operators.length; i++) {
            vm.prank(operators[i]);
            delegationManager.registerAsOperator(address(0),1, "ipfs://some-ipfs-hash");
        }

        vm.roll(block.number + 2);

        IStakingNode _stakingNodeInstance = stakingNodesManager.nodes(_nodeId);

        vm.prank(actors.admin.STAKING_NODES_DELEGATOR);
        _stakingNodeInstance.delegate(
            operator1, ISignatureUtilsMixinTypes.SignatureWithExpiry({signature: "", expiry: 0}), bytes32(0)
        );


        allocationManager = IAllocationManager(chainAddresses.eigenlayer.ALLOCATION_MANAGER_ADDRESS);
        IStrategy[] memory strategies = new IStrategy[](1);
        strategies[0] = IStrategy(_stakingNodeInstance.beaconChainETHStrategy());
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
    }

    function setUp() public override {
        super.setUp();

 
    }

    function registerVerifiedValidators(
       uint256 totalDepositAmountInNewNode
    ) private returns (TestState memory state) {
        (state, nodeId, amount, validatorIndices) = super.registerVerifiedValidators(user, totalDepositAmountInNewNode);
    }

    function startAndVerifyCheckpoint(uint256 _nodeId, TestState memory state) private {
        super.startAndVerifyCheckpoint(_nodeId, state, validatorIndices);
    }

    function test_userWithdrawalWithRewards_Scenario_6_OperatorSlashing() public {

        // deposit 100 ETH into ynETH
        TestState memory state = registerVerifiedValidators(100 ether);

        stakingNodeInstance = stakingNodesManager.nodes(nodeId);

        setupAVS(nodeId);

        uint256 accumulatedRewards;
        {
            uint256 epochCount = 30;
            // Advance the beacon chain by 100 epochs to simulate rewards accumulation
            for (uint256 i = 0; i < epochCount; i++) {
                beaconChain.advanceEpoch();
            }
            accumulatedRewards += state.validatorCount * epochCount * 1e9; // 1 GWEI per Epoch per Validator
        }

        // exit validators
        {
            for (uint256 i = 0; i < validatorIndices.length; i++) {
                beaconChain.exitValidator(validatorIndices[i]);
            }
            beaconChain.advanceEpoch();
        }

        runSystemStateInvariants(state.totalAssetsBefore, state.totalSupplyBefore, state.stakingNodeBalancesBefore);

        startAndVerifyCheckpoint(nodeId, state);

        // Rewards accumulated are accounted after verifying the checkpoint
        state.totalAssetsBefore += accumulatedRewards;
        state.stakingNodeBalancesBefore[nodeId] += accumulatedRewards;

        runSystemStateInvariants(state.totalAssetsBefore, state.totalSupplyBefore, state.stakingNodeBalancesBefore);

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

            stakingNodeInstance.stakingNodesManager().updateTotalETHStaked();
        }

        {
            // decrease based on slashing amount
            uint256 totalAssetsSlashed = state.stakingNodeBalancesBefore[nodeId]  * slashingPercent / 1e18;
            state.totalAssetsBefore = state.totalAssetsBefore - totalAssetsSlashed;
            state.stakingNodeBalancesBefore[nodeId] = state.stakingNodeBalancesBefore[nodeId] - totalAssetsSlashed;
        }

        runSystemStateInvariants(state.totalAssetsBefore, state.totalSupplyBefore, state.stakingNodeBalancesBefore);
        
        // Calculate the total amount that would be withdrawn if no slashing occurred
        // This includes the principal amount (32 ETH per validator) plus any accumulated rewards
        // We need this value to properly queue withdrawals, even though the actual amount
        // received will be reduced due to the slashing that occurred
        uint256 unslashedWithdrawalAmount = 32 ether * validatorIndices.length + accumulatedRewards;
        
        uint256 withdrawnAmount = unslashedWithdrawalAmount - unslashedWithdrawalAmount * slashingPercent / 1e18;
        // queue withdrawals
        {
            vm.startPrank(actors.ops.STAKING_NODES_WITHDRAWER);
            stakingNodesManager.nodes(nodeId).queueWithdrawals(unslashedWithdrawalAmount);
            vm.stopPrank();
        }

        QueuedWithdrawalInfo[] memory withdrawalInfos = new QueuedWithdrawalInfo[](1);
        withdrawalInfos[0] = QueuedWithdrawalInfo({
            nodeId: nodeId,
            withdrawnAmount: unslashedWithdrawalAmount
        });
        completeQueuedWithdrawals(nodeId, withdrawalInfos);

        runSystemStateInvariants(state.totalAssetsBefore, state.totalSupplyBefore, state.stakingNodeBalancesBefore);

        uint256 userWithdrawalAmount = 30 ether;
        uint256 amountToReinvest = withdrawnAmount - userWithdrawalAmount - accumulatedRewards;

        {
            IStakingNodesManager.WithdrawalAction[] memory _actions = new IStakingNodesManager.WithdrawalAction[](1);
            _actions[0] = IStakingNodesManager.WithdrawalAction({
                nodeId: nodeId,
                amountToReinvest: amountToReinvest,
                amountToQueue: userWithdrawalAmount,
                rewardsAmount: accumulatedRewards
            });
            vm.prank(actors.ops.WITHDRAWAL_MANAGER);
            stakingNodesManager.processPrincipalWithdrawals({
                actions: _actions
            });
        }

        {
            // Calculate fee for accumulated rewards
            uint256 feesBasisPoints = rewardsDistributor.feesBasisPoints();
            uint256 _BASIS_POINTS_DENOMINATOR = 10_000; // Assuming this is the denominator used in RewardsDistributor
            uint256 fees = Math.mulDiv(feesBasisPoints, accumulatedRewards, _BASIS_POINTS_DENOMINATOR);
            
            // Fees on accumulated rewards are substracted from the totalAssets and set to feeReceiver
            state.totalAssetsBefore -= fees;
            // The Balance of the stakingNode decreases by the total amount withdrawn
            state.stakingNodeBalancesBefore[nodeId] -= (amountToReinvest + userWithdrawalAmount + accumulatedRewards);
        }

        runSystemStateInvariants(state.totalAssetsBefore, state.totalSupplyBefore, state.stakingNodeBalancesBefore);

        // Calculate user ynETH amount to redeem
        uint256 userYnETHToRedeem = yneth.previewDeposit(userWithdrawalAmount);
        
        // Ensure user has enough ynETH balance
        require(yneth.balanceOf(user) >= userYnETHToRedeem, "User doesn't have enough ynETH balance");

        vm.startPrank(user);
        yneth.approve(address(ynETHWithdrawalQueueManager), userYnETHToRedeem);
        uint256 _tokenId = ynETHWithdrawalQueueManager.requestWithdrawal(userYnETHToRedeem);
        vm.stopPrank();

        vm.prank(actors.ops.REQUEST_FINALIZER);
        uint256 finalizationId = ynETHWithdrawalQueueManager.finalizeRequestsUpToIndex(_tokenId + 1);

        uint256 userBalanceBefore = user.balance;
        vm.prank(user);

        ynETHWithdrawalQueueManager.claimWithdrawal(
            IWithdrawalQueueManager.WithdrawalClaim({
                finalizationId: finalizationId,
                tokenId: _tokenId,
                receiver: user
            })
        );
        uint256 userBalanceAfter = user.balance;
        uint256 actualWithdrawnAmount = userBalanceAfter - userBalanceBefore;
        // Calculate expected withdrawal amount after fee
        uint256 withdrawalFee = ynETHWithdrawalQueueManager.withdrawalFee();
        uint256 expectedWithdrawnAmount = userWithdrawalAmount - (userWithdrawalAmount * withdrawalFee / ynETHWithdrawalQueueManager.FEE_PRECISION());
        
        assertApproxEqAbs(actualWithdrawnAmount, expectedWithdrawnAmount, 1e9, "User did not receive expected ETH amount after fee");
    }
}

contract WithdrawalsWithQueuedBeforeELIP002SlashingUpgradeTest is WithdrawalsScenarioTestBase {

    address public user = vm.addr(420);

    uint256 public amount;
    uint40[] validatorIndices;
    uint256 public nodeId;
    IStakingNode stakingNodeInstance;
    // caching the block timestamp because assignContracts called in setUp will set block.timestamp to GENESIS_TIMESTAMP while creating beacon chain mock
    uint256 setUpBlockTimestamp;

    function setUp() public override {
        setUpBlockTimestamp = block.timestamp;
        super.assignContracts();
        nodeId = stakingNodesManager.nodesLength();
    }

     function registerVerifiedValidatorsAtSpecificNode(
        uint256 totalDepositAmountInNewNode, uint256 stakingNodeId
    ) internal returns (uint40[] memory _validatorIndices) {

        amount = totalDepositAmountInNewNode;
        // deposit entire amount
        {
            vm.deal(user, amount);
            vm.prank(user);
            yneth.depositETH{value: amount}(user);
        }

        // Process rewards
        rewardsDistributor.processRewards();


        // Calculate validator count based on amount
        uint256 validatorCount = amount / 32 ether;

        // create and register validators validator
        {
            // Create an array of nodeIds with length equal to validatorCount
            uint256[] memory nodeIds = new uint256[](validatorCount);
            for (uint256 i = 0; i < validatorCount; i++) {
                nodeIds[i] = stakingNodeId;
            }

            // Call createValidators with the nodeIds array and validatorCount
            _validatorIndices = createValidators(nodeIds, 1);

            beaconChain.advanceEpoch_NoRewards();

            registerValidators(nodeIds);
        }

        // verify withdrawal credentials
        {

            CredentialProofs memory _proofs = beaconChain.getCredentialProofs(_validatorIndices);
            vm.startPrank(actors.ops.STAKING_NODES_OPERATOR);
            IPod(address(stakingNodesManager.nodes(stakingNodeId))).verifyWithdrawalCredentials({
                beaconTimestamp: _proofs.beaconTimestamp,
                stateRootProof: _proofs.stateRootProof,
                validatorIndices: _validatorIndices,
                validatorFieldsProofs: _proofs.validatorFieldsProofs,
                validatorFields: _proofs.validatorFields
            });
            vm.stopPrank();
        }
    }

     function startAndVerifyCheckpoint(uint256 _nodeId) internal {
        // start checkpoint
        {
            vm.startPrank(actors.ops.STAKING_NODES_OPERATOR);
            stakingNodesManager.nodes(_nodeId).startCheckpoint(true);
            vm.stopPrank();
        }

        // verify checkpoints
        {
            IStakingNode _node = stakingNodesManager.nodes(_nodeId);
            CheckpointProofs memory _cpProofs = beaconChain.getCheckpointProofs(validatorIndices, _node.eigenPod().currentCheckpointTimestamp());
            IPod(address(_node.eigenPod())).verifyCheckpointProofs({
                balanceContainerProof: _cpProofs.balanceContainerProof,
                proofs: _cpProofs.balanceProofs
            });
        }
    }
}