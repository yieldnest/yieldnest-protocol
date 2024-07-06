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
import {IDelayedWithdrawalRouter} from "lib/eigenlayer-contracts/src/contracts/interfaces/IDelayedWithdrawalRouter.sol";
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
import { ONE_GWEI } from "src/Constants.sol";

contract StakingNodeRewardsCollectionOnHolesky is StakingNodeTestBase {

    using BeaconChainProofs for *;

    struct TestState {
        uint256 nodeId;
        uint256 withdrawalAmount;
        IStakingNode stakingNodeInstance;
        uint256 totalAssetsBefore;
        uint256 totalSupplyBefore;
        uint256[] stakingNodeBalancesBefore;
        uint256 stakingNodeETHBalance;
        uint256 previousYnETHRedemptionAssetsVaultBalance;
        uint256 previousYnETHBalance;
        uint256 totalDelayedWitdrawalsBefore;
    }

    function test_processDelayedWithdrawals_From_PartialRewards_Holesky() public {

        if (block.chainid != 17000) {
            return; // Skip test if not on Holesky
        }

        TestState memory state = TestState({
            nodeId: 2,
            withdrawalAmount: 32 ether,
            stakingNodeInstance: stakingNodesManager.nodes(2),
            totalAssetsBefore: yneth.totalAssets(),
            totalSupplyBefore: yneth.totalSupply(),
            stakingNodeBalancesBefore: getAllStakingNodeBalances(),
            stakingNodeETHBalance: address(stakingNodesManager.nodes(2)).balance,
            previousYnETHRedemptionAssetsVaultBalance: ynETHRedemptionAssetsVaultInstance.availableRedemptionAssets(),
            previousYnETHBalance: address(yneth).balance,
            totalDelayedWitdrawalsBefore: sumTotalDelayedWithdrawalsForUser(address(stakingNodesManager.nodes(2)))
        });

        uint256 partialRewardsAmount;

        {
            // Validator proven
            // 1692473
            // 0x80500c11e542327646b5a08a952288241b11f6ea0c185f41afa79dad03b21defe213054ab71770651f3f293dd2e4b9c7

            setupForVerifyAndProcessWithdrawals(state.nodeId, "test/data/holesky_withdrawal_proof_1972138.json");
            uint64 oracleTimestamp = uint64(block.timestamp);
            ValidatorWithdrawalProofParams memory params = getValidatorWithdrawalProofParams();

            vm.prank(actors.ops.STAKING_NODES_OPERATOR);
            state.stakingNodeInstance.verifyAndProcessWithdrawals(
                oracleTimestamp,
                params.stateRootProof,
                params.withdrawalProofs,
                params.validatorFieldsProofs,
                params.validatorFields,
                params.withdrawalFields
            );
            partialRewardsAmount = params.withdrawalFields[0].getWithdrawalAmountGwei() * ONE_GWEI;
        }

        assertEq(
            sumTotalDelayedWithdrawalsForUser(address(state.stakingNodeInstance)),
            state.totalDelayedWitdrawalsBefore + partialRewardsAmount,
            "Total delayed withdrawals did not increase correctly by the partial rewards amount"
        );

        runSystemStateInvariants(state.totalAssetsBefore, state.totalSupplyBefore, state.stakingNodeBalancesBefore);

        vm.roll(block.number + delayedWithdrawalRouter.withdrawalDelayBlocks() + 1);

        delayedWithdrawalRouter.claimDelayedWithdrawals(address(state.stakingNodeInstance), type(uint256).max);

        assertEq(
            address(state.stakingNodeInstance).balance,
            state.stakingNodeETHBalance + state.totalDelayedWitdrawalsBefore + partialRewardsAmount,
            "Staking node ETH balance did not increase correctly by the expected amount"
        );

        {
            uint256 balanceBeforeClaim = address(consensusLayerReceiver).balance;
            vm.prank(actors.ops.STAKING_NODES_OPERATOR);
            state.stakingNodeInstance.processDelayedWithdrawals();
            uint256 balanceAfterClaim = address(consensusLayerReceiver).balance;
            uint256 rewardsAmount = balanceAfterClaim - balanceBeforeClaim;

            assertEq(
                rewardsAmount,
                state.totalDelayedWitdrawalsBefore + partialRewardsAmount,
                "Rewards amount does not match the partial rewards amount"
            );
        }

        runSystemStateInvariants(state.totalAssetsBefore, state.totalSupplyBefore, state.stakingNodeBalancesBefore);
    }
}