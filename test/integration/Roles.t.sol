// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;
import {IntegrationBaseTest} from "test/integration/IntegrationBaseTest.sol";
import {ynETH} from "src/ynETH.sol";
import {RewardsDistributor} from "src/RewardsDistributor.sol";
import {IAccessControl} from "lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";

contract RolesTest is IntegrationBaseTest {

    function testRoleChangeYnETH() public {
        address newOperator = address(0x123);
        bytes32 PAUSER_ROLE = keccak256("PAUSER_ROLE");

        assertTrue(stakingNodesManager.hasRole(stakingNodesManager.DEFAULT_ADMIN_ROLE(), actors.admin.ADMIN));
        assertTrue(stakingNodesManager.hasRole(PAUSER_ROLE, actors.ops.PAUSE_ADMIN));

        vm.startPrank(actors.admin.ADMIN);
        yneth.grantRole(PAUSER_ROLE, newOperator);
        yneth.revokeRole(PAUSER_ROLE, actors.ops.PAUSE_ADMIN);
        vm.stopPrank();

        assertTrue(yneth.hasRole(PAUSER_ROLE, newOperator));
    }

    function testRoleChangeStakingNodesManager() public {
        address newOperator = address(0x456);
        bytes32 STAKING_ADMIN_ROLE = keccak256("STAKING_ADMIN_ROLE");
        bytes32 VALIDATOR_MANAGER_ROLE = keccak256("VALIDATOR_MANAGER_ROLE");
        bytes32 STAKING_NODES_OPERATOR_ROLE = keccak256("STAKING_NODES_OPERATOR_ROLE");
        bytes32 STAKING_NODE_CREATOR_ROLE = keccak256("STAKING_NODE_CREATOR_ROLE");
        bytes32 PAUSER_ROLE = keccak256("PAUSER_ROLE");

        assertTrue(stakingNodesManager.hasRole(stakingNodesManager.DEFAULT_ADMIN_ROLE(), actors.admin.ADMIN));
        assertTrue(stakingNodesManager.hasRole(STAKING_ADMIN_ROLE, actors.admin.STAKING_ADMIN));
        assertTrue(stakingNodesManager.hasRole(VALIDATOR_MANAGER_ROLE, actors.ops.VALIDATOR_MANAGER));
        assertTrue(stakingNodesManager.hasRole(STAKING_NODES_OPERATOR_ROLE, actors.ops.STAKING_NODES_OPERATOR));
        assertTrue(stakingNodesManager.hasRole(STAKING_NODE_CREATOR_ROLE, actors.ops.STAKING_NODE_CREATOR));
        assertTrue(stakingNodesManager.hasRole(PAUSER_ROLE, actors.ops.PAUSE_ADMIN));

        vm.startPrank(actors.admin.ADMIN);
        stakingNodesManager.grantRole(STAKING_ADMIN_ROLE, newOperator);
        stakingNodesManager.revokeRole(STAKING_ADMIN_ROLE, actors.admin.STAKING_ADMIN);

        stakingNodesManager.grantRole(VALIDATOR_MANAGER_ROLE, newOperator);
        stakingNodesManager.revokeRole(VALIDATOR_MANAGER_ROLE, actors.ops.VALIDATOR_MANAGER);

        stakingNodesManager.grantRole(STAKING_NODES_OPERATOR_ROLE, newOperator);
        stakingNodesManager.revokeRole(STAKING_NODES_OPERATOR_ROLE, actors.ops.STAKING_NODES_OPERATOR);

        stakingNodesManager.grantRole(STAKING_NODE_CREATOR_ROLE, newOperator);
        stakingNodesManager.revokeRole(STAKING_NODE_CREATOR_ROLE, actors.ops.STAKING_NODE_CREATOR);

        stakingNodesManager.grantRole(PAUSER_ROLE, newOperator);
        stakingNodesManager.revokeRole(PAUSER_ROLE, actors.ops.PAUSE_ADMIN);
        vm.stopPrank();

        assertTrue(stakingNodesManager.hasRole(STAKING_ADMIN_ROLE, newOperator));
        assertTrue(stakingNodesManager.hasRole(VALIDATOR_MANAGER_ROLE, newOperator));
        assertTrue(stakingNodesManager.hasRole(STAKING_NODES_OPERATOR_ROLE, newOperator));
        assertTrue(stakingNodesManager.hasRole(STAKING_NODE_CREATOR_ROLE, newOperator));
        assertTrue(stakingNodesManager.hasRole(PAUSER_ROLE, newOperator));

        assertFalse(stakingNodesManager.hasRole(STAKING_ADMIN_ROLE, actors.admin.STAKING_ADMIN));
        assertFalse(stakingNodesManager.hasRole(VALIDATOR_MANAGER_ROLE, actors.ops.VALIDATOR_MANAGER));
        assertFalse(stakingNodesManager.hasRole(STAKING_NODES_OPERATOR_ROLE, actors.ops.STAKING_NODES_OPERATOR));
        assertFalse(stakingNodesManager.hasRole(STAKING_NODE_CREATOR_ROLE, actors.ops.STAKING_NODE_CREATOR));
        assertFalse(stakingNodesManager.hasRole(PAUSER_ROLE, actors.ops.PAUSE_ADMIN));
    }

    function testRoleChangeRewardsDistributor() public {
        address newRewardsAdmin = address(0x789);
        bytes32 REWARDS_ADMIN_ROLE = keccak256("REWARDS_ADMIN_ROLE");

        assertTrue(rewardsDistributor.hasRole(rewardsDistributor.DEFAULT_ADMIN_ROLE(), actors.admin.ADMIN));
        assertTrue(rewardsDistributor.hasRole(REWARDS_ADMIN_ROLE, actors.admin.REWARDS_ADMIN));

        vm.startPrank(actors.admin.ADMIN);
        rewardsDistributor.grantRole(REWARDS_ADMIN_ROLE, newRewardsAdmin);
        rewardsDistributor.revokeRole(REWARDS_ADMIN_ROLE, actors.admin.REWARDS_ADMIN);
        vm.stopPrank();

        assertTrue(rewardsDistributor.hasRole(REWARDS_ADMIN_ROLE, newRewardsAdmin));
        assertFalse(rewardsDistributor.hasRole(REWARDS_ADMIN_ROLE, actors.admin.REWARDS_ADMIN));
    }

    function testRewardsDistributorFeeAdminRoles() public {
        address payable newFeeReceiver = payable(address(0x789));
        bytes32 REWARDS_ADMIN_ROLE = keccak256("REWARDS_ADMIN_ROLE");

        vm.prank(actors.admin.REWARDS_ADMIN);
        rewardsDistributor.setFeesReceiver(newFeeReceiver);

        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), REWARDS_ADMIN_ROLE));
        rewardsDistributor.setFeesReceiver(newFeeReceiver);

        vm.prank(actors.admin.REWARDS_ADMIN);
        rewardsDistributor.setFeesBasisPoints(1000);

        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), REWARDS_ADMIN_ROLE));
        rewardsDistributor.setFeesBasisPoints(1000);
    }

    function testConsensusLayerRewardsReceiverRoles() public {
        address newRewardsDistributor = address(0x789);
        bytes32 WITHDRAWER_ROLE = keccak256("WITHDRAWER_ROLE");

        assertTrue(consensusLayerReceiver.hasRole(consensusLayerReceiver.DEFAULT_ADMIN_ROLE(), actors.admin.ADMIN));
        assertTrue(consensusLayerReceiver.hasRole(WITHDRAWER_ROLE, address(rewardsDistributor)));

        vm.startPrank(actors.admin.ADMIN);
        consensusLayerReceiver.grantRole(WITHDRAWER_ROLE, newRewardsDistributor);
        consensusLayerReceiver.revokeRole(WITHDRAWER_ROLE, address(rewardsDistributor));
        vm.stopPrank();

        assertTrue(consensusLayerReceiver.hasRole(WITHDRAWER_ROLE, newRewardsDistributor));
        assertFalse(consensusLayerReceiver.hasRole(WITHDRAWER_ROLE, address(rewardsDistributor)));
    }

    function testExecutionLayerRewardsReceiverRoles() public {
        address newRewardsDistributor = address(0x789);
        bytes32 WITHDRAWER_ROLE = keccak256("WITHDRAWER_ROLE");

        assertTrue(executionLayerReceiver.hasRole(executionLayerReceiver.DEFAULT_ADMIN_ROLE(), actors.admin.ADMIN));
        assertTrue(executionLayerReceiver.hasRole(WITHDRAWER_ROLE, address(rewardsDistributor)));

        vm.startPrank(actors.admin.ADMIN);
        executionLayerReceiver.grantRole(WITHDRAWER_ROLE, newRewardsDistributor);
        executionLayerReceiver.revokeRole(WITHDRAWER_ROLE, address(rewardsDistributor));
        vm.stopPrank();

        assertTrue(executionLayerReceiver.hasRole(WITHDRAWER_ROLE, newRewardsDistributor));
        assertFalse(executionLayerReceiver.hasRole(WITHDRAWER_ROLE, address(rewardsDistributor)));
    }    
    function testRoleChangeYnLSD() public {
        address newStakingAdmin = address(0xABC);
        bytes32 STAKING_ADMIN_ROLE = keccak256("STAKING_ADMIN_ROLE");
        bytes32 LSD_RESTAKING_MANAGER_ROLE = keccak256("LSD_RESTAKING_MANAGER_ROLE");
        bytes32 LSD_STAKING_NODE_CREATOR_ROLE = keccak256("LSD_STAKING_NODE_CREATOR_ROLE");

        assertTrue(ynlsd.hasRole(ynlsd.DEFAULT_ADMIN_ROLE(), actors.admin.ADMIN));
        assertTrue(ynlsd.hasRole(STAKING_ADMIN_ROLE, actors.admin.STAKING_ADMIN));
        assertTrue(ynlsd.hasRole(LSD_RESTAKING_MANAGER_ROLE, actors.ops.LSD_RESTAKING_MANAGER));
        assertTrue(ynlsd.hasRole(LSD_STAKING_NODE_CREATOR_ROLE, actors.ops.STAKING_NODE_CREATOR));

        vm.startPrank(actors.admin.ADMIN);
        ynlsd.grantRole(STAKING_ADMIN_ROLE, newStakingAdmin);
        ynlsd.revokeRole(STAKING_ADMIN_ROLE, actors.admin.STAKING_ADMIN);
        ynlsd.grantRole(LSD_RESTAKING_MANAGER_ROLE, newStakingAdmin);
        ynlsd.revokeRole(LSD_RESTAKING_MANAGER_ROLE, actors.ops.LSD_RESTAKING_MANAGER);
        ynlsd.grantRole(LSD_STAKING_NODE_CREATOR_ROLE, newStakingAdmin);
        ynlsd.revokeRole(LSD_STAKING_NODE_CREATOR_ROLE, actors.ops.STAKING_NODE_CREATOR);
        vm.stopPrank();

        assertTrue(ynlsd.hasRole(STAKING_ADMIN_ROLE, newStakingAdmin));
        assertTrue(ynlsd.hasRole(LSD_RESTAKING_MANAGER_ROLE, newStakingAdmin));
        assertTrue(ynlsd.hasRole(LSD_STAKING_NODE_CREATOR_ROLE, newStakingAdmin));
        assertFalse(ynlsd.hasRole(STAKING_ADMIN_ROLE, actors.admin.STAKING_ADMIN));
        assertFalse(ynlsd.hasRole(LSD_RESTAKING_MANAGER_ROLE, actors.ops.LSD_RESTAKING_MANAGER));
        assertFalse(ynlsd.hasRole(LSD_STAKING_NODE_CREATOR_ROLE, actors.ops.STAKING_NODE_CREATOR));
    }

    function testRoleChangeYieldNestOracle() public {
        address newOracleManager = address(0xDEF);
        bytes32 ORACLE_MANAGER_ROLE = keccak256("ORACLE_MANAGER_ROLE");

        assertTrue(yieldNestOracle.hasRole(yieldNestOracle.DEFAULT_ADMIN_ROLE(), actors.admin.ADMIN));
        assertTrue(yieldNestOracle.hasRole(ORACLE_MANAGER_ROLE, actors.admin.ORACLE_ADMIN));

        vm.startPrank(actors.admin.ADMIN);
        yieldNestOracle.grantRole(ORACLE_MANAGER_ROLE, newOracleManager);
        yieldNestOracle.revokeRole(ORACLE_MANAGER_ROLE, actors.admin.ORACLE_ADMIN);
        vm.stopPrank();

        assertTrue(yieldNestOracle.hasRole(ORACLE_MANAGER_ROLE, newOracleManager));
        assertFalse(yieldNestOracle.hasRole(ORACLE_MANAGER_ROLE, actors.admin.ORACLE_ADMIN));
    }
}


