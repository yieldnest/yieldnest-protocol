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
// import {IBeaconChainOracle} from "lib/eigenlayer-contracts/src/contracts/interfaces/IBeaconChainOracle.sol";
// import {IDelayedWithdrawalRouter} from "lib/eigenlayer-contracts/src/contracts/interfaces/IDelayedWithdrawalRouter.sol";
import {IStrategy} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IDelegationManager, IDelegationManagerTypes} from "lib/eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {TransparentUpgradeableProxy} from "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ITransparentUpgradeableProxy} from "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ScenarioBaseTest} from "test/scenarios/ScenarioBaseTest.sol";
import { Invariants } from "test/scenarios/Invariants.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol"; 
import {BytesLib} from "lib/eigenlayer-contracts/src/contracts/libraries/BytesLib.sol";
// import { MockEigenLayerBeaconOracle } from "test/mocks/MockEigenLayerBeaconOracle.sol";

import {UpgradeableBeacon} from "lib/openzeppelin-contracts/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {TestStakingNodesManagerV2} from "test/mocks/TestStakingNodesManagerV2.sol";
import {TestStakingNodeV2} from "test/mocks/TestStakingNodeV2.sol";

import {BeaconChainProofs} from "lib/eigenlayer-contracts/src/contracts/libraries/BeaconChainProofs.sol";
import {Merkle} from "lib/eigenlayer-contracts/src/contracts/libraries/Merkle.sol";
import { ProofParsingV1 } from "test/eigenlayer-utils/ProofParsingV1.sol";
import {Utils} from "script/Utils.sol";
import {beaconChainETHStrategy} from "src/Constants.sol";
import {Vm} from "lib/forge-std/src/Vm.sol";
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
        // BeaconChainProofs.WithdrawalProof[] withdrawalProofs;
    }

    struct WithdrawAction {
        uint256 nodeId;
        uint256 amountToReinvest;
        uint256 amountToQueue;
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
        // params.withdrawalProofs =  new BeaconChainProofs.WithdrawalProof[](1);

        params.stateRootProof.beaconStateRoot = getBeaconStateRoot();
        params.stateRootProof.proof = getStateRootProof();
        params.validatorFields[0] = getValidatorFields();
        params.withdrawalFields[0] = getWithdrawalFields();
        // params.withdrawalProofs[0] = _getWithdrawalProof();
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


    // function _getWithdrawalProof() internal returns (BeaconChainProofs.WithdrawalProof memory) {
    //     {
    //         bytes32 blockRoot = getBlockRoot();
    //         bytes32 slotRoot = getSlotRoot();
    //         bytes32 timestampRoot = getTimestampRoot();
    //         bytes32 executionPayloadRoot = getExecutionPayloadRoot();

    //         return
    //             BeaconChainProofs.WithdrawalProof(
    //                 abi.encodePacked(getWithdrawalProofDeneb()),
    //                 abi.encodePacked(getSlotProof()),
    //                 abi.encodePacked(getExecutionPayloadProof()),
    //                 abi.encodePacked(getTimestampProofDeneb()),
    //                 abi.encodePacked(getHistoricalSummaryProof()),
    //                 uint64(getBlockRootIndex()),
    //                 uint64(getHistoricalSummaryIndex()),
    //                 uint64(getWithdrawalIndex()),
    //                 blockRoot,
    //                 slotRoot,
    //                 timestampRoot,
    //                 executionPayloadRoot
    //             );
    //     }
    // }

    // function setupForVerifyWithdrawalCredentials(uint256 nodeId, string memory path) public {

    //     setJSON(path);

    //     IStakingNode stakingNodeInstance = stakingNodesManager.nodes(nodeId);

    //     MockEigenLayerBeaconOracle mockBeaconOracle = new MockEigenLayerBeaconOracle();

    //     address eigenPodManagerOwner = OwnableUpgradeable(address(eigenPodManager)).owner();
    //     vm.prank(eigenPodManagerOwner);
    //     eigenPodManager.updateBeaconChainOracle(IBeaconChainOracle(address(mockBeaconOracle)));
        
    //     // set existing EigenPod to be the EigenPod of the StakingNode for the 
    //     // purpose of testing verifyWithdrawalCredentials
    //     address eigenPodAddress = getWithdrawalAddress();

    //     assertEq(eigenPodAddress, address(stakingNodeInstance.eigenPod()), "EigenPod address does not match the expected address");

    //     bytes32 latestBlockRoot = _getLatestBlockRoot();
    //     mockBeaconOracle.setOracleBlockRootAtTimestamp(latestBlockRoot);
    // }

    function runSystemStateInvariants(
        uint256 previousTotalAssets,
        uint256 previousTotalSupply,
        uint256[] memory previousStakingNodeBalances
    ) public {  
        assertEq(yneth.totalAssets(), previousTotalAssets, "Total assets integrity check failed");
        assertEq(yneth.totalSupply(), previousTotalSupply, "Share mint integrity check failed");
        for (uint i = 0; i < previousStakingNodeBalances.length; i++) {
            IStakingNode stakingNodeInstance = stakingNodesManager.nodes(i);
            uint256 currentStakingNodeBalance = stakingNodeInstance.getETHBalance();
            assertEq(currentStakingNodeBalance, previousStakingNodeBalances[i], "Staking node balance integrity check failed for node ID: ");
        }
	}

    function runSystemStateInvariants(
        uint256 previousTotalAssets,
        uint256 previousTotalSupply,
        uint256[] memory previousStakingNodeBalances,
        IStakingNodesManager.WithdrawalAction[] memory withdrawActions,
        uint256 previousYnETHRedemptionAssetsVaultBalance,
        uint256 previousYnETHBalance
    ) public {  
        assertEq(yneth.totalAssets(), previousTotalAssets, "Total assets integrity check failed");
        assertEq(yneth.totalSupply(), previousTotalSupply, "Share mint integrity check failed");
        for (uint i = 0; i < previousStakingNodeBalances.length; i++) {
            IStakingNode stakingNodeInstance = stakingNodesManager.nodes(i);
            uint256 currentStakingNodeBalance = stakingNodeInstance.getETHBalance();
            uint256 expectedBalance = previousStakingNodeBalances[i];
            for (uint j = 0; j < withdrawActions.length; j++) {
                if (withdrawActions[j].nodeId == i) {
                    expectedBalance -= withdrawActions[j].amountToQueue + withdrawActions[j].amountToReinvest;
                }
            }
            assertEq(currentStakingNodeBalance, expectedBalance, "Staking node balance integrity check failed for node ID: ");
        }

        uint256 currentYnETHRedemptionAssetsVaultBalance = ynETHRedemptionAssetsVaultInstance.availableRedemptionAssets();
        uint256 expectedVaultBalance = previousYnETHRedemptionAssetsVaultBalance;
        uint256 expectedYnETHBalance = previousYnETHBalance;
        for (uint j = 0; j < withdrawActions.length; j++) {
            expectedVaultBalance += withdrawActions[j].amountToQueue;
            expectedYnETHBalance += withdrawActions[j].amountToReinvest;
        }
        assertEq(currentYnETHRedemptionAssetsVaultBalance, expectedVaultBalance, "YnETH Redemption Assets Vault balance integrity check failed after withdrawals");
        assertEq(address(yneth).balance, expectedYnETHBalance, "YnETH balance integrity check failed after withdrawals");
        assertEq(yneth.totalDepositedInPool(), expectedYnETHBalance, "Total Deposited in Pool integrity check failed after withdrawals");
	}

    function completeQueuedWithdrawals(IStakingNode stakingNodeInstance, uint256 withdrawalAmount) public {
        uint256 nonce = delegationManager.cumulativeWithdrawalsQueued(address(stakingNodeInstance)) - 1;

        IStrategy[] memory strategies = new IStrategy[](1);
        strategies[0] = beaconChainETHStrategy;

        uint256[] memory shares = new uint256[](1);
        shares[0] = withdrawalAmount;
        IDelegationManagerTypes.Withdrawal memory withdrawal = IDelegationManagerTypes.Withdrawal({
            staker: address(stakingNodeInstance),
            delegatedTo: delegationManager.delegatedTo(address(stakingNodeInstance)),
            withdrawer: address(stakingNodeInstance),
            nonce: nonce,
            startBlock: uint32(block.number),
            strategies: strategies,
            scaledShares: shares
        });

        IDelegationManagerTypes.Withdrawal[] memory withdrawals = new IDelegationManagerTypes.Withdrawal[](1);
        withdrawals[0] = withdrawal;

        uint256[] memory middlewareTimesIndexes = new uint256[](1);
        middlewareTimesIndexes[0] = 0; // value is not used, as per EigenLayer docs

        // Advance time so the withdrawal can be completed
        vm.roll(block.number + delegationManager.minWithdrawalDelayBlocks() + 1);

        vm.expectRevert(bytes4(keccak256("NotStakingNodesWithdrawer()")));
        stakingNodeInstance.completeQueuedWithdrawals(withdrawals, middlewareTimesIndexes);

        vm.prank(actors.ops.STAKING_NODES_WITHDRAWER);
        stakingNodeInstance.completeQueuedWithdrawals(withdrawals, middlewareTimesIndexes);
    }

    function getAllStakingNodeBalances() public view returns (uint256[] memory) {
        uint256[] memory balances = new uint256[](stakingNodesManager.nodesLength());
        for (uint256 i = 0; i < stakingNodesManager.nodesLength(); i++) {
            IStakingNode stakingNode = stakingNodesManager.nodes(i);
            balances[i] = stakingNode.getETHBalance();
        }
        return balances;
    }

    // // TODO: Update This 
    // function sumTotalDelayedWithdrawalsForUser(address user) public view returns (uint256 totalDelayedWithdrawals) {

    //     IDelayedWithdrawalRouter.DelayedWithdrawal[] memory delayedWithdrawals
    //         = delayedWithdrawalRouter.getUserDelayedWithdrawals(user);
    //     for (uint256 j = 0; j < delayedWithdrawals.length; j++) {
    //         totalDelayedWithdrawals += delayedWithdrawals[j].amount;
    //     }
    // }

    function finalizeRequest(uint256 tokenId) public returns (uint256) {
        vm.prank(actors.ops.REQUEST_FINALIZER);
        return ynETHWithdrawalQueueManager.finalizeRequestsUpToIndex(tokenId + 1);
    }
}