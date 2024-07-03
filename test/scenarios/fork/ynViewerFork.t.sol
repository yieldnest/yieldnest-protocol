// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IStakingNodesManager} from "src/interfaces/IStakingNodesManager.sol";

import {DeployYnViewer} from "../../../script/deployYnViewer.s.sol";

import "../ScenarioBaseTest.sol";

contract ynViewerForkTest is ScenarioBaseTest, DeployYnViewer {

    function setUp() public override {
        super.setUp();

        (, privateKey) = makeAddrAndKey("deployer");
        DeployYnViewer.run();
    }

    function testGetAllValidators() public {
        IStakingNodesManager.Validator[] memory validators = viewer.getAllValidators();
        assertGt(validators.length, 0, "testGetAllValidators: E0");
    }

    function testGetRate() public {
        assertGt(viewer.getRate(), 1 ether, "testGetRate: E0");
    }

    function testWithdrawalDelayBlocks() public {
        uint256 _minWithdrawalDelayBlocks = stakingNodesManager.delegationManager().minWithdrawalDelayBlocks();
        assertEq(viewer.withdrawalDelayBlocks(address(this)), _minWithdrawalDelayBlocks, "testWithdrawalDelayBlocks: E0"); // non-strategy
        assertGe(viewer.withdrawalDelayBlocks(address(0xbeaC0eeEeeeeEEeEeEEEEeeEEeEeeeEeeEEBEaC0)), _minWithdrawalDelayBlocks, "testWithdrawalDelayBlocks: E1"); // beaconChainETHStrategy
    }

    function testGetStakingNodeData() public {
        ynViewer.StakingNodeData[] memory _data = viewer.getStakingNodeData();
        assertGt(_data.length, 0, "testGetStakingNodeData: E0");
        assertEq(_data[0].nodeId, 0, "testGetStakingNodeData: E1");
        assertGe(_data[0].ethBalance, 0, "testGetStakingNodeData: E2");
        assertGe(_data[0].eigenPodEthBalance, 0, "testGetStakingNodeData: E3");
        assertGe(_data[0].podOwnerShares, 0, "testGetStakingNodeData: E4");
        assertNotEq(_data[0].stakingNode, address(0), "testGetStakingNodeData: E5");
        assertNotEq(_data[0].eigenPod, address(0), "testGetStakingNodeData: E6");
        assertNotEq(_data[0].delegatedTo, address(0), "testGetStakingNodeData: E7");
    }
}