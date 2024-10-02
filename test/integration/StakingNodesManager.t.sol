// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {ProxyAdmin} from "lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {UpgradeableBeacon} from "lib/openzeppelin-contracts/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {ITransparentUpgradeableProxy} from "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IntegrationBaseTest} from "test/integration/IntegrationBaseTest.sol";
import {IStakingNode} from "src/interfaces/IStakingNode.sol";
import {IEigenPod} from "lib/eigenlayer-contracts/src/contracts/interfaces/IEigenPod.sol";
import {IDepositContract} from "src/external/ethereum/IDepositContract.sol";
import {IStakingNodesManager} from "src/interfaces/IStakingNodesManager.sol";
import {StakingNodesManager} from "src/StakingNodesManager.sol";
import {ynETH} from "src/ynETH.sol";
import {RewardsType} from "src/interfaces/IRewardsDistributor.sol";
import {TestStakingNodeV2} from "test/mocks/TestStakingNodeV2.sol";
import {TestStakingNodesManagerV2} from "test/mocks/TestStakingNodesManagerV2.sol";
import {StakingNodeTestBase} from "./StakingNodeTestBase.sol";

import "forge-std/console.sol";



contract StakingNodesManagerStakingNodeCreation is IntegrationBaseTest {

    function testCreateStakingNode() public {
        vm.prank(actors.ops.STAKING_NODE_CREATOR);
        IStakingNode stakingNodeInstance = stakingNodesManager.createStakingNode();
        IEigenPod eigenPod = stakingNodeInstance.eigenPod();
        assertEq(address(stakingNodesManager), address(stakingNodeInstance.stakingNodesManager()), "StakingNodesManager is not correct");
        address eigenPodOwner = eigenPod.podOwner();
        assertEq(eigenPodOwner, address(stakingNodeInstance), "EigenPod owner is not the staking node instance");

        uint expectedNodeId = 0;
        assertEq(stakingNodeInstance.nodeId(), expectedNodeId, "Node ID does not match expected value");
    }

    function testCreate2StakingNodes() public {

        vm.prank(actors.ops.STAKING_NODE_CREATOR);

        IStakingNode stakingNodeInstance1 = stakingNodesManager.createStakingNode();
        IEigenPod eigenPod1 = stakingNodeInstance1.eigenPod();
        assertEq(address(stakingNodesManager), address(stakingNodeInstance1.stakingNodesManager()), "StakingNodesManager for node 1 is not correct");
        address eigenPodOwner1 = eigenPod1.podOwner();
        assertEq(eigenPodOwner1, address(stakingNodeInstance1), "EigenPod owner for node 1 is not the staking node instance");
        uint expectedNodeId1 = 0;
        assertEq(stakingNodeInstance1.nodeId(), expectedNodeId1, "Node ID for node 1 does not match expected value");

        vm.prank(actors.ops.STAKING_NODE_CREATOR);
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
        vm.prank(actors.admin.PROXY_ADMIN_OWNER);
        ProxyAdmin(getTransparentUpgradeableProxyAdminAddress(address(stakingNodesManager)))
            .upgradeAndCall(ITransparentUpgradeableProxy(address(stakingNodesManager)), newImplementation, "");

        // Attempt to create a staking node after the upgrade - should fail since implementation is not there
        vm.expectRevert();
        stakingNodesManager.createStakingNode();
    }

    function testFailToCreateStakingNodeWhenMaxCountReached() public {
        // Set the max node count to the current number of nodes to simulate the limit being reached
        uint256 currentNodesCount = stakingNodesManager.nodesLength();
        vm.prank(actors.admin.STAKING_ADMIN);
        stakingNodesManager.setMaxNodeCount(currentNodesCount);

        // Attempt to create a new staking node should fail due to max node count reached
        vm.prank(actors.ops.STAKING_NODE_CREATOR);
        vm.expectRevert(StakingNodesManager.TooManyStakingNodes.selector);
        stakingNodesManager.createStakingNode();
    }

    function testFailToCreateStakingNodeWithZeroAddressBeacon() public {
        // Attempt to create a staking node with a zero address beacon should fail
        vm.prank(actors.admin.STAKING_ADMIN);
        stakingNodesManager.registerStakingNodeImplementationContract(address(0));
        
        vm.prank(actors.ops.STAKING_NODE_CREATOR);
        vm.expectRevert(StakingNodesManager.ZeroAddress.selector);
        stakingNodesManager.createStakingNode();
    }

    function testFailToCreateStakingNodeWithoutStakingNodeCreatorRole() public {
        // Attempt to create a staking node without STAKING_NODE_CREATOR_ROLE should fail
        vm.expectRevert("AccessControlUnauthorizedAccount");
        stakingNodesManager.createStakingNode();
    }

    function testSetMaxNodeCount() public {
        uint256 initialMaxNodeCount = stakingNodesManager.maxNodeCount();
        uint256 newMaxNodeCount = initialMaxNodeCount + 1;
        vm.prank(actors.admin.STAKING_ADMIN);
        stakingNodesManager.setMaxNodeCount(newMaxNodeCount);
        uint256 updatedMaxNodeCount = stakingNodesManager.maxNodeCount();
        assertEq(updatedMaxNodeCount, newMaxNodeCount, "Max node count does not match expected value");
    }

    function testTooManyStakingNodes() public {
        // set the max node count to 1
        vm.prank(actors.admin.STAKING_ADMIN);
        stakingNodesManager.setMaxNodeCount(1);
        uint256 maxNodeCount = stakingNodesManager.maxNodeCount();
        // create first statking node
        vm.prank(actors.ops.STAKING_NODE_CREATOR);
        stakingNodesManager.createStakingNode();
        // create second staking node should fail
        vm.prank(actors.ops.STAKING_NODE_CREATOR);
        vm.expectRevert(abi.encodeWithSelector(StakingNodesManager.TooManyStakingNodes.selector, maxNodeCount));
        stakingNodesManager.createStakingNode();
    }
}

contract StakingNodesManagerStakingNodeImplementation is IntegrationBaseTest {

    function testUpgradeStakingNodeImplementation() public {
        vm.prank(actors.ops.STAKING_NODE_CREATOR);
        IStakingNode stakingNodeInstance = stakingNodesManager.createStakingNode();
        address eigenPodAddress = address(stakingNodeInstance.eigenPod());

        // upgrade the StakingNodeManager to support the new initialization version.
        address newStakingNodesManagerImpl = address(new TestStakingNodesManagerV2());
        vm.prank(actors.admin.PROXY_ADMIN_OWNER);
        
        ProxyAdmin(getTransparentUpgradeableProxyAdminAddress(address(stakingNodesManager)))
            .upgradeAndCall(ITransparentUpgradeableProxy(address(stakingNodesManager)), newStakingNodesManagerImpl, "");

        // uint64 initializedVersion = stakingNodeInstance.getInitializedVersion();
        // console.log("Initialized version initializedVersion", initializedVersion);

        TestStakingNodeV2 testStakingNodeV2 = new TestStakingNodeV2();
        vm.prank(actors.admin.STAKING_ADMIN);
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
        vm.prank(actors.admin.STAKING_ADMIN);
        stakingNodesManager.registerStakingNodeImplementationContract(initialImplementation);

        address newImplementation = address(new TestStakingNodeV2());
        vm.expectRevert("StakingNodesManager: Implementation already exists");
        vm.prank(actors.admin.STAKING_ADMIN);
        stakingNodesManager.registerStakingNodeImplementationContract(newImplementation);
    }

    function testIsStakingNodesAdmin() public {
        stakingNodesManager.nodesLength();
        assertEq(stakingNodesManager.isStakingNodesOperator(address(this)), false);
        assertEq(stakingNodesManager.isStakingNodesOperator(actors.ops.STAKING_NODES_OPERATOR), true);
    }

    function testStakingNodesLength() public {
        uint256 initialLength = stakingNodesManager.nodesLength();
        vm.prank(actors.ops.STAKING_NODE_CREATOR);
        stakingNodesManager.createStakingNode();
        uint256 newLength = stakingNodesManager.nodesLength();
        assertEq(newLength, initialLength + 1);
    }

}

contract StakingNodesManagerRegisterValidators is IntegrationBaseTest {

    function testRegisterValidators() public {

        address addr1 = vm.addr(100);

        vm.deal(addr1, 100 ether);

        uint validatorCount = 3;

        uint depositAmount = 32 ether * validatorCount;
        vm.prank(addr1);
        yneth.depositETH{value: depositAmount}(addr1);
        uint balance = yneth.balanceOf(addr1);
        assertEq(balance, depositAmount, "Balance does not match deposit amount");
        
        vm.prank(actors.ops.STAKING_NODE_CREATOR);
        stakingNodesManager.createStakingNode();

        vm.prank(actors.ops.STAKING_NODE_CREATOR);
        stakingNodesManager.createStakingNode();

        IStakingNodesManager.ValidatorData[] memory validatorData = new IStakingNodesManager.ValidatorData[](validatorCount);
        validatorData[0] = IStakingNodesManager.ValidatorData({
            publicKey: ZERO_PUBLIC_KEY,
            signature: ZERO_SIGNATURE,
            nodeId: 0,
            depositDataRoot: bytes32(0)
        });
        validatorData[1] = IStakingNodesManager.ValidatorData({
            publicKey: ONE_PUBLIC_KEY,
            signature: ZERO_SIGNATURE,
            nodeId: 1,
            depositDataRoot: bytes32(0)
        });

       validatorData[2] = IStakingNodesManager.ValidatorData({
            publicKey: TWO_PUBLIC_KEY,
            signature: ZERO_SIGNATURE,
            nodeId: 1,
            depositDataRoot: bytes32(0)
        });

        for (uint i = 0; i < validatorData.length; i++) {
            bytes memory withdrawalCredentials = stakingNodesManager.getWithdrawalCredentials(validatorData[i].nodeId);
            uint amount = depositAmount / validatorData.length;
            bytes32 depositDataRoot = stakingNodesManager.generateDepositRoot(validatorData[i].publicKey, validatorData[i].signature, withdrawalCredentials, amount);
            validatorData[i].depositDataRoot = depositDataRoot;
        }
        
        vm.prank(actors.ops.VALIDATOR_MANAGER);
        stakingNodesManager.registerValidators(validatorData);

        uint totalAssetsControlled = yneth.totalAssets();
        assertEq(totalAssetsControlled, depositAmount, "Total assets controlled does not match expected value");

        StakingNodesManager.Validator[] memory registeredValidators = stakingNodesManager.getAllValidators();
        assertEq(registeredValidators.length, validatorCount, "Incorrect number of registered validators");

        for (uint i = 0; i < registeredValidators.length; i++) {
            assertEq(registeredValidators[i].publicKey, validatorData[i].publicKey, "Validator public key does not match");
            assertEq(registeredValidators[i].nodeId, validatorData[i].nodeId, "Validator node ID does not match");
        }
    }

    function testRegisterValidatorsWithZeroValidators() public {
        // Attempt to register with an empty array of validators
        IStakingNodesManager.ValidatorData[] memory validatorData = new IStakingNodesManager.ValidatorData[](0);
        vm.prank(actors.ops.VALIDATOR_MANAGER);
        vm.expectRevert(StakingNodesManager.NoValidatorsProvided.selector);
        stakingNodesManager.registerValidators(validatorData);
    }

    function testRegisterValidatorsWithInvalidNodeId() public {
        // Attempt to register validators with an invalid node ID
        IStakingNodesManager.ValidatorData[] memory validatorData = new IStakingNodesManager.ValidatorData[](1);
        validatorData[0] = IStakingNodesManager.ValidatorData({
            publicKey: ONE_PUBLIC_KEY,
            signature: ZERO_SIGNATURE,
            nodeId: 999, // Assuming 999 is an invalid node ID
            depositDataRoot: bytes32(0)
        });

        vm.prank(actors.ops.VALIDATOR_MANAGER);
        vm.expectRevert(
            abi.encodeWithSelector(
                StakingNodesManager.InvalidNodeId.selector,
                999
            )
        );
        stakingNodesManager.registerValidators(validatorData);
    }

    function testRegisterValidatorsWithDuplicatePublicKey() public {

        address addr1 = vm.addr(100);

        vm.deal(addr1, 100 ether);

        uint validatorCount = 2;

        uint depositAmount = 32 ether * validatorCount;
        vm.prank(addr1);
        yneth.depositETH{value: depositAmount}(addr1);

        vm.prank(actors.ops.STAKING_NODE_CREATOR);
        stakingNodesManager.createStakingNode();
        // Attempt to register validators with a duplicate public key
        IStakingNodesManager.ValidatorData[] memory validatorData = new IStakingNodesManager.ValidatorData[](2);
        validatorData[0] = IStakingNodesManager.ValidatorData({
            publicKey: ONE_PUBLIC_KEY,
            signature: ZERO_SIGNATURE,
            nodeId: 0,
            depositDataRoot: bytes32(0)
        });
        validatorData[1] = IStakingNodesManager.ValidatorData({
            publicKey: ONE_PUBLIC_KEY, // Duplicate public key
            signature: ZERO_SIGNATURE,
            nodeId: 0,
            depositDataRoot: bytes32(0)
        });


        for (uint i = 0; i < validatorData.length; i++) {
            bytes memory withdrawalCredentials = stakingNodesManager.getWithdrawalCredentials(validatorData[i].nodeId);
            uint amount = depositAmount / validatorData.length;
            bytes32 depositDataRoot = stakingNodesManager.generateDepositRoot(validatorData[i].publicKey, validatorData[i].signature, withdrawalCredentials, amount);
            validatorData[i].depositDataRoot = depositDataRoot;
        }

        vm.prank(actors.ops.VALIDATOR_MANAGER);
        vm.expectRevert(abi.encodeWithSelector(StakingNodesManager.ValidatorAlreadyUsed.selector, ONE_PUBLIC_KEY) );
        stakingNodesManager.registerValidators(validatorData);
    }

    function testRegisterValidatorsWithInsufficientDeposit() public {
        address addr1 = vm.addr(100);
        vm.deal(addr1, 100 ether);
        uint depositAmount = 16 ether; // Insufficient deposit amount
        vm.prank(addr1);
        yneth.depositETH{value: depositAmount}(addr1);

        vm.prank(actors.ops.STAKING_NODE_CREATOR);
        stakingNodesManager.createStakingNode();
        // Attempt to register a validator with insufficient deposit
        IStakingNodesManager.ValidatorData[] memory validatorData = new IStakingNodesManager.ValidatorData[](1);
        validatorData[0] = IStakingNodesManager.ValidatorData({
            publicKey: ONE_PUBLIC_KEY,
            signature: ZERO_SIGNATURE,
            nodeId: 0,
            depositDataRoot: bytes32(0)
        });

        for (uint i = 0; i < validatorData.length; i++) {
            bytes memory withdrawalCredentials = stakingNodesManager.getWithdrawalCredentials(validatorData[i].nodeId);
            uint amount = depositAmount / validatorData.length;
            bytes32 depositDataRoot = stakingNodesManager.generateDepositRoot(validatorData[i].publicKey, validatorData[i].signature, withdrawalCredentials, amount);
            validatorData[i].depositDataRoot = depositDataRoot;
        }

        vm.prank(actors.ops.VALIDATOR_MANAGER);
        vm.expectRevert(abi.encodeWithSelector(ynETH.InsufficientBalance.selector));
        stakingNodesManager.registerValidators(validatorData);
    }

    function testRegisterValidatorsWithExceedingMaxNodeCount() public {
        address addr1 = vm.addr(100);
        vm.deal(addr1, 100 ether);
        uint validatorCount = 1;
        uint depositAmount = 32 ether * validatorCount;
        vm.prank(addr1);
        yneth.depositETH{value: depositAmount}(addr1);

        // Create nodes up to the max node count
        uint256 maxNodeCount = stakingNodesManager.maxNodeCount();
        for (uint256 i = 0; i < maxNodeCount; i++) {
            vm.prank(actors.ops.STAKING_NODE_CREATOR);
            stakingNodesManager.createStakingNode();
        }

        // Attempt to register a validator when max node count is reached
        IStakingNodesManager.ValidatorData[] memory validatorData = new IStakingNodesManager.ValidatorData[](1);
        validatorData[0] = IStakingNodesManager.ValidatorData({
            publicKey: ONE_PUBLIC_KEY,
            signature: ZERO_SIGNATURE,
            nodeId: uint256(maxNodeCount), // Node ID equal to max node count
            depositDataRoot: bytes32(0)
        });

        vm.prank(actors.ops.VALIDATOR_MANAGER);
        vm.expectRevert(abi.encodeWithSelector(StakingNodesManager.InvalidNodeId.selector, maxNodeCount));
        stakingNodesManager.registerValidators(validatorData);
    } 
}

contract StakingNodesManagerViews is IntegrationBaseTest {

    function testGetAllNodes() public {

        IStakingNode[] memory expectedNodes = new IStakingNode[](2);
        vm.prank(actors.ops.STAKING_NODE_CREATOR);
        expectedNodes[0] = stakingNodesManager.createStakingNode();

        vm.prank(actors.ops.STAKING_NODE_CREATOR);
        expectedNodes[1] = stakingNodesManager.createStakingNode();

        IStakingNode[] memory nodes = stakingNodesManager.getAllNodes();
        assertEq(nodes.length, expectedNodes.length, "Incorrect number of nodes returned");
        for (uint i = 0; i < nodes.length; i++) {
            assertTrue(address(nodes[i]) == address(expectedNodes[i]), "Node address does not match");
        }
    }

    function testNodesLength() public {
       IStakingNode[] memory expectedNodes = new IStakingNode[](3);
        vm.prank(actors.ops.STAKING_NODE_CREATOR);
        expectedNodes[0] = stakingNodesManager.createStakingNode();

        vm.prank(actors.ops.STAKING_NODE_CREATOR);
        expectedNodes[1] = stakingNodesManager.createStakingNode();

        vm.prank(actors.ops.STAKING_NODE_CREATOR);
        expectedNodes[2] = stakingNodesManager.createStakingNode();

        uint256 length = stakingNodesManager.nodesLength();
        assertEq(length, expectedNodes.length, "Nodes length does not match expected value");
    }

    function testIsStakingNodesOperator() public {

        bool isAdmin = stakingNodesManager.isStakingNodesOperator(actors.ops.STAKING_NODES_OPERATOR);
        assertTrue(isAdmin, "Address should be an admin");

        address nonOperatorAddress = vm.addr(9999);
        isAdmin = stakingNodesManager.isStakingNodesOperator(nonOperatorAddress);
        assertFalse(isAdmin, "Address should not be an admin");
    }
}


contract StakingNodesManagerValidators is IntegrationBaseTest {

    function makeTestValidators(uint256 _depositAmount) public returns(IStakingNodesManager.ValidatorData[] memory validatorData, uint256 validatorCount) {
        address addr1 = vm.addr(100);
        vm.deal(addr1, 100 ether);
        validatorCount = 3;
        uint256 depositAmount = _depositAmount * validatorCount;
        vm.prank(addr1);
        yneth.depositETH{value: depositAmount}(addr1);
        
        vm.prank(actors.ops.STAKING_NODE_CREATOR);
        stakingNodesManager.createStakingNode();

        vm.prank(actors.ops.STAKING_NODE_CREATOR);
        stakingNodesManager.createStakingNode();

        vm.prank(actors.ops.STAKING_NODE_CREATOR);
        stakingNodesManager.createStakingNode();

        validatorData = new IStakingNodesManager.ValidatorData[](validatorCount);

        validatorData[0] = IStakingNodesManager.ValidatorData({
            publicKey: ZERO_PUBLIC_KEY,
            signature: ZERO_SIGNATURE,
            nodeId: 0,
            depositDataRoot: bytes32(0)
        });
        validatorData[1] = IStakingNodesManager.ValidatorData({
            publicKey: ONE_PUBLIC_KEY,
            signature: ZERO_SIGNATURE,
            nodeId: 1,
            depositDataRoot: bytes32(0)
        });

       validatorData[2] = IStakingNodesManager.ValidatorData({
            publicKey: TWO_PUBLIC_KEY,
            signature: ZERO_SIGNATURE,
            nodeId: 2,
            depositDataRoot: bytes32(0)
        });

        for (uint256 i = 0; i < validatorData.length; i++) {
            bytes memory withdrawalCredentials = stakingNodesManager.getWithdrawalCredentials(validatorData[i].nodeId);
            uint256 amount = depositAmount / validatorData.length;
            bytes32 depositDataRoot = stakingNodesManager.generateDepositRoot(
                validatorData[i].publicKey, 
                validatorData[i].signature, 
                withdrawalCredentials, amount
            );
            validatorData[i].depositDataRoot = depositDataRoot;
        }
    }

    function testRegisterValidatorDepositDataRootMismatch() public {
        uint256 depositAmount = 33 ether;
        (IStakingNodesManager.ValidatorData[] memory validatorData,) = makeTestValidators(depositAmount);
        // try to create a bad deposit root
        bytes memory withdrawalCredentials = stakingNodesManager.getWithdrawalCredentials(validatorData[0].nodeId);

        bytes32 depositDataRoot = stakingNodesManager.generateDepositRoot(
            validatorData[0].publicKey, 
            validatorData[0].signature, 
            withdrawalCredentials, 32 ether
        );
        vm.prank(actors.ops.VALIDATOR_MANAGER);
        vm.expectRevert(abi.encodeWithSelector(
            StakingNodesManager.DepositDataRootMismatch.selector, 
            depositDataRoot, 
            validatorData[0].depositDataRoot)
        );
        stakingNodesManager.registerValidators(validatorData);
    }

    function testRegisterValidatorSuccess() public {
        (IStakingNodesManager.ValidatorData[] memory validatorData, uint256 validatorCount) = makeTestValidators(32 ether);
        // Call validateDepositDataAllocation to ensure the deposit data allocation ßis valid
        stakingNodesManager.validateNodes(validatorData);
        
        vm.prank(actors.ops.VALIDATOR_MANAGER);
        stakingNodesManager.registerValidators(validatorData);

        StakingNodesManager.Validator[] memory registeredValidators = stakingNodesManager.getAllValidators();
        assertEq(registeredValidators.length, validatorCount, "Incorrect number of registered validators");    
    }

    function testGenerateWithdrawalCredentials() public {
        makeTestValidators(32 ether);

        bytes memory withdrawalCredentials = stakingNodesManager.generateWithdrawalCredentials(actors.ops.VALIDATOR_MANAGER);
        assertEq(withdrawalCredentials.length, 32, "Withdrawal credentials length does not match expected value");
    }
    
    function testValidatorRegistrationPaused() public {
        uint256 depositAmount = 32 ether;
        (IStakingNodesManager.ValidatorData[] memory validatorData,) = makeTestValidators(depositAmount);

        // Pause validator registration
        vm.prank(actors.ops.PAUSE_ADMIN);
        stakingNodesManager.pauseValidatorRegistration();

        // Attempt to register validators while paused
        vm.prank(actors.ops.VALIDATOR_MANAGER);
        vm.expectRevert(StakingNodesManager.ValidatorRegistrationPaused.selector);
        stakingNodesManager.registerValidators(validatorData);

        // Unpause validator registration
        vm.prank(actors.admin.UNPAUSE_ADMIN);
        stakingNodesManager.unpauseValidatorRegistration();

        // Attempt to register validators after unpausing
        vm.prank(actors.ops.VALIDATOR_MANAGER);
        stakingNodesManager.registerValidators(validatorData);
        assertEq(stakingNodesManager.getAllValidators().length, validatorData.length, "Validators were not registered after unpausing");
    }
}

contract StakingNodeManagerWithdrawals is StakingNodeTestBase {

    uint256 constant STAKING_NODE_COUNT = 3;
    uint256 constant VALIDATORS_PER_NODE = 5;

    struct NodeData {
        uint40[] validatorIndices;
    }
    
    mapping(uint256 => NodeData) internal nodeData;

    function setUp() public override {
        super.setUp();

        // Create STAKING_NODE_COUNT StakingNodes
        for (uint i = 0; i < STAKING_NODE_COUNT; i++) {
            vm.prank(actors.ops.STAKING_NODE_CREATOR);
            stakingNodesManager.createStakingNode();
        }

        // Deposit 1000 ETH to ynETH
        address depositor = vm.addr(100);
        vm.deal(depositor, 1000 ether);
        vm.prank(depositor);
        yneth.depositETH{value: 1000 ether}(depositor);


        // Create an array of nodeIds
        uint256[] memory nodeIds = new uint256[](STAKING_NODE_COUNT);
        for (uint nodeId = 0; nodeId < STAKING_NODE_COUNT; nodeId++) {
            nodeIds[nodeId] = nodeId;
        }


        uint40[] memory allValidatorIndices = createValidators(nodeIds, VALIDATORS_PER_NODE);
        uint256[] memory assignedNodeIds = new uint256[](STAKING_NODE_COUNT * VALIDATORS_PER_NODE);
        
        // Register validators for each staking node
        for (uint nodeId = 0; nodeId < STAKING_NODE_COUNT; nodeId++) {
            nodeData[nodeId].validatorIndices = new uint40[](VALIDATORS_PER_NODE);
            for (uint i = 0; i < VALIDATORS_PER_NODE; i++) {
                nodeData[nodeId].validatorIndices[i] = allValidatorIndices[nodeId * VALIDATORS_PER_NODE + i];

                //assignedNodeIds[nodeId * VALIDATORS_PER_NODE + i] = nodeId;
            }
        }
        beaconChain.advanceEpoch_NoRewards();
        registerValidators(assignedNodeIds);

        // Verify that STAKING_NODE_COUNT * VALIDATORS_PER_NODE validators were registered in total
        assertEq(stakingNodesManager.getAllValidators().length, STAKING_NODE_COUNT * VALIDATORS_PER_NODE, "Incorrect number of registered validators");
    }

    function exitValidatorsAndAccumulateRewards(
        uint256 nodeId,
        uint256 exitCount,
        uint256 epochsToAdvance
    ) internal returns (uint256 accumulatedRewards) {

        // Advance epochs and accumulate rewards
        for (uint256 i = 0; i < epochsToAdvance; i++) {
            beaconChain.advanceEpoch();
        }
        accumulatedRewards = epochsToAdvance * VALIDATORS_PER_NODE * 1e9; // 1 GWEI per Epoch per Validator;

        // Exit validators
        uint256[] memory exitedValidatorIndices = new uint256[](exitCount);
        for (uint256 i = 0; i < exitCount; i++) {
            exitedValidatorIndices[i] = nodeData[nodeId].validatorIndices[i];
        }
 
        
    }

    function testProcessWithdrawnETH() public {
        address addr1 = vm.addr(100);
        vm.deal(addr1, 100 ether);
        uint256 depositAmount = 32 ether;
        vm.prank(addr1);
        yneth.depositETH{value: depositAmount}(addr1);
        vm.prank(actors.ops.STAKING_NODE_CREATOR);
        stakingNodesManager.createStakingNode();
        vm.expectRevert(abi.encodeWithSelector(StakingNodesManager.NotStakingNode.selector, actors.ops.STAKING_NODE_CREATOR, 0));
        vm.prank(actors.ops.STAKING_NODE_CREATOR);
        stakingNodesManager.processRewards(0, RewardsType.ConsensusLayer);
    }

    function testProcessPrincipalWithdrawalsForThreeNodes() public {
        // Prepare withdrawal actions
        StakingNodesManager.WithdrawalAction[] memory actions = new StakingNodesManager.WithdrawalAction[](3);
        actions[0] = IStakingNodesManager.WithdrawalAction(0, 100 ether, 50 ether, 10 ether);
        actions[1] = IStakingNodesManager.WithdrawalAction(1, 150 ether, 75 ether, 15 ether);
        actions[2] = IStakingNodesManager.WithdrawalAction(2, 200 ether, 100 ether, 20 ether);

        // Record balances before processing withdrawals
        uint256 ynETHBalanceBefore = address(yneth).balance;
        uint256 withdrawalQueueBalanceBefore = address(ynETHWithdrawalQueueManager).balance;

        // Process principal withdrawals
        vm.prank(actors.ops.WITHDRAWAL_MANAGER);
        stakingNodesManager.processPrincipalWithdrawals(actions);

        // Verify balances after processing withdrawals
        uint256 ynETHBalanceAfter = address(yneth).balance;
        uint256 withdrawalQueueBalanceAfter = address(ynETHWithdrawalQueueManager).balance;

        assertEq(ynETHBalanceAfter - ynETHBalanceBefore, 325 ether, "Incorrect amount reinvested in ynETH");
        assertEq(withdrawalQueueBalanceAfter - withdrawalQueueBalanceBefore, 225 ether, "Incorrect amount sent to withdrawal queue");

        // Verify that rewards were processed correctly
        uint256 totalRewards = 45 ether;
        assertEq(address(rewardsDistributor).balance, totalRewards, "Incorrect amount of rewards processed");
    }


}

contract StakingNodesManagerMisc is IntegrationBaseTest {

    function testSendingETHToStakingNodesManagerShouldNotRevert() public {
        uint256 amountToSend = 1 ether;

        // Send ETH to the StakingNodesManager contract
        (bool sent, ) = address(stakingNodesManager).call{value: amountToSend}("");
        assertTrue(sent, "ETH transfer failed");
        assertEq(address(stakingNodesManager).balance, amountToSend, "Balance of StakingNodesManager incorrect after receiving ETH");

    }
}