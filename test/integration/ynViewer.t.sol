// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IStakingNodesManager} from "src/interfaces/IStakingNodesManager.sol";

import "./IntegrationBaseTest.sol";

contract ynViewerTest is IntegrationBaseTest {

    function setUp() public override {
        super.setUp();

        viewer = new ynViewer(address(yneth), address(stakingNodesManager));
    }

    function testGetAllValidators() public {
        IStakingNodesManager.Validator[] memory validators = viewer.getAllValidators();
        assertEq(validators.length, 0, "testGetAllValidators: E0");
    }

    function testGetRate() public {
        assertEq(viewer.getRate(), 1 ether, "testGetRate: E0");
    }

    function testWithdrawalDelayBlocks() public {
        assertEq(viewer.withdrawalDelayBlocks(address(this)), stakingNodesManager.delegationManager().minWithdrawalDelayBlocks(), "testWithdrawalDelayBlocks: E0"); // non-strategy
        assertGt(viewer.withdrawalDelayBlocks(address(0xbeaC0eeEeeeeEEeEeEEEEeeEEeEeeeEeeEEBEaC0)), 0, "testWithdrawalDelayBlocks: E1"); // beaconChainETHStrategy
    }

    function testGetStakingNodeData() public {
        ynViewer.StakingNodeData[] memory _data = viewer.getStakingNodeData();
        assertEq(_data.length, 0, "testGetStakingNodeData: E0");
    }
}	