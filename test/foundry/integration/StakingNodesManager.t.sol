// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IntegrationBaseTest} from "./IntegrationBaseTest.sol";
import {IStakingNode} from "../../../src/interfaces/IStakingNode.sol";
import {IEigenPod} from "../../../src/external/eigenlayer/v0.1.0/interfaces/IEigenPod.sol";
import {IStakingNodesManager} from "../../../src/interfaces/IStakingNodesManager.sol";
import {MockStakingNode} from "../mocks/MockStakingNode.sol";
import "forge-std/console.sol";


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
        IStakingNodesManager.ValidatorData[] memory validatorData = new IStakingNodesManager.ValidatorData[](validatorCount);
        validatorData[0] = IStakingNodesManager.ValidatorData({
            publicKey: ZERO_PUBLIC_KEY,
            signature: ZERO_SIGNATURE,
            nodeId: nodeId,
            depositDataRoot: bytes32(0)
        });
        validatorData[1] = IStakingNodesManager.ValidatorData({
            publicKey: ONE_PUBLIC_KEY,
            signature: ZERO_SIGNATURE,
            nodeId: nodeId,
            depositDataRoot: bytes32(0)
        });

        bytes memory withdrawalCredentials = stakingNodesManager.getWithdrawalCredentials(nodeId);

        for (uint i = 0; i < validatorData.length; i++) {
            uint amount = depositAmount / validatorData.length;
            bytes32 depositDataRoot = stakingNodesManager.generateDepositRoot(validatorData[i].publicKey, validatorData[i].signature, withdrawalCredentials, amount);
            validatorData[i].depositDataRoot = depositDataRoot;

        }
        
        bytes32 depositRoot = depositContractEth2.get_deposit_root();
        vm.prank(actors.VALIDATOR_MANAGER);
        stakingNodesManager.registerValidators(depositRoot, validatorData);

        uint totalAssetsControlled = yneth.totalAssets();
        assertEq(totalAssetsControlled, depositAmount, "Total assets controlled does not match expected value");
    }

    function testUpgradeStakingNodeImplementation() public {
        IStakingNode stakingNodeInstance = stakingNodesManager.createStakingNode();
        address eigenPodAddress = address(stakingNodeInstance.eigenPod());

        MockStakingNode mockStakingNode = new MockStakingNode();
        bytes memory callData = abi.encodeWithSelector(MockStakingNode.reinitialize.selector, MockStakingNode.ReInit({valueToBeInitialized: 23}));
        vm.prank(actors.STAKING_ADMIN);
        stakingNodesManager.upgradeStakingNodeImplementation(payable(mockStakingNode), callData);

        address upgradedImplementationAddress = stakingNodesManager.implementationContract();
        assertEq(upgradedImplementationAddress, payable(mockStakingNode));

        address newEigenPodAddress = address(stakingNodeInstance.eigenPod());
        assertEq(newEigenPodAddress, eigenPodAddress);

        MockStakingNode mockStakingNodeInstance = MockStakingNode(payable(address(stakingNodeInstance)));
        uint redundantFunctionResult = mockStakingNodeInstance.redundantFunction();
        assertEq(redundantFunctionResult, 1234567);

        assertEq(mockStakingNodeInstance.valueToBeInitialized(), 23, "Value to be initialized does not match expected value");
    }

    function testFailRegisterStakingNodeImplementationTwice() public {
        address initialImplementation = address(new MockStakingNode());
        vm.prank(actors.STAKING_ADMIN);
        stakingNodesManager.registerStakingNodeImplementationContract(initialImplementation);

        address newImplementation = address(new MockStakingNode());
        vm.expectRevert("StakingNodesManager: Implementation already exists");
        vm.prank(actors.STAKING_ADMIN);
        stakingNodesManager.registerStakingNodeImplementationContract(newImplementation);
    }

    function testFailUpgradeStakingNodeImplementationWithoutCallData() public {
        address initialImplementation = address(new MockStakingNode());
        stakingNodesManager.registerStakingNodeImplementationContract(initialImplementation);

        address newImplementation = address(new MockStakingNode());
        vm.expectRevert("StakingNodesManager: Call data is empty");
        stakingNodesManager.upgradeStakingNodeImplementation(payable(newImplementation), "");
    }

    function testIsStakingNodesAdmin() public {
        stakingNodesManager.nodesLength();
        assertEq(stakingNodesManager.isStakingNodesAdmin(address(this)), false);
        assertEq(stakingNodesManager.isStakingNodesAdmin(actors.STAKING_NODES_ADMIN), true);
    }


    // TODO: Should createStakingNode be open to public?
    function testStakingNodesLength() public {
        uint256 initialLength = stakingNodesManager.nodesLength();
        stakingNodesManager.createStakingNode();
        uint256 newLength = stakingNodesManager.nodesLength();
        assertEq(newLength, initialLength + 1);
    }

    function testUpgradeStakingNodeImplementationWithCallData() public {
        IStakingNode stakingNodeInstance = stakingNodesManager.createStakingNode();
        address eigenPodAddress = address(stakingNodeInstance.eigenPod());

        MockStakingNode mockStakingNode = new MockStakingNode();
        bytes memory callData = abi.encodeWithSelector(MockStakingNode.reinitialize.selector, MockStakingNode.ReInit({valueToBeInitialized: 23}));
        vm.prank(actors.STAKING_ADMIN);
        stakingNodesManager.upgradeStakingNodeImplementation(payable(mockStakingNode), callData);

        address upgradedImplementationAddress = stakingNodesManager.implementationContract();
        assertEq(upgradedImplementationAddress, payable(mockStakingNode));

        address newEigenPodAddress = address(stakingNodeInstance.eigenPod());
        assertEq(newEigenPodAddress, eigenPodAddress);

        MockStakingNode mockStakingNodeInstance = MockStakingNode(payable(address(stakingNodeInstance)));
        uint redundantFunctionResult = mockStakingNodeInstance.redundantFunction();
        assertEq(redundantFunctionResult, 1234567);

        assertEq(mockStakingNodeInstance.valueToBeInitialized(), 23, "Value to be initialized does not match expected value");
    }
}
