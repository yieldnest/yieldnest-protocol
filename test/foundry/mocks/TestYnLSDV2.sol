// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import "../../../src/ynLSD.sol";
import "../../../src/interfaces/ILSDStakingNode.sol";
import "./TestLSDStakingNodeV2.sol";

contract TestYnLSDV2 is ynLSD {
    function initializeLSDStakingNode(ILSDStakingNode node) override internal {

         uint64 initializedVersion = node.getInitializedVersion();
         if (initializedVersion == 0) {
             uint256 nodeId = nodes.length;
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
