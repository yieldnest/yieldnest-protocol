// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IynEigen} from "src/interfaces/IynEigen.sol";
import {ITokenStakingNodesManager} from "src/interfaces/ITokenStakingNodesManager.sol";
import {TestLSDStakingNodeV2} from "test/mocks/TestLSDStakingNodeV2.sol";

contract TestYnLSDV2 is ynLSD {
    function initializeLSDStakingNode(ILSDStakingNode node, uint256 nodeId) internal {

         uint64 initializedVersion = node.getInitializedVersion();
         if (initializedVersion == 0) {
             node.initialize(
                ILSDStakingNode.Init(ITokenStakingNodesManager(address(this)), nodeId)
             );
             initializedVersion = node.getInitializedVersion();
         }

         if (initializedVersion == 1) {
            TestLSDStakingNodeV2(payable(address(node)))
                .initializeV2(TestLSDStakingNodeV2.ReInit({valueToBeInitialized: 23}));
         }
    }
}
