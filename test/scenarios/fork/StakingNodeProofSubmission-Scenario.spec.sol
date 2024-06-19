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
import { ProofParsingV1 } from "test/eigenlayer-utils/ProofParsingV1.sol";
import {Utils} from "script/Utils.sol";

contract StakingNodeTestBase is ScenarioBaseTest, ProofParsingV1 {

    struct ValidatorProofs {
        BeaconChainProofs.StateRootProof stateRootProof;
        uint40[] validatorIndices;
        bytes[] withdrawalCredentialProofs;
        bytes[] validatorFieldsProofs;
        bytes32[][] validatorFields;
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


contract StakingNodeVerifyWithdrawalCredentialsOnHolesky is StakingNodeTestBase {

    using stdStorage for StdStorage;
    using BytesLib for bytes;

    address newMockStakingNodeImplementation;


    function testVerifyWithdrawalCredentialsSuccesfully_32ETH() public {
        if (block.chainid != 17000) {
            return; // Skip test if not on Ethereum Mainnet
        }
        // Validator proven:
        // 1692941
        // 0xb7ea207e2cad7076c176af040a79ce3c9779e02f94e62548fb9856c8e1c9720398f88fd59e89e7cfe0518d43f299ea13
        uint256 nodeId = 0;
        verifyWithdrawalCredentialsSuccesfullyForProofFile(nodeId, "test/data/holesky_wc_proof_1902072.json");
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
    }
}
