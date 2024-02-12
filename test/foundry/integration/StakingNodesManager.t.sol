// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IntegrationBaseTest.sol";
import "forge-std/console.sol";
import "../../../src/StakingNodesManager.sol";
import "../../../src/mocks/MockStakingNode.sol";

contract StakingNodesManagerTest is IntegrationBaseTest {

    function testCreateStakingNode() public {
        IStakingNode stakingNodeInstance = stakingNodesManager.createStakingNode();
        IEigenPod eigenPod = stakingNodeInstance.eigenPod();
        assertEq(address(stakingNodesManager), address(stakingNodeInstance.stakingNodesManager()), "StakingNodesManager is not correct");
        address eigenPodOwner = eigenPod.podOwner();
        assertEq(eigenPodOwner, address(stakingNodeInstance), "EigenPod owner is not the staking node instance");

        uint expectedNodeId = 0;
        assertEq(stakingNodeInstance.nodeId(), expectedNodeId, "Node ID does not match expected value");
    }

    function testCreate2StakingNodes() public {
        IStakingNode stakingNodeInstance1 = stakingNodesManager.createStakingNode();
        IEigenPod eigenPod1 = stakingNodeInstance1.eigenPod();
        assertEq(address(stakingNodesManager), address(stakingNodeInstance1.stakingNodesManager()), "StakingNodesManager for node 1 is not correct");
        address eigenPodOwner1 = eigenPod1.podOwner();
        assertEq(eigenPodOwner1, address(stakingNodeInstance1), "EigenPod owner for node 1 is not the staking node instance");
        uint expectedNodeId1 = 0;
        assertEq(stakingNodeInstance1.nodeId(), expectedNodeId1, "Node ID for node 1 does not match expected value");

        IStakingNode stakingNodeInstance2 = stakingNodesManager.createStakingNode();
        IEigenPod eigenPod2 = stakingNodeInstance2.eigenPod();
        assertEq(address(stakingNodesManager), address(stakingNodeInstance2.stakingNodesManager()), "StakingNodesManager for node 2 is not correct");
        address eigenPodOwner2 = eigenPod2.podOwner();
        assertEq(eigenPodOwner2, address(stakingNodeInstance2), "EigenPod owner for node 2 is not the staking node instance");
        uint expectedNodeId2 = 1;
        assertEq(stakingNodeInstance2.nodeId(), expectedNodeId2, "Node ID for node 2 does not match expected value");
    }

      function testRegisterValidators() public {

        address addr1 = vm.addr(100);

        vm.deal(addr1, 100 ether);

        uint validatorCount = 2;

        uint depositAmount = 32 ether * validatorCount;
        vm.prank(addr1);
        yneth.depositETH{value: depositAmount}(addr1);
        uint balance = yneth.balanceOf(addr1);
        assertEq(balance, depositAmount, "Balance does not match deposit amount");
        
        stakingNodesManager.createStakingNode();

        uint nodeId = 0;
        IStakingNodesManager.DepositData[] memory depositData = new IStakingNodesManager.DepositData[](validatorCount);
        depositData[0] = IStakingNodesManager.DepositData({
            publicKey: ZERO_PUBLIC_KEY,
            signature: ZERO_SIGNATURE,
            nodeId: nodeId,
            depositDataRoot: bytes32(0)
        });
        depositData[1] = IStakingNodesManager.DepositData({
            publicKey: ONE_PUBLIC_KEY,
            signature: ZERO_SIGNATURE,
            nodeId: nodeId,
            depositDataRoot: bytes32(0)
        });

        bytes memory withdrawalCredentials = stakingNodesManager.getWithdrawalCredentials(nodeId);

        for (uint i = 0; i < depositData.length; i++) {
            uint amount = depositAmount / depositData.length;
            bytes32 depositDataRoot = stakingNodesManager.generateDepositRoot(depositData[i].publicKey, depositData[i].signature, withdrawalCredentials, amount);
            depositData[i].depositDataRoot = depositDataRoot;
        }
        
        bytes32 depositRoot = ZERO_DEPOSIT_ROOT;
        stakingNodesManager.registerValidators(depositRoot, depositData);

        uint totalAssetsControlled = yneth.totalAssets();
        assertEq(totalAssetsControlled, depositAmount, "Total assets controlled does not match expected value");
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
