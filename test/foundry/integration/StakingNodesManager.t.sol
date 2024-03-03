// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IntegrationBaseTest} from "./IntegrationBaseTest.sol";
import {IStakingNode} from "../../../src/interfaces/IStakingNode.sol";
import {IEigenPod} from "../../../src/external/eigenlayer/v0.1.0/interfaces/IEigenPod.sol";
import {IStakingNodesManager} from "../../../src/interfaces/IStakingNodesManager.sol";
import "forge-std/console.sol";
import "../../../src/StakingNodesManager.sol";
import "../mocks/TestStakingNodeV2.sol";
import "../mocks/TestStakingNodesManagerV2.sol";


contract StakingNodesManagerTest is IntegrationBaseTest {

    function testCreateStakingNode() public {
        vm.prank(actors.STAKING_NODE_CREATOR);
        IStakingNode stakingNodeInstance = stakingNodesManager.createStakingNode();
        IEigenPod eigenPod = stakingNodeInstance.eigenPod();
        assertEq(address(stakingNodesManager), address(stakingNodeInstance.stakingNodesManager()), "StakingNodesManager is not correct");
        address eigenPodOwner = eigenPod.podOwner();
        assertEq(eigenPodOwner, address(stakingNodeInstance), "EigenPod owner is not the staking node instance");

        uint expectedNodeId = 0;
        assertEq(stakingNodeInstance.nodeId(), expectedNodeId, "Node ID does not match expected value");
    }

    function testCreate2StakingNodes() public {

        vm.prank(actors.STAKING_NODE_CREATOR);

        IStakingNode stakingNodeInstance1 = stakingNodesManager.createStakingNode();
        IEigenPod eigenPod1 = stakingNodeInstance1.eigenPod();
        assertEq(address(stakingNodesManager), address(stakingNodeInstance1.stakingNodesManager()), "StakingNodesManager for node 1 is not correct");
        address eigenPodOwner1 = eigenPod1.podOwner();
        assertEq(eigenPodOwner1, address(stakingNodeInstance1), "EigenPod owner for node 1 is not the staking node instance");
        uint expectedNodeId1 = 0;
        assertEq(stakingNodeInstance1.nodeId(), expectedNodeId1, "Node ID for node 1 does not match expected value");

        vm.prank(actors.STAKING_NODE_CREATOR);
        IStakingNode stakingNodeInstance2 = stakingNodesManager.createStakingNode();
        IEigenPod eigenPod2 = stakingNodeInstance2.eigenPod();
        assertEq(address(stakingNodesManager), address(stakingNodeInstance2.stakingNodesManager()), "StakingNodesManager for node 2 is not correct");
        address eigenPodOwner2 = eigenPod2.podOwner();
        assertEq(eigenPodOwner2, address(stakingNodeInstance2), "EigenPod owner for node 2 is not the staking node instance");
        uint expectedNodeId2 = 1;
        assertEq(stakingNodeInstance2.nodeId(), expectedNodeId2, "Node ID for node 2 does not match expected value");
    }

    function testCreateStakingNodeAfterUpgradeWithoutUpgradeability() public {
        // Upgrade the StakingNodesManager implementation to TestStakingNodesManagerV2
        address newImplementation = address(new TestStakingNodesManagerV2());
        vm.prank(actors.PROXY_ADMIN_OWNER);
        ProxyAdmin(getTransparentUpgradeableProxyAdminAddress(address(stakingNodesManager)))
            .upgradeAndCall(ITransparentUpgradeableProxy(address(stakingNodesManager)), newImplementation, "");

        // Attempt to create a staking node after the upgrade - should fail since implementation is not there
        vm.expectRevert();
        stakingNodesManager.createStakingNode();
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
        
        vm.prank(actors.STAKING_NODE_CREATOR);
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
        vm.prank(actors.STAKING_NODE_CREATOR);
        IStakingNode stakingNodeInstance = stakingNodesManager.createStakingNode();
        address eigenPodAddress = address(stakingNodeInstance.eigenPod());

        // upgrade the StakingNodeManager to support the new initialization version.
        address newStakingNodesManagerImpl = address(new TestStakingNodesManagerV2());
        vm.prank(actors.PROXY_ADMIN_OWNER);
        
        ProxyAdmin(getTransparentUpgradeableProxyAdminAddress(address(stakingNodesManager)))
            .upgradeAndCall(ITransparentUpgradeableProxy(address(stakingNodesManager)), newStakingNodesManagerImpl, "");

        TestStakingNodeV2 testStakingNodeV2 = new TestStakingNodeV2();
        vm.prank(actors.STAKING_ADMIN);
        stakingNodesManager.upgradeStakingNodeImplementation(payable(testStakingNodeV2));

        UpgradeableBeacon beacon = stakingNodesManager.upgradeableBeacon();
        address upgradedImplementationAddress = beacon.implementation();
        assertEq(upgradedImplementationAddress, payable(testStakingNodeV2));

        address newEigenPodAddress = address(stakingNodeInstance.eigenPod());
        assertEq(newEigenPodAddress, eigenPodAddress);

        TestStakingNodeV2 testStakingNodeV2Instance = TestStakingNodeV2(payable(address(stakingNodeInstance)));
        uint redundantFunctionResult = testStakingNodeV2Instance.redundantFunction();
        assertEq(redundantFunctionResult, 1234567);

        assertEq(testStakingNodeV2Instance.valueToBeInitialized(), 23, "Value to be initialized does not match expected value");
    }

    function testFailRegisterStakingNodeImplementationTwice() public {
        address initialImplementation = address(new TestStakingNodeV2());
        vm.prank(actors.STAKING_ADMIN);
        stakingNodesManager.registerStakingNodeImplementationContract(initialImplementation);

        address newImplementation = address(new TestStakingNodeV2());
        vm.expectRevert("StakingNodesManager: Implementation already exists");
        vm.prank(actors.STAKING_ADMIN);
        stakingNodesManager.registerStakingNodeImplementationContract(newImplementation);
    }

    function testIsStakingNodesAdmin() public {
        stakingNodesManager.nodesLength();
        assertEq(stakingNodesManager.isStakingNodesAdmin(address(this)), false);
        assertEq(stakingNodesManager.isStakingNodesAdmin(actors.STAKING_NODES_ADMIN), true);
    }

    // TODO: Should createStakingNode be open to public?
    function testStakingNodesLength() public {
        uint256 initialLength = stakingNodesManager.nodesLength();
        vm.prank(actors.STAKING_NODE_CREATOR);
        stakingNodesManager.createStakingNode();
        uint256 newLength = stakingNodesManager.nodesLength();
        assertEq(newLength, initialLength + 1);
    }
}
