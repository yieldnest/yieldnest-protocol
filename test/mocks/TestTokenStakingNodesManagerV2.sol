// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IynEigen} from "src/interfaces/IynEigen.sol";
import {ITokenStakingNodesManager} from "src/interfaces/ITokenStakingNodesManager.sol";
import {ITokenStakingNode} from "src/interfaces/ITokenStakingNode.sol";
import {TestTokenStakingNodeV2} from "test/mocks/TestTokenStakingNodeV2.sol";
import {TokenStakingNodesManager} from "src/ynEIGEN/TokenStakingNodesManager.sol";

contract TestTokenStakingNodesManagerV2 is TokenStakingNodesManager {
    function initializeTokenStakingNode(ITokenStakingNode node, uint256 nodeId) internal override {

         uint64 initializedVersion = node.getInitializedVersion();
         if (initializedVersion == 0) {
             node.initialize(
                ITokenStakingNode.Init(ITokenStakingNodesManager(address(this)), nodeId)
             );
             initializedVersion = node.getInitializedVersion();
         }

         if (initializedVersion == 1) {
            TestTokenStakingNodeV2(payable(address(node)))
                .initializeV2(TestTokenStakingNodeV2.ReInit({valueToBeInitialized: 23}));
         }
    }
}
