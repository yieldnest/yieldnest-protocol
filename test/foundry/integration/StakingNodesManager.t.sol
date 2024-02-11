// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IntegrationBaseTest.sol";
import "forge-std/console.sol";
import "../../../src/StakingNodesManager.sol";
import "../../../src/mocks/MockStakingNode.sol";

contract StakingNodesManagerTest is IntegrationBaseTest {

    bytes ZERO_PUBLIC_KEY = hex"000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";
    bytes ZERO_SIGNATURE = hex"000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";
    bytes32 ZERO_DEPOSIT_ROOT = bytes32(0);

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

      function testRegisterValidators() public {

        address addr1 = vm.addr(100);

        vm.deal(addr1, 100 ether);

        uint depositAmount = 32 ether;
        vm.prank(addr1);
        yneth.depositETH{value: depositAmount}(addr1);
        uint balance = yneth.balanceOf(addr1);
        assertEq(balance, depositAmount, "Balance does not match deposit amount");

        console.log("Creating staking node...");
        stakingNodesManager.createStakingNode();

        uint nodeId = 0;

        IStakingNodesManager.DepositData[] memory depositData = new IStakingNodesManager.DepositData[](1);
        depositData[0] = IStakingNodesManager.DepositData({
            publicKey: ZERO_PUBLIC_KEY,
            signature: ZERO_SIGNATURE,
            nodeId: nodeId,
            depositDataRoot: bytes32(0)
        });

        console.log("Getting withdrawal credentials...", nodeId);
        bytes memory withdrawalCredentials = stakingNodesManager.getWithdrawalCredentials(nodeId);

        console.log("Generating deposit data root for each deposit data...");
        for (uint i = 0; i < depositData.length; i++) {
            uint amount = depositAmount / depositData.length;
            bytes32 depositDataRoot = stakingNodesManager.generateDepositRoot(depositData[i].publicKey, depositData[i].signature, withdrawalCredentials, amount);
            depositData[i].depositDataRoot = depositDataRoot;
        }
        
        console.log("Registering validators...");
        bytes32 depositRoot = ZERO_DEPOSIT_ROOT;
        stakingNodesManager.registerValidators(depositRoot, depositData);
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
