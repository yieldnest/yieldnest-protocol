// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {StakingNodesManager} from "src/StakingNodesManager.sol";
import {IStakingNode} from "src/interfaces/IStakingNode.sol";
import {IStakingNodesManager} from "src/interfaces/IStakingNodesManager.sol";

contract PlaceholderStakingNodesManager is StakingNodesManager {
    // Additional functionality can be added here

    struct NodeInitializationData {
        uint256 initializationDelta;
    }

    uint256 private immutable node0InitializationDelta;
    uint256 private immutable node1InitializationDelta;
    uint256 private immutable node2InitializationDelta;
    uint256 private immutable node3InitializationDelta;
    uint256 private immutable node4InitializationDelta;

    constructor(uint256[] memory _nodeDeltas) {
        require(_nodeDeltas.length == 5, "Invalid number of node deltas");
        
        node0InitializationDelta = _nodeDeltas[0];
        node1InitializationDelta = _nodeDeltas[1];
        node2InitializationDelta = _nodeDeltas[2];
        node3InitializationDelta = _nodeDeltas[3];
        node4InitializationDelta = _nodeDeltas[4];
    }
    
    function initializeStakingNode(IStakingNode node, uint256 nodeCount) override internal {
        uint64 initializedVersion = node.getInitializedVersion();
        if (initializedVersion == 0) {
            node.initialize(
                IStakingNode.Init(IStakingNodesManager(address(this)), nodeCount)
            );

            // update to the newly upgraded version.
            initializedVersion = node.getInitializedVersion();
            emit NodeInitialized(address(node), initializedVersion);
        }

        if (initializedVersion == 1) {

            uint256 initializationDelta;
            uint256 nodeId = node.nodeId();
            if (nodeId == 0) {
                initializationDelta = node0InitializationDelta;
            } else if (nodeId == 1) {
                initializationDelta = node1InitializationDelta;
            } else if (nodeId == 2) {
                initializationDelta = node2InitializationDelta;
            } else if (nodeId == 3) {
                initializationDelta = node3InitializationDelta;
            } else if (nodeId == 4) {
                initializationDelta = node4InitializationDelta;
            } else {
                initializationDelta = 0;
            }
            node.initializeV2(initializationDelta);

        }
        // NOTE: for future versions add additional if clauses that initialize the node 
        // for the next version while keeping the previous initializers
    }
}
