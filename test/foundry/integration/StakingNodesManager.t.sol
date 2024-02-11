// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IntegrationBaseTest.sol";
import "forge-std/console.sol";
import "../../../src/StakingNodesManager.sol";
import "../../../src/mocks/MockStakingNode.sol";

contract StakingNodesManagerTest is IntegrationBaseTest {
    address owner;
    address addr1;
    address addr2;

    function testCreateStakingNode() public {
        IStakingNode stakingNodeInstance = stakingNodesManager.createStakingNode();
        IEigenPod eigenPod = stakingNodeInstance.eigenPod();
        assertEq(address(stakingNodesManager), address(stakingNodeInstance.stakingNodesManager()), "StakingNodesManager is not correct");
        address eigenPodOwner = eigenPod.podOwner();
        assertEq(eigenPodOwner, address(stakingNodeInstance), "EigenPod owner is not the staking node instance");
    }

    function testCreate2StakingNodes() public {

        IStakingNode stakingNodeInstance1 = stakingNodesManager.createStakingNode();
        IEigenPod eigenPod1 = stakingNodeInstance1.eigenPod();
        assertEq(address(stakingNodesManager), address(stakingNodeInstance1.stakingNodesManager()), "StakingNodesManager for node 1 is not correct");
        address eigenPodOwner1 = eigenPod1.podOwner();
        assertEq(eigenPodOwner1, address(stakingNodeInstance1), "EigenPod owner for node 1 is not the staking node instance");

        IStakingNode stakingNodeInstance2 = stakingNodesManager.createStakingNode();
        IEigenPod eigenPod2 = stakingNodeInstance2.eigenPod();
        assertEq(address(stakingNodesManager), address(stakingNodeInstance2.stakingNodesManager()), "StakingNodesManager for node 2 is not correct");
        address eigenPodOwner2 = eigenPod2.podOwner();
        assertEq(eigenPodOwner2, address(stakingNodeInstance2), "EigenPod owner for node 2 is not the staking node instance");
    }

    function testUpgradeStakingNodeImplementation() public {
        IStakingNode stakingNodeInstance = stakingNodesManager.createStakingNode();
        address eigenPodAddress = address(stakingNodeInstance.eigenPod());

        MockStakingNode mockStakingNode = new MockStakingNode();
        stakingNodesManager.registerStakingNodeImplementationContract(address(mockStakingNode));

        address upgradedImplementationAddress = stakingNodesManager.implementationContract();
        assertEq(upgradedImplementationAddress, address(mockStakingNode));

        address newEigenPodAddress = address(stakingNodeInstance.eigenPod());
        assertEq(newEigenPodAddress, eigenPodAddress);

        MockStakingNode mockStakingNodeInstance = MockStakingNode(address(stakingNodeInstance));
        uint redundantFunctionResult = mockStakingNodeInstance.redundantFunction();
        assertEq(redundantFunctionResult, 1234567);
    }
}
