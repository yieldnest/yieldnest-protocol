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



    function test_UserWithdrawal_1ETH_Holesky() public {

        if (block.chainid != 17000) {
            return; // Skip test if not on Holesky
        }
        /*
            This validator has been activated and withdrawn.
            It has NOT been proved VerifyWithdrawalCredentials yet.
            It has  NOT been proven verifyAndProcessWithdrawal yet for any of the withdrawals.
        */

        uint256 nodeId = 2;
        uint256 withdrawalAmount = 32 ether;
        IStakingNode stakingNodeInstance = stakingNodesManager.nodes(nodeId);

        {
            // verifyWithdrawalCredentials
            uint256 unverifiedStakedETHBefore = stakingNodeInstance.getUnverifiedStakedETH();

            // Validator proven:
            // 1692468
            // 0xa5d87f6440fbac9a0f40f192f618e24512572c5b54dbdb51960772ea9b3e9dc985a5703f2e837da9bc08c28e4f633984
            setupForVerifyWithdrawalCredentials(nodeId, "test/data/holesky_wc_proof_1916455.json");

            ValidatorProofs memory validatorProofs = getWithdrawalCredentialParams();
            vm.prank(actors.ops.STAKING_NODES_OPERATOR);
            stakingNodeInstance.verifyWithdrawalCredentials(
                 uint64(block.timestamp),
                validatorProofs.stateRootProof,
                validatorProofs.validatorIndices,
                validatorProofs.withdrawalCredentialProofs,
                validatorProofs.validatorFields
            );

            uint256 unverifiedStakedETHAfter = stakingNodeInstance.getUnverifiedStakedETH();
            assertEq(unverifiedStakedETHBefore - unverifiedStakedETHAfter, withdrawalAmount, "Unverified staked ETH after withdrawal does not match expected amount");
        }

        bytes32[] memory fullWithdrawalRoots;
        {
            // queueWithdrawals
            uint256 queuedSharesBefore = stakingNodeInstance.getQueuedSharesAmount();
            int256 sharesBefore = eigenPodManager.podOwnerShares(address(stakingNodeInstance));

            vm.prank(actors.ops.STAKING_NODES_OPERATOR);
            fullWithdrawalRoots = stakingNodeInstance.queueWithdrawals(withdrawalAmount);

            console.log("fullWithdrawalRoots.length", fullWithdrawalRoots.length);

            assertEq(fullWithdrawalRoots.length, 1, "Expected exactly one full withdrawal root");

            uint256 queuedSharesAfter = stakingNodeInstance.getQueuedSharesAmount();
            int256 sharesAfter = eigenPodManager.podOwnerShares(address(stakingNodeInstance));

            assertEq(queuedSharesBefore + withdrawalAmount, queuedSharesAfter, "Queued shares after withdrawal do not match the expected total.");
            assertEq(sharesBefore - sharesAfter, int256(withdrawalAmount), "Staking node shares do not match expected shares");
        }


        uint256 nonce = delegationManager.cumulativeWithdrawalsQueued(address(stakingNodeInstance)) - 1;

        IStrategy[] memory strategies = new IStrategy[](1);
        strategies[0] = beaconChainETHStrategy;

        uint256[] memory shares = new uint256[](1);
        shares[0] = withdrawalAmount;
        IDelegationManager.Withdrawal memory withdrawal = IDelegationManager.Withdrawal({
            staker: address(stakingNodeInstance),
            delegatedTo: address(0),
            withdrawer: address(stakingNodeInstance),
            nonce: nonce,
            startBlock: uint32(block.number),
            strategies: strategies,
            shares: shares
        });

        bytes32 fullWithdrawalRoot = delegationManager.calculateWithdrawalRoot(withdrawal);
        assertEq(fullWithdrawalRoot, fullWithdrawalRoots[0], "fullWithdrawalRoot should match the first in the array");

        IDelegationManager.Withdrawal[] memory withdrawals = new IDelegationManager.Withdrawal[](1);
        withdrawals[0] = withdrawal;

        uint256[] memory middlewareTimesIndexes = new uint256[](1);
        middlewareTimesIndexes[0] = 0; // value is not used, as per EigenLayer docs

        vm.roll(block.number + delegationManager.minWithdrawalDelayBlocks() + 1);

        uint256 balanceBefore = address(stakingNodeInstance).balance;
        uint256 withdrawnValidatorPrincipalBefore = stakingNodeInstance.getWithdrawnValidatorPrincipal();

        vm.prank(actors.ops.STAKING_NODES_OPERATOR);
        stakingNodeInstance.completeQueuedWithdrawals(withdrawals, middlewareTimesIndexes);

        uint256 balanceAfter = address(stakingNodeInstance).balance;
        uint256 withdrawnValidatorPrincipalAfter = stakingNodeInstance.getWithdrawnValidatorPrincipal();

        assertEq(balanceAfter - balanceBefore, withdrawalAmount, "ETH balance after withdrawal does not match expected amount");
        assertEq(withdrawnValidatorPrincipalAfter - withdrawnValidatorPrincipalBefore, withdrawalAmount, "Withdrawn validator principal after withdrawal does not match expected amount");
    }
}