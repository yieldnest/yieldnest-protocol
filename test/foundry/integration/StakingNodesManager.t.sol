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
        IStakingNodesManager stakingNodesManager = stakingNodeInstance.stakingNodesManager();
    }

    // function testCreate2StakingNodes() public {
    //     address stakingNodeAddress1 = stakingNodesManager.createStakingNode();
    //     IStakingNode stakingNodeInstance1 = IStakingNode(stakingNodeAddress1);
    //     address eigenPodAddress1 = stakingNodeInstance1.eigenPod();
    //     address stakingNodesManagerAddress1 = stakingNodeInstance1.stakingNodesManager();
    //     assertEq(stakingNodesManagerAddress1, address(stakingNodesManager));

    //     address stakingNodeAddress2 = stakingNodesManager.createStakingNode();
    //     IStakingNode stakingNodeInstance2 = IStakingNode(stakingNodeAddress2);
    //     address eigenPodAddress2 = stakingNodeInstance2.eigenPod();
    //     address stakingNodesManagerAddress2 = stakingNodeInstance2.stakingNodesManager();
    //     assertEq(stakingNodesManagerAddress2, address(stakingNodesManager));
    // }

    // function testRegisterValidators() public {
    //     // Simulate deposit and balance checks
    //     // This part is highly dependent on the implementation details of the contract
    //     // and might need adjustments based on the actual contract logic

    //     console.log("Creating staking node...");
    //     address stakingNodeAddress = stakingNodesManager.createStakingNode();

    //     // Assuming the nodeId is obtained or set in a specific way in the contract
    //     uint nodeId = 0;

    //     // Simulate generating deposit data root and registering validators
    //     // This is a simplified version and should be adjusted according to the actual contract logic
    //     console.log("Registering validators...");
    //     bytes32 depositRoot = 0x0000000000000000000000000000000000000000000000000000000000000000;
    //     // Assuming a function exists to register validators with simplified parameters
    //     stakingNodesManager.registerValidators(depositRoot, nodeId);
    // }

    // function testUpgradeStakingNodeImplementation() public {
    //     console.log("Creating staking node...");
    //     address stakingNodeAddress = stakingNodesManager.createStakingNode();
    //     IStakingNode stakingNodeInstance = IStakingNode(stakingNodeAddress);
    //     address eigenPodAddress = stakingNodeInstance.eigenPod();
    //     console.log("EigenPod address: ", eigenPodAddress);

    //     MockStakingNode mockStakingNode = new MockStakingNode();
    //     console.log("Upgrading StakingNode implementation...");
    //     stakingNodesManager.registerStakingNodeImplementationContract(address(mockStakingNode));

    //     address upgradedImplementationAddress = stakingNodesManager.implementationContract();
    //     assertEq(upgradedImplementationAddress, address(mockStakingNode));

    //     console.log("Fetching EigenPod address after upgrade...");
    //     address newEigenPodAddress = stakingNodeInstance.eigenPod();
    //     console.log("New EigenPod address: ", newEigenPodAddress);
    //     assertEq(newEigenPodAddress, eigenPodAddress);

    //     console.log("Loading MockStakingNode at stakingNodeInstance address...");
    //     MockStakingNode mockStakingNodeInstance = MockStakingNode(stakingNodeAddress);
    //     console.log("Calling redundant function...");
    //     uint redundantFunctionResult = mockStakingNodeInstance.redundantFunction();
    //     console.log("Redundant function result: ", redundantFunctionResult);
    //     assertEq(redundantFunctionResult, 1234567);
    // }
}
