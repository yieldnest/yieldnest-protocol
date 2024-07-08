// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;
import {StakingNodesManager} from "src/StakingNodesManager.sol";
import {OwnableUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {ynETH} from "src/ynETH.sol";
import {RewardsReceiver} from "src/RewardsReceiver.sol";
import {RewardsDistributor} from "src/RewardsDistributor.sol";
import {ProxyAdmin} from "lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {IRewardsDistributor} from "src/interfaces/IRewardsDistributor.sol";
import {IStakingNodesManager} from "src/interfaces/IStakingNodesManager.sol";
import {IStakingNode} from "src/interfaces/IStakingNodesManager.sol";
import {IBeaconChainOracle} from "lib/eigenlayer-contracts/src/contracts/interfaces/IBeaconChainOracle.sol";
import {IStrategy} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IDelegationManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {TransparentUpgradeableProxy} from "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ITransparentUpgradeableProxy} from "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ScenarioBaseTest} from "test/scenarios/ScenarioBaseTest.sol";
import { Invariants } from "test/scenarios/Invariants.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol"; 
import {BytesLib} from "lib/eigenlayer-contracts/src/contracts/libraries/BytesLib.sol";
import { MockEigenLayerBeaconOracle } from "test/mocks/MockEigenLayerBeaconOracle.sol";

import {UpgradeableBeacon} from "lib/openzeppelin-contracts/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {TestStakingNodesManagerV2} from "test/mocks/TestStakingNodesManagerV2.sol";
import {TestStakingNodeV2} from "test/mocks/TestStakingNodeV2.sol";

import {BeaconChainProofs} from "lib/eigenlayer-contracts/src/contracts/libraries/BeaconChainProofs.sol";
import {Merkle} from "lib/eigenlayer-contracts/src/contracts/libraries/Merkle.sol";
import { ProofParsingV1 } from "test/eigenlayer-utils/ProofParsingV1.sol";
import {Utils} from "script/Utils.sol";
import {beaconChainETHStrategy} from "src/Constants.sol";
import { StakingNodeTestBase } from "test/utils/StakingNodeTestBase.sol";
import {Vm} from "lib/forge-std/src/Vm.sol";

import "forge-std/console.sol";


contract ynETHUserWithdrawalScenarioOnHolesky is StakingNodeTestBase {
    using stdStorage for StdStorage;
    using BytesLib for bytes;


    struct TestState {
        uint256 nodeId;
        uint256 withdrawalAmount;
        IStakingNode stakingNodeInstance;
        uint256 totalAssetsBefore;
        uint256 totalSupplyBefore;
        uint256[] stakingNodeBalancesBefore;
        uint256 previousYnETHRedemptionAssetsVaultBalance;
        uint256 previousYnETHBalance;
    }

    function test_UserWithdrawal_1ETH_Holesky() public {

        if (block.chainid != 17000) {
            return; // Skip test if not on Holesky
        }

        // Withdrawing user configuration
        uint256 userRequestedAmountYnETH = 1 ether;
        address userAddress = address(0x12345678);
        address receivalAddress = address(0x987654321);
        vm.deal(userAddress, 100 ether); // Give the user some Ether to start with
        vm.prank(userAddress);
        yneth.depositETH{value: 10 ether}(userAddress); // User mints ynETH by depositing ETH

        TestState memory state = TestState({
            nodeId: 2,
            withdrawalAmount: 32 ether,
            stakingNodeInstance: stakingNodesManager.nodes(2),
            totalAssetsBefore: yneth.totalAssets(),
            totalSupplyBefore: yneth.totalSupply(),
            stakingNodeBalancesBefore: getAllStakingNodeBalances(),
            previousYnETHRedemptionAssetsVaultBalance: ynETHRedemptionAssetsVaultInstance.availableRedemptionAssets(),
            previousYnETHBalance: address(yneth).balance
        });

        {
            // verifyWithdrawalCredentials
            setupForVerifyWithdrawalCredentials(state.nodeId, "test/data/holesky_wc_proof_1916455.json");
            ValidatorProofs memory validatorProofs = getWithdrawalCredentialParams();
            vm.prank(actors.ops.STAKING_NODES_OPERATOR);
            state.stakingNodeInstance.verifyWithdrawalCredentials(
                uint64(block.timestamp),
                validatorProofs.stateRootProof,
                validatorProofs.validatorIndices,
                validatorProofs.withdrawalCredentialProofs,
                validatorProofs.validatorFields
            );
        }

        runSystemStateInvariants(state.totalAssetsBefore, state.totalSupplyBefore, state.stakingNodeBalancesBefore);
        
        vm.prank(actors.ops.STAKING_NODES_OPERATOR);
        state.stakingNodeInstance.queueWithdrawals(state.withdrawalAmount);

        runSystemStateInvariants(state.totalAssetsBefore, state.totalSupplyBefore, state.stakingNodeBalancesBefore);

        completeQueuedWithdrawals(state.stakingNodeInstance, state.withdrawalAmount);

        runSystemStateInvariants(state.totalAssetsBefore, state.totalSupplyBefore, state.stakingNodeBalancesBefore);

        uint256 ethEquivalent = yneth.previewRedeem(userRequestedAmountYnETH);

        uint256 tokenId;
        {
            uint256 ynETHBalanceBefore = yneth.balanceOf(userAddress);
            vm.prank(userAddress);
            yneth.approve(address(ynETHWithdrawalQueueManager), userRequestedAmountYnETH);
            vm.prank(userAddress);
            tokenId = ynETHWithdrawalQueueManager.requestWithdrawal(userRequestedAmountYnETH);
            uint256 ynETHBalanceAfter = yneth.balanceOf(userAddress);
            assertEq(ynETHBalanceBefore - ynETHBalanceAfter, userRequestedAmountYnETH, "ynETH balance after withdrawal request does not match expected amount");
        }

        runSystemStateInvariants(state.totalAssetsBefore, state.totalSupplyBefore, state.stakingNodeBalancesBefore);

        uint256 systemAmountToWithdraw = ethEquivalent * 4;
        uint256 amountToReinvest = ethEquivalent;
        uint256 amountToQueue = systemAmountToWithdraw - amountToReinvest;

        vm.prank(actors.ops.WITHDRAWAL_MANAGER);
        IStakingNodesManager.WithdrawalAction[] memory actions = new IStakingNodesManager.WithdrawalAction[](1);
        actions[0] = IStakingNodesManager.WithdrawalAction({
            nodeId: state.nodeId,
            amountToReinvest: amountToReinvest,
            amountToQueue: amountToQueue
        });
        stakingNodesManager.processPrincipalWithdrawals(actions);

        runSystemStateInvariants(
            state.totalAssetsBefore, 
            state.totalSupplyBefore, 
            state.stakingNodeBalancesBefore, 
            actions, 
            state.previousYnETHRedemptionAssetsVaultBalance, 
            state.previousYnETHBalance
        );

        // Advance time to simulate the delay required for withdrawals to be processed
        uint256 secondsToFinalization = ynETHWithdrawalQueueManager.secondsToFinalization();
        vm.warp(block.timestamp + secondsToFinalization + 1); // Adjust time as per the specific requirements of the scenario
        uint256 userEthBalanceBefore = receivalAddress.balance;
        uint256 ynETHRedemptionAssetsVaultBalanceBefore = ynETHRedemptionAssetsVaultInstance.availableRedemptionAssets();

        vm.prank(userAddress);
        ynETHWithdrawalQueueManager.claimWithdrawal(tokenId, receivalAddress);
        
        uint256 userEthBalanceAfter = receivalAddress.balance;

        uint256 feePercentage = ynETHWithdrawalQueueManager.withdrawalFee();
        uint256 feeAmount = (ethEquivalent * feePercentage) / ynETHWithdrawalQueueManager.FEE_PRECISION();
        uint256 expectedReceivedAmount = ethEquivalent - feeAmount;
        assertEq(userEthBalanceAfter - userEthBalanceBefore, expectedReceivedAmount, "ETH balance change does not match the expected ETH equivalent");

        uint256 ynETHRedemptionAssetsVaultBalanceAfter = ynETHRedemptionAssetsVaultInstance.availableRedemptionAssets();
        assertEq(
            ynETHRedemptionAssetsVaultBalanceBefore - ynETHRedemptionAssetsVaultBalanceAfter,
            ethEquivalent,
            "Difference in ynETH Redemption assets vault available assets does not match the expected ETH equivalent"
        );
    }
}