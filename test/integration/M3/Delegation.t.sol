// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IEigenPod} from "lib/eigenlayer-contracts/src/contracts/interfaces/IEigenPod.sol";

import {IStakingNode} from "../../../src/interfaces/IStakingNode.sol";
import {IStakingNodesManager} from "../../../src/interfaces/IStakingNodesManager.sol";
import {IWithdrawalQueueManager} from "../../../src/interfaces/IWithdrawalQueueManager.sol";

import "./Base.t.sol";

interface IPod {
    function verifyWithdrawalCredentials(uint64 beaconTimestamp, BeaconChainProofs.StateRootProof calldata stateRootProof, uint40[] calldata validatorIndices, bytes[] calldata validatorFieldsProofs, bytes32[][] calldata validatorFields) external;
    function verifyCheckpointProofs(BeaconChainProofs.BalanceContainerProof calldata balanceContainerProof, BeaconChainProofs.BalanceProof[] calldata proofs) external;
}

interface IStakingNodeVars {
    function queuedSharesAmount() external view returns (uint256);
    function withdrawnETH() external view returns (uint256);
}

contract DelegationTest is Base {

    function testUndelegateStakingNode0() public {

        // Log total assets before undelegation
        uint256 totalAssetsBefore = yneth.totalAssets();
        console.log("Total assets before undelegation:", totalAssetsBefore);

        // Get operator for node 0
        address operator = delegationManager.delegatedTo(address(stakingNodesManager.nodes(0)));

        // Call undelegate from operator
        vm.startPrank(operator);
        delegationManager.undelegate(address(stakingNodesManager.nodes(0)));
        vm.stopPrank();

        // Log total assets after undelegation  
        uint256 totalAssetsAfter = yneth.totalAssets();
        console.log("Total assets after undelegation:", totalAssetsAfter);
    }
}