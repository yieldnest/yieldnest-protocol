// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IntegrationBaseTest} from "test/integration/IntegrationBaseTest.sol";
import {IynViewer} from "src/interfaces/IynViewer.sol";
import {ynViewer as YnViewer} from "src/ynViewer.sol";
import {IStakingNode} from "src/interfaces/IStakingNode.sol";
import {IStakingNodesManager} from "src/interfaces/IStakingNodesManager.sol";

contract ynViewerTest is IntegrationBaseTest {
    IynViewer ynViewer;

    function setUp() public override {
        super.setUp();
        ynViewer = new YnViewer(yneth, stakingNodesManager);
    }

    function testGetAllValidators() public {
        IStakingNodesManager.Validator[] memory validators = ynViewer.getAllValidators();
        assertEq(validators.length, 0, "There should be no validators");
    }
    
    function testgetAllStakingNodes() public {
        IStakingNode[] memory stakingNodes = ynViewer.getAllStakingNodes();
        assertEq(stakingNodes.length, 0, "There should be no staking nodes");
    }
}	