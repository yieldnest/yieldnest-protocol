// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import "../../../src/StakingNodesManager.sol";
import "./TestStakingNodeV2.sol";
import "forge-std/console.sol";



contract TestStakingNodesManagerV2 is StakingNodesManager {
    function initializeStakingNode(IStakingNode node) override internal {

         uint64 initializedVersion = node.getInitializedVersion();
         console.log("Initialized version:", initializedVersion);
         if (initializedVersion == 0) {
             uint256 nodeId = nodes.length;
             console.log("Initializing node with ID:", nodeId);
             node.initialize(
                IStakingNode.Init(IStakingNodesManager(address(this)), nodeId)
             );
             console.log("Node initialized with version 0");
             initializedVersion = node.getInitializedVersion();
         }

         if (initializedVersion == 1) {
            console.log("Upgrading node to version 2");
            TestStakingNodeV2(payable(address(node)))
                .initializeV2(TestStakingNodeV2.ReInit({valueToBeInitialized: 23}));
            console.log("Node upgraded to version 2 with valueToBeInitialized set to 23");
         }
    }
}
