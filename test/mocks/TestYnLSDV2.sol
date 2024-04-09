// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {ynLSD} from "src/ynLSD.sol";
import {IynLSD} from "src/interfaces/IynLSD.sol";
import {ILSDStakingNode} from "src/interfaces/ILSDStakingNode.sol";
import {TestLSDStakingNodeV2} from "test/mocks/TestLSDStakingNodeV2.sol";

contract TestYnLSDV2 is ynLSD {
    function initializeLSDStakingNode(ILSDStakingNode node, uint256 nodeId) override internal {

         uint64 initializedVersion = node.getInitializedVersion();
         if (initializedVersion == 0) {
             node.initialize(
                ILSDStakingNode.Init(IynLSD(address(this)), nodeId)
             );
             initializedVersion = node.getInitializedVersion();
         }

         if (initializedVersion == 1) {
            TestLSDStakingNodeV2(payable(address(node)))
                .initializeV2(TestLSDStakingNodeV2.ReInit({valueToBeInitialized: 23}));
         }
    }
}
