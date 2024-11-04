// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import "src/StakingNodesManager.sol";
import "test/mocks/TestStakingNodeV2.sol";

contract TestStakingNodesManagerV2 is StakingNodesManager {

    uint256 public newV2Value;
    struct ReInit {
        uint256 newV2Value;
    }

    function initializeV3(ReInit memory reInit) public reinitializer(3) {
        newV2Value = reInit.newV2Value;
    }

    function initializeStakingNode(IStakingNode node, uint256 nodeCount) override internal {

         uint64 initializedVersion = node.getInitializedVersion();
         if (initializedVersion == 0) {
             node.initialize(
                IStakingNode.Init(IStakingNodesManager(address(this)), nodeCount)
             );
             initializedVersion = node.getInitializedVersion();
         }

        if (initializedVersion == 1) {
            node.initializeV2(0);
        }


        if (initializedVersion == 2) {
            node.initializeV3();
        }


         if (initializedVersion == 3) {
            TestStakingNodeV2(payable(address(node)))
                .initializeV4(TestStakingNodeV2.ReInit({valueToBeInitialized: 23}));
         }
    }

    /// @notice Retrieve the version number of the highest/newest initialize
    ///         function that was executed.
    function getInitializedVersion() external view returns (uint64) {
        return _getInitializedVersion();
    }
}
