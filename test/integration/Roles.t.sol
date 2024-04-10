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

    // function testRoleChangeYnETH() public {
    //     address newAdmin = address(0x123);
    //     vm.prank(actors.ADMIN);
    //     ynETH.updateAdmin(newAdmin);

    //     address currentAdmin = ynETH.admin();
    //     assertEq(currentAdmin, newAdmin);
    // }

    function testRoleChangeStakingNodesManager() public {
        address newOperator = address(0x456);
        bytes32 OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
        bytes32 STAKING_ADMIN_ROLE = keccak256("STAKING_ADMIN_ROLE");
        bytes32 VALIDATOR_MANAGER_ROLE = keccak256("VALIDATOR_MANAGER_ROLE");
        bytes32 STAKING_NODES_ADMIN_ROLE = keccak256("STAKING_NODES_ADMIN_ROLE");
        bytes32 STAKING_NODE_CREATOR_ROLE = keccak256("STAKING_NODE_CREATOR_ROLE");
        bytes32 PAUSER_ROLE = keccak256("PAUSER_ROLE");

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
    }

    // function testRoleChangeRewardsDistributor() public {
    //     address newDistributor = address(0x789);
    //     vm.prank(actors.DISTRIBUTOR);
    //     RewardsDistributor.updateDistributor(newDistributor);
        
    //     address currentDistributor = RewardsDistributor.distributor();
    //     assertEq(currentDistributor, newDistributor);
    // }

    // function testRoleChangeYnLSD() public {
    //     address newStrategyManager = address(0xABC);
    //     vm.prank(actors.STRATEGY_MANAGER);
    //     ynLSD.updateStrategyManager(newStrategyManager);
        
    //     address currentStrategyManager = ynLSD.strategyManager();
    //     assertEq(currentStrategyManager, newStrategyManager);
    // }

    // function testRoleChangeYieldNestOracle() public {
    //     address newOracleAdmin = address(0xDEF);
    //     vm.prank(actors.ORACLE_ADMIN);
    //     YieldNestOracle.updateAdmin(newOracleAdmin);
        
    //     address currentOracleAdmin = YieldNestOracle.admin();
    //     assertEq(currentOracleAdmin, newOracleAdmin);
    // }

    // function testRoleChangeStakingNodesManagerToV2() public {
    //     address newV2Operator = address(0x101112);
    //     vm.prank(actors.OPERATOR);
    //     TestStakingNodesManagerV2.updateOperator(newV2Operator);

    //     address currentV2Operator = TestStakingNodesManagerV2.operator();
    //     assertEq(currentV2Operator, newV2Operator);
    // }
}


