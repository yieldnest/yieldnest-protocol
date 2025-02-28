// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IynEigen} from "src/interfaces/IynEigen.sol";
import {ITokenStakingNodesManager} from "src/interfaces/ITokenStakingNodesManager.sol";
import {ITokenStakingNode} from "src/interfaces/ITokenStakingNode.sol";
import {TestTokenStakingNodeV2} from "test/mocks/TestTokenStakingNodeV2.sol";
import {TokenStakingNodesManager} from "src/ynEIGEN/TokenStakingNodesManager.sol";

contract TestTokenStakingNodesManagerV2 is TokenStakingNodesManager {


    function initializeTokenStakingNode(ITokenStakingNode node, uint256 nodeId) virtual override internal {

         uint64 initializedVersion = node.getInitializedVersion();
         if (initializedVersion == 0) {
             node.initialize(
               ITokenStakingNode.Init(ITokenStakingNodesManager(address(this)), nodeId)
             );

             // update version to latest
             initializedVersion = node.getInitializedVersion();
             emit NodeInitialized(address(node), initializedVersion);
         }

         if (initializedVersion == 1) {
             node.initializeV2();
             initializedVersion = node.getInitializedVersion();
             emit NodeInitialized(address(node), initializedVersion);
         }

         if (initializedVersion == 2) {
             TestTokenStakingNodeV2.ReInit memory reInit = TestTokenStakingNodeV2.ReInit({
                 valueToBeInitialized: 23
             });
             TestTokenStakingNodeV2(payable(address(node))).initializeV3(reInit);
             initializedVersion = node.getInitializedVersion();
             emit NodeInitialized(address(node), initializedVersion);
         }
    }
}
