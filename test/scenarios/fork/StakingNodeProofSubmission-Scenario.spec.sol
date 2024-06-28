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
import "forge-std/console.sol";


contract StakingNodeTestBase is ScenarioBaseTest, ProofParsingV1 {

    struct ValidatorProofs {
        BeaconChainProofs.StateRootProof stateRootProof;
        uint40[] validatorIndices;
        bytes[] withdrawalCredentialProofs;
        bytes[] validatorFieldsProofs;
        bytes32[][] validatorFields;
    }

    struct ValidatorWithdrawalProofParams {
        BeaconChainProofs.StateRootProof stateRootProof;
        bytes32[][] validatorFields;
        bytes[] validatorFieldsProofs;
        bytes32[][] withdrawalFields;
        BeaconChainProofs.WithdrawalProof[] withdrawalProofs;
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


        //bytes memory validatorFieldsProof = abi.encodePacked(getValidatorProof());
        // Set beacon state root, validatorIndex
        validatorProofs.stateRootProof.beaconStateRoot = getBeaconStateRoot();
        validatorProofs.stateRootProof.proof = getStateRootProof();
        validatorProofs.validatorIndices[0] = uint40(getValidatorIndex());
        validatorProofs.withdrawalCredentialProofs[0] = abi.encodePacked(getWithdrawalCredentialProof()); // Validator fields are proven here
        //validatorProofs.validatorFieldsProofs[0] = validatorFieldsProof;
        validatorProofs.validatorFields[0] = getValidatorFields();

        return validatorProofs;
    }

    function getValidatorWithdrawalProofParams() public returns (ValidatorWithdrawalProofParams memory) {
        ValidatorWithdrawalProofParams memory params;

        params.validatorFieldsProofs = new bytes[](1);
        params.validatorFields = new bytes32[][](1);
        params.withdrawalFields = new bytes32[][](1);
        params.withdrawalProofs =  new BeaconChainProofs.WithdrawalProof[](1);

        params.stateRootProof.beaconStateRoot = getBeaconStateRoot();
        params.stateRootProof.proof = getStateRootProof();
        params.validatorFields[0] = getValidatorFields();
        params.withdrawalFields[0] = getWithdrawalFields();
        params.withdrawalProofs[0] = _getWithdrawalProof();
        params.validatorFieldsProofs[0] = abi.encodePacked(getValidatorProof());

        return params;
    }

    function bytes32ToData(bytes32 data) public pure returns (address) {
        return address(uint160(uint256(data)));
    }

    function getWithdrawalAddress() public returns (address) {
        bytes32[] memory validatorFields = getValidatorFields();
        return bytes32ToData(validatorFields[1]);
    }


    function _getWithdrawalProof() internal returns (BeaconChainProofs.WithdrawalProof memory) {
        {
            bytes32 blockRoot = getBlockRoot();
            bytes32 slotRoot = getSlotRoot();
            bytes32 timestampRoot = getTimestampRoot();
            bytes32 executionPayloadRoot = getExecutionPayloadRoot();

            return
                BeaconChainProofs.WithdrawalProof(
                    abi.encodePacked(getWithdrawalProofDeneb()),
                    abi.encodePacked(getSlotProof()),
                    abi.encodePacked(getExecutionPayloadProof()),
                    abi.encodePacked(getTimestampProofDeneb()),
                    abi.encodePacked(getHistoricalSummaryProof()),
                    uint64(getBlockRootIndex()),
                    uint64(getHistoricalSummaryIndex()),
                    uint64(getWithdrawalIndex()),
                    blockRoot,
                    slotRoot,
                    timestampRoot,
                    executionPayloadRoot
                );
        }
    }

}


contract StakingNodeVerifyWithdrawalCredentialsOnHolesky is StakingNodeTestBase {

    using stdStorage for StdStorage;
    using BytesLib for bytes;

    address newMockStakingNodeImplementation;


    function testVerifyWithdrawalCredentialsSuccesfully_32ETH_Holesky() public {
        if (block.chainid != 17000) {
            return; // Skip test if not on Holesky
        }
        // Validator proven:
        // 1692941
        // 0xb7ea207e2cad7076c176af040a79ce3c9779e02f94e62548fb9856c8e1c9720398f88fd59e89e7cfe0518d43f299ea13
        uint256 nodeId = 0;
        verifyWithdrawalCredentialsSuccesfullyForProofFile(nodeId, "test/data/holesky_wc_proof_1915130.json");
    }

    function testFail_VerifyWithdrawalCredentials_32ETH_Twice_Holesky() public {
        if (block.chainid != 17000) {
            return; // Skip test if not on Holesky
        }
        // Validator proven:
        // 1692941
        // 0xb7ea207e2cad7076c176af040a79ce3c9779e02f94e62548fb9856c8e1c9720398f88fd59e89e7cfe0518d43f299ea13
        uint256 nodeId = 0;
        verifyWithdrawalCredentialsSuccesfullyForProofFile(nodeId, "test/data/holesky_wc_proof_1915130.json");

        vm.expectRevert("EigenPod.verifyCorrectWithdrawalCredentials: Validator must be inactive to prove withdrawal credentials");
        verifyWithdrawalCredentialsSuccesfullyForProofFile(nodeId, "test/data/holesky_wc_proof_1915130.json");
    }

    function testVerifyWithdrawalCredentials_PartialRewards_Holesky() public {

        uint256 nodeId = 2;
        // Validator proven
        // 1692473
        // 0x80500c11e542327646b5a08a952288241b11f6ea0c185f41afa79dad03b21defe213054ab71770651f3f293dd2e4b9c7
        verifyAndProcessWithdrawalSuccesfullyForProofFile(nodeId, "test/data/holesky_withdrawal_proof_1972138.json");
    }


    function testVerifyWithdrawalCredentialsSuccesfully_32ETH_With_verifyAndProcessWithdrawal_32ETH_Holesky() public {

        if (block.chainid != 17000) {
            return; // Skip test if not on Holesky
        }
        /*
            This validator  has been activated and withdrawn.
            It has NOT been proved VerifyWithdrawalCredentials yet.
            It has  NOT been proven verifyAndProcessWithdrawal yet for any of the withdrawals.
        */

       // Validator proven:
        // 1692468
        // 0xa5d87f6440fbac9a0f40f192f618e24512572c5b54dbdb51960772ea9b3e9dc985a5703f2e837da9bc08c28e4f633984
        uint256 nodeId = 2;
        verifyWithdrawalCredentialsSuccesfullyForProofFile(nodeId, "test/data/holesky_wc_proof_1916455.json");

        // verify Full Withdrawal
        verifyAndProcessWithdrawalSuccesfullyForProofFile(nodeId, "test/data/holesky_withdrawal_proof_1945219.json");
    }

    function testVerifyWithdrawalCredentialsSuccesfully_32ETH_With_verifyAndProcessWithdrawal_RewardsPartial_Holesky() public {

        if (block.chainid != 17000) {
            return; // Skip test if not on Holesky
        }
        /*
            This validator  has been activated and withdrawn.
            It has NOT been proved VerifyWithdrawalCredentials yet.
            It has  NOT been proven verifyAndProcessWithdrawal yet for any of the withdrawals.
        */

       // Validator proven:
        // 1692468
        // 0xa5d87f6440fbac9a0f40f192f618e24512572c5b54dbdb51960772ea9b3e9dc985a5703f2e837da9bc08c28e4f633984
        uint256 nodeId = 2;
        verifyWithdrawalCredentialsSuccesfullyForProofFile(nodeId, "test/data/holesky_wc_proof_1916455.json");

        // verify Partial Withdrawal
        verifyAndProcessWithdrawalSuccesfullyForProofFile(nodeId, "test/data/holesky_withdrawal_proof_1945219_2.json");
    }

    function testVerifyWithdrawalCredentialsSuccesfully_32ETH_With_verifyAndProcessWithdrawal_32ETH_and_RewardsPartial_Holesky() public {

        if (block.chainid != 17000) {
            return; // Skip test if not on Holesky
        }
        /*
            This validator  has been activated and withdrawn.
            It has NOT been proved VerifyWithdrawalCredentials yet.
            It has  NOT been proven verifyAndProcessWithdrawal yet for any of the withdrawals.
        */

       // Validator proven:
        // 1692468
        // 0xa5d87f6440fbac9a0f40f192f618e24512572c5b54dbdb51960772ea9b3e9dc985a5703f2e837da9bc08c28e4f633984
        uint256 nodeId = 2;
        verifyWithdrawalCredentialsSuccesfullyForProofFile(nodeId, "test/data/holesky_wc_proof_1916455.json");

        // verify Full Withdrawal
        verifyAndProcessWithdrawalSuccesfullyForProofFile(nodeId, "test/data/holesky_withdrawal_proof_1945219.json");

        // verify Partial Withdrawal
        verifyAndProcessWithdrawalSuccesfullyForProofFile(nodeId, "test/data/holesky_withdrawal_proof_1945219_2.json");
    }

    function testVerifyWithdrawalCredentialsSuccesfully_32ETH_With_verifyAndProcessWithdrawal_RewardsPartial_and_32ETH_Holesky() public {

        if (block.chainid != 17000) {
            return; // Skip test if not on Holesky
        }
        /*
            This validator  has been activated and withdrawn.
            It has NOT been proved VerifyWithdrawalCredentials yet.
            It has  NOT been proven verifyAndProcessWithdrawal yet for any of the withdrawals.
        */

       // Validator proven:
        // 1692468
        // 0xa5d87f6440fbac9a0f40f192f618e24512572c5b54dbdb51960772ea9b3e9dc985a5703f2e837da9bc08c28e4f633984
        uint256 nodeId = 2;
        verifyWithdrawalCredentialsSuccesfullyForProofFile(nodeId, "test/data/holesky_wc_proof_1916455.json");

        // verify Partial Withdrawal
        verifyAndProcessWithdrawalSuccesfullyForProofFile(nodeId, "test/data/holesky_withdrawal_proof_1945219_2.json");

        // verify Full Withdrawal
        verifyAndProcessWithdrawalSuccesfullyForProofFile(nodeId, "test/data/holesky_withdrawal_proof_1945219.json");
    }

    function testFail_verifyAndProcessWithdrawal_32ETH_Without_VerifyWithdrawalCredentials_Holesky() public {

        if (block.chainid != 17000) {
            return; // Skip test if not on Holesky
        }
        /*
            This validator  has been activated and withdrawn.
            It has NOT been proved VerifyWithdrawalCredentials yet.
            It has  NOT been proven verifyAndProcessWithdrawal yet for any of the withdrawals.
        */

       // Validator proven:
        // 1692468
        // 0xa5d87f6440fbac9a0f40f192f618e24512572c5b54dbdb51960772ea9b3e9dc985a5703f2e837da9bc08c28e4f633984
        uint256 nodeId = 2;

        // Attempt verify Full Withdrawal without having run verifyWithdrawalCredentials
        vm.expectRevert("EigenPod._verifyAndProcessWithdrawal: Validator never proven to have withdrawal credentials pointed to this contract");
        verifyAndProcessWithdrawalSuccesfullyForProofFile(nodeId, "test/data/holesky_withdrawal_proof_1945219.json");
    }

    function testFail_verifyAndProcessWithdrawal_RewardsPartial_Twice_Holesky() public {

        if (block.chainid != 17000) {
            return; // Skip test if not on Holesky
        }
        /*
            This validator  has been activated and withdrawn.
            It has NOT been proved VerifyWithdrawalCredentials yet.
            It has  NOT been proven verifyAndProcessWithdrawal yet for any of the withdrawals.
        */

       // Validator proven:
        // 1692468
        // 0xa5d87f6440fbac9a0f40f192f618e24512572c5b54dbdb51960772ea9b3e9dc985a5703f2e837da9bc08c28e4f633984
        uint256 nodeId = 2;
        verifyWithdrawalCredentialsSuccesfullyForProofFile(nodeId, "test/data/holesky_wc_proof_1916455.json");

        // verify Partial Withdrawal
        verifyAndProcessWithdrawalSuccesfullyForProofFile(nodeId, "test/data/holesky_withdrawal_proof_1945219_2.json");

        // verify Partial Withdrawal
        vm.expectRevert();
        verifyAndProcessWithdrawalSuccesfullyForProofFile(nodeId, "test/data/holesky_withdrawal_proof_1945219_2.json");
    }

    function test_queueWithdrawals_32ETH_Holesky() public {

        // WIP

        if (block.chainid != 17000) {
            return; // Skip test if not on Holesky
        }
        /*
            This validator  has been activated and withdrawn.
            It has NOT been proved VerifyWithdrawalCredentials yet.
            It has  NOT been proven verifyAndProcessWithdrawal yet for any of the withdrawals.
        */

       // Validator proven:
        // 1692468
        // 0xa5d87f6440fbac9a0f40f192f618e24512572c5b54dbdb51960772ea9b3e9dc985a5703f2e837da9bc08c28e4f633984
        uint256 nodeId = 2;
        verifyWithdrawalCredentialsSuccesfullyForProofFile(nodeId, "test/data/holesky_wc_proof_1916455.json");

        uint256 withdrawalAmount = 32 ether;

        IStakingNode stakingNodeInstance = stakingNodesManager.nodes(nodeId);

        uint256 unverifiedStakedETHBefore = stakingNodeInstance.getUnverifiedStakedETH();
        uint256 queuedSharesBefore = stakingNodeInstance.getQueuedSharesAmount();
        int256 sharesBefore = eigenPodManager.podOwnerShares(address(stakingNodeInstance));

        bytes32[] memory fullWithdrawalRoots = stakingNodeInstance.queueWithdrawals(withdrawalAmount);

        assertEq(fullWithdrawalRoots.length, 1, "Expected exactly one full withdrawal root");

        uint256 unverifiedStakedETHAfter = stakingNodeInstance.getUnverifiedStakedETH();
        uint256 queuedSharesAfter = stakingNodeInstance.getQueuedSharesAmount();
        int256 sharesAfter = eigenPodManager.podOwnerShares(address(stakingNodeInstance));

        assertEq(unverifiedStakedETHBefore, unverifiedStakedETHAfter - withdrawalAmount);
        assertEq(queuedSharesBefore + withdrawalAmount, queuedSharesAfter);
        assertEq(sharesBefore - sharesAfter, int256(withdrawalAmount), "Staking node shares do not match expected shares");

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
        // TODO: fixme
        middlewareTimesIndexes[0] = 0;

        stakingNodeInstance.completeQueuedWithdrawals(withdrawals, middlewareTimesIndexes);
    }

    function skiptestVerifyAndProcessWithdrawalSuccesfully_32ETH_Holesky() public {

        if (block.chainid != 17000) {
            return; // Skip test if not on Holesky
        }
         /*
            This validator  has been activated and withdrawn.
            It has been proved VerifyWithdrawalCredentials already.
            It has NOT been proven verifyAndProcessWithdrawal yet.
        */

       // Validator proven:
        // 1692434 
        // 0xa876a689610dfa8cda994afffc47fbff35b4fed1d417487ba098b3733241147639fef98e722ed54cb74676c4a8ebfcad
        uint256 nodeId = 2;
        verifyAndProcessWithdrawalSuccesfullyForProofFile(nodeId, "test/data/holesky_withdrawal_proof_1915130.json");
    }


    function verifyWithdrawalCredentialsSuccesfullyForProofFile(uint256 nodeId, string memory path) public {

        setJSON(path);

        IStakingNode stakingNodeInstance = stakingNodesManager.nodes(nodeId);

        uint64 oracleTimestamp = uint64(block.timestamp);
        MockEigenLayerBeaconOracle mockBeaconOracle = new MockEigenLayerBeaconOracle();

        address eigenPodManagerOwner = OwnableUpgradeable(address(eigenPodManager)).owner();
        vm.prank(eigenPodManagerOwner);
        eigenPodManager.updateBeaconChainOracle(IBeaconChainOracle(address(mockBeaconOracle)));
        
        // set existing EigenPod to be the EigenPod of the StakingNode for the 
        // purpose of testing verifyWithdrawalCredentials
        address eigenPodAddress = getWithdrawalAddress();

        assertEq(eigenPodAddress, address(stakingNodeInstance.eigenPod()), "EigenPod address does not match the expected address");


        ValidatorProofs memory validatorProofs = getWithdrawalCredentialParams();
        bytes32 validatorPubkeyHash = BeaconChainProofs.getPubkeyHash(validatorProofs.validatorFields[0]);


        bytes32 latestBlockRoot = _getLatestBlockRoot();
        mockBeaconOracle.setOracleBlockRootAtTimestamp(latestBlockRoot);

        int256 sharesBefore = eigenPodManager.podOwnerShares(address(stakingNodeInstance));

        vm.prank(actors.ops.STAKING_NODES_OPERATOR);
        stakingNodeInstance.verifyWithdrawalCredentials(
            oracleTimestamp,
            validatorProofs.stateRootProof,
            validatorProofs.validatorIndices,
            validatorProofs.withdrawalCredentialProofs,
            validatorProofs.validatorFields
        );
        
        int256 expectedSharesIncrease = int256(uint256(BeaconChainProofs.getEffectiveBalanceGwei(validatorProofs.validatorFields[0])) * 1e9);
        int256 sharesAfter = eigenPodManager.podOwnerShares(address(stakingNodeInstance));
        assertEq(sharesAfter - sharesBefore, expectedSharesIncrease, "Staking node shares do not match expected shares");
    }

    function verifyAndProcessWithdrawalSuccesfullyForProofFile(uint256 nodeId, string memory path) public {

        setJSON(path);

        IStakingNode stakingNodeInstance = stakingNodesManager.nodes(nodeId);

        uint64 oracleTimestamp = uint64(block.timestamp);
        MockEigenLayerBeaconOracle mockBeaconOracle = new MockEigenLayerBeaconOracle();

        address eigenPodManagerOwner = OwnableUpgradeable(address(eigenPodManager)).owner();
        vm.prank(eigenPodManagerOwner);
        eigenPodManager.updateBeaconChainOracle(IBeaconChainOracle(address(mockBeaconOracle)));
        bytes32 latestBlockRoot = _getLatestBlockRoot();
        mockBeaconOracle.setOracleBlockRootAtTimestamp(latestBlockRoot);

        ValidatorWithdrawalProofParams memory params = getValidatorWithdrawalProofParams();

        BeaconChainProofs.WithdrawalProof memory withdrawalProof = params.withdrawalProofs[0];   


        {
            // TODO: remove this block when completed
            uint256 historicalBlockHeaderIndex = (BeaconChainProofs.HISTORICAL_SUMMARIES_INDEX <<
                    ((BeaconChainProofs.HISTORICAL_SUMMARIES_TREE_HEIGHT + 1) + 1 + (BeaconChainProofs.BLOCK_ROOTS_TREE_HEIGHT))) |
                    (uint256(withdrawalProof.historicalSummaryIndex) << (1 + (BeaconChainProofs.BLOCK_ROOTS_TREE_HEIGHT))) |
                    (BeaconChainProofs.BLOCK_SUMMARY_ROOT_INDEX << (BeaconChainProofs.BLOCK_ROOTS_TREE_HEIGHT)) |
                    uint256(withdrawalProof.blockRootIndex);

            console.log("Blokc Root Index: ", withdrawalProof.blockRootIndex);
            console.log("Historical Summary Block Root Proof:", vm.toString(withdrawalProof.historicalSummaryBlockRootProof));
            console.log("Beacon State Root:",  vm.toString(params.stateRootProof.beaconStateRoot));
            console.log("Block Root:", vm.toString(withdrawalProof.blockRoot));
            console.log("Historical Block Header Index:", historicalBlockHeaderIndex);

            require(
                    Merkle.verifyInclusionSha256({
                        proof: withdrawalProof.historicalSummaryBlockRootProof,
                        root: params.stateRootProof.beaconStateRoot,
                        leaf: withdrawalProof.blockRoot,
                        index: historicalBlockHeaderIndex
                    }),
                    "Merkle.verifyInclusionSha256 BeaconChainProofs.verifyWithdrawal: Invalid historicalsummary merkle proof"
                );   
        }
  

        // Save state for checks; deal EigenPod withdrawal router balance
        // uint64 withdrawalAmountGwei = Endian.fromLittleEndianUint64(
        //     withdrawalFields[0][BeaconChainProofs.WITHDRAWAL_VALIDATOR_AMOUNT_INDEX]
        // );
        // uint64 leftOverBalanceWEI = uint64(withdrawalAmountGwei - MAX_RESTAKED_BALANCE_GWEI_PER_VALIDATOR) * 1e9;
        // cheats.deal(address(eigenPod), leftOverBalanceWEI);
        // int256 initialShares = eigenPodManager.podOwnerShares(podOwner);

        // Withdraw
        vm.prank(actors.ops.STAKING_NODES_OPERATOR);
        stakingNodeInstance.verifyAndProcessWithdrawals(
            oracleTimestamp,
            params.stateRootProof,
            params.withdrawalProofs,
            params.validatorFieldsProofs,
            params.validatorFields,
            params.withdrawalFields
        );

    }
}
