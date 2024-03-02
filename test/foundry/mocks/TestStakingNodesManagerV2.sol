// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import "../../../src/StakingNodesManager.sol";
import "./TestStakingNodeV2.sol";


contract TestStakingNodesManagerV2 is StakingNodesManager {
    function initializeStakingNode(IStakingNode node) override internal {

         uint64 initializedVersion = node.getInitializedVersion();
         if (initializedVersion == 0) {
             uint256 nodeId = nodes.length;
             node.initialize(
                IStakingNode.Init(IStakingNodesManager(address(this)), nodeId)
             );
         }

         if (initializedVersion == 1) {
            TestStakingNodeV2(payable(address(node)))
                .initializeV2(TestStakingNodeV2.ReInit({valueToBeInitialized: 23}));
         }
    }
}
