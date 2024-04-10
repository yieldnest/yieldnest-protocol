// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;
import {IntegrationBaseTest} from "./IntegrationBaseTest.sol";
import {StakingNodesManager} from "src/StakingNodesManager.sol";
import {ynETH} from "src/ynETH.sol";
import {ynLSD} from "src/ynLSD.sol";
import {YieldNestOracle} from "src/YieldNestOracle.sol";
import {MockYnETHERC4626} from "test/mocks/MockYnETHERC4626.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {RewardsDistributor} from "src/RewardsDistributor.sol";
import {ProxyAdmin} from "lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {IRewardsDistributor} from "src/interfaces/IRewardsDistributor.sol";
import {IStakingNodesManager} from "src/interfaces/IStakingNodesManager.sol";
import {IStrategy} from "src/external/eigenlayer/v0.1.0/interfaces/IStrategy.sol";
import {TransparentUpgradeableProxy} from "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ITransparentUpgradeableProxy} from "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {TestStakingNodesManagerV2} from "test/mocks/TestStakingNodesManagerV2.sol";

contract RolesTest is IntegrationBaseTest {

    function testRoleChangeYnETH() public {
        address newOperator = address(0x123);
        bytes32 ADMIN_ROLE = keccak256("ADMIN_ROLE");
        bytes32 PAUSER_ROLE = keccak256("PAUSER_ROLE");
        bytes32 STAKING_NODES_MANAGER_ROLE = keccak256("STAKING_NODES_MANAGER_ROLE");
        bytes32 REWARDS_DISTRIBUTOR_ROLE = keccak256("REWARDS_DISTRIBUTOR_ROLE");

        assertTrue(stakingNodesManager.hasRole(stakingNodesManager.DEFAULT_ADMIN_ROLE(), actors.ADMIN));
        assertTrue(stakingNodesManager.hasRole(PAUSER_ROLE, actors.PAUSE_ADMIN));

        vm.startPrank(actors.ADMIN);
        yneth.grantRole(PAUSER_ROLE, newOperator);
        yneth.revokeRole(PAUSER_ROLE, actors.PAUSE_ADMIN);
        vm.stopPrank();

        assertTrue(yneth.hasRole(PAUSER_ROLE, newOperator));
    }

    function testRoleChangeStakingNodesManager() public {
        address newOperator = address(0x456);
        bytes32 STAKING_ADMIN_ROLE = keccak256("STAKING_ADMIN_ROLE");
        bytes32 VALIDATOR_MANAGER_ROLE = keccak256("VALIDATOR_MANAGER_ROLE");
        bytes32 STAKING_NODES_ADMIN_ROLE = keccak256("STAKING_NODES_ADMIN_ROLE");
        bytes32 STAKING_NODE_CREATOR_ROLE = keccak256("STAKING_NODE_CREATOR_ROLE");
        bytes32 PAUSER_ROLE = keccak256("PAUSER_ROLE");

        assertTrue(stakingNodesManager.hasRole(stakingNodesManager.DEFAULT_ADMIN_ROLE(), actors.ADMIN));
        assertTrue(stakingNodesManager.hasRole(STAKING_ADMIN_ROLE, actors.STAKING_ADMIN));
        assertTrue(stakingNodesManager.hasRole(VALIDATOR_MANAGER_ROLE, actors.VALIDATOR_MANAGER));
        assertTrue(stakingNodesManager.hasRole(STAKING_NODES_ADMIN_ROLE, actors.STAKING_NODES_ADMIN));
        assertTrue(stakingNodesManager.hasRole(STAKING_NODE_CREATOR_ROLE, actors.STAKING_NODE_CREATOR));
        assertTrue(stakingNodesManager.hasRole(PAUSER_ROLE, actors.PAUSE_ADMIN));

        vm.startPrank(actors.ADMIN);
        stakingNodesManager.grantRole(STAKING_ADMIN_ROLE, newOperator);
        stakingNodesManager.revokeRole(STAKING_ADMIN_ROLE, actors.STAKING_ADMIN);

        stakingNodesManager.grantRole(VALIDATOR_MANAGER_ROLE, newOperator);
        stakingNodesManager.revokeRole(VALIDATOR_MANAGER_ROLE, actors.VALIDATOR_MANAGER);

        stakingNodesManager.grantRole(STAKING_NODES_ADMIN_ROLE, newOperator);
        stakingNodesManager.revokeRole(STAKING_NODES_ADMIN_ROLE, actors.STAKING_NODES_ADMIN);

        stakingNodesManager.grantRole(STAKING_NODE_CREATOR_ROLE, newOperator);
        stakingNodesManager.revokeRole(STAKING_NODE_CREATOR_ROLE, actors.STAKING_NODE_CREATOR);

        stakingNodesManager.grantRole(PAUSER_ROLE, newOperator);
        stakingNodesManager.revokeRole(PAUSER_ROLE, actors.PAUSE_ADMIN);
        vm.stopPrank();

        assertTrue(stakingNodesManager.hasRole(STAKING_ADMIN_ROLE, newOperator));
        assertTrue(stakingNodesManager.hasRole(VALIDATOR_MANAGER_ROLE, newOperator));
        assertTrue(stakingNodesManager.hasRole(STAKING_NODES_ADMIN_ROLE, newOperator));
        assertTrue(stakingNodesManager.hasRole(STAKING_NODE_CREATOR_ROLE, newOperator));
        assertTrue(stakingNodesManager.hasRole(PAUSER_ROLE, newOperator));

        assertFalse(stakingNodesManager.hasRole(STAKING_ADMIN_ROLE, actors.STAKING_ADMIN));
        assertFalse(stakingNodesManager.hasRole(VALIDATOR_MANAGER_ROLE, actors.VALIDATOR_MANAGER));
        assertFalse(stakingNodesManager.hasRole(STAKING_NODES_ADMIN_ROLE, actors.STAKING_NODES_ADMIN));
        assertFalse(stakingNodesManager.hasRole(STAKING_NODE_CREATOR_ROLE, actors.STAKING_NODE_CREATOR));
        assertFalse(stakingNodesManager.hasRole(PAUSER_ROLE, actors.PAUSE_ADMIN));
    }

    function testRoleChangeRewardsDistributor() public {
        // TODO: add after fixing roles in RewardsDistributor.sol
    }

    function testRoleChangeYnLSD() public {
        address newStakingAdmin = address(0xABC);
        bytes32 STAKING_ADMIN_ROLE = keccak256("STAKING_ADMIN_ROLE");
        bytes32 LSD_RESTAKING_MANAGER_ROLE = keccak256("LSD_RESTAKING_MANAGER_ROLE");
        bytes32 LSD_STAKING_NODE_CREATOR_ROLE = keccak256("LSD_STAKING_NODE_CREATOR_ROLE");

        assertTrue(ynlsd.hasRole(ynlsd.DEFAULT_ADMIN_ROLE(), actors.ADMIN));
        assertTrue(ynlsd.hasRole(STAKING_ADMIN_ROLE, actors.STAKING_ADMIN));
        assertTrue(ynlsd.hasRole(LSD_RESTAKING_MANAGER_ROLE, actors.LSD_RESTAKING_MANAGER));
        assertTrue(ynlsd.hasRole(LSD_STAKING_NODE_CREATOR_ROLE, actors.STAKING_NODE_CREATOR));

        vm.startPrank(actors.ADMIN);
        ynlsd.grantRole(STAKING_ADMIN_ROLE, newStakingAdmin);
        ynlsd.revokeRole(STAKING_ADMIN_ROLE, actors.STAKING_ADMIN);
        ynlsd.grantRole(LSD_RESTAKING_MANAGER_ROLE, newStakingAdmin);
        ynlsd.revokeRole(LSD_RESTAKING_MANAGER_ROLE, actors.LSD_RESTAKING_MANAGER);
        ynlsd.grantRole(LSD_STAKING_NODE_CREATOR_ROLE, newStakingAdmin);
        ynlsd.revokeRole(LSD_STAKING_NODE_CREATOR_ROLE, actors.STAKING_NODE_CREATOR);
        vm.stopPrank();

        assertTrue(ynlsd.hasRole(STAKING_ADMIN_ROLE, newStakingAdmin));
        assertTrue(ynlsd.hasRole(LSD_RESTAKING_MANAGER_ROLE, newStakingAdmin));
        assertTrue(ynlsd.hasRole(LSD_STAKING_NODE_CREATOR_ROLE, newStakingAdmin));
        assertFalse(ynlsd.hasRole(STAKING_ADMIN_ROLE, actors.STAKING_ADMIN));
        assertFalse(ynlsd.hasRole(LSD_RESTAKING_MANAGER_ROLE, actors.LSD_RESTAKING_MANAGER));
        assertFalse(ynlsd.hasRole(LSD_STAKING_NODE_CREATOR_ROLE, actors.STAKING_NODE_CREATOR));
    }

    function testRoleChangeYieldNestOracle() public {
        address newOracleAdmin = address(0xDEF);
        bytes32 ORACLE_MANAGER_ROLE = keccak256("ORACLE_MANAGER_ROLE");

        assertTrue(yieldNestOracle.hasRole(yieldNestOracle.DEFAULT_ADMIN_ROLE(), actors.ADMIN));
        assertTrue(yieldNestOracle.hasRole(ORACLE_MANAGER_ROLE, actors.ORACLE_MANAGER));

        vm.startPrank(actors.ADMIN);
        yieldNestOracle.grantRole(ORACLE_MANAGER_ROLE, newOracleAdmin);
        yieldNestOracle.revokeRole(ORACLE_MANAGER_ROLE, actors.ORACLE_MANAGER);
        vm.stopPrank();

        assertTrue(yieldNestOracle.hasRole(ORACLE_MANAGER_ROLE, newOracleAdmin));
        assertFalse(yieldNestOracle.hasRole(ORACLE_MANAGER_ROLE, actors.ORACLE_MANAGER));
    }
}


