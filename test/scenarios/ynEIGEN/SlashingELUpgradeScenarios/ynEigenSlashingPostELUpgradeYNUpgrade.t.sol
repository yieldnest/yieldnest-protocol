// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {TokenStakingNodesManager} from "src/ynEIGEN/TokenStakingNodesManager.sol";
import {TokenStakingNode} from "src/ynEIGEN/TokenStakingNode.sol";
import {EigenStrategyManager} from "src/ynEIGEN/EigenStrategyManager.sol";
import {WithdrawalsProcessor} from "src/ynEIGEN/WithdrawalsProcessor.sol";
import {ITokenStakingNode} from "src/interfaces/ITokenStakingNode.sol";
import {ITokenStakingNodesManager} from "src/interfaces/ITokenStakingNodesManager.sol";
import {IynEigen} from "src/interfaces/IynEigen.sol";
import {IAssetRegistry} from "src/interfaces/IAssetRegistry.sol";
import {ProxyAdmin} from "lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {
    TransparentUpgradeableProxy,
    ITransparentUpgradeableProxy
} from "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {StorageSlot} from "lib/openzeppelin-contracts/contracts/utils/StorageSlot.sol";
import {IDelegationManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {DelegationManager} from "lib/eigenlayer-contracts/src/contracts/core/DelegationManager.sol";
import {AllocationManager} from "lib/eigenlayer-contracts/src/contracts/core/AllocationManager.sol";
import {IAllocationManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {UpgradeableBeacon} from "lib/openzeppelin-contracts/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {IPauserRegistry} from "lib/eigenlayer-contracts/src/contracts/interfaces/IPauserRegistry.sol";
import {IPermissionController} from "lib/eigenlayer-contracts/src/contracts/interfaces/IPermissionController.sol";
import {IStrategyManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IStrategy} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {Test, console2} from "forge-std/Test.sol";
import {ynEigenSlashingTestBase} from "./ynEigenSlashingTestBase.t.sol";

/**
 * @title YnEigenPostAllUpgradesTest
 * @notice Tests for ynEigen functionality after both EigenLayer and ynEigen upgrades
 */
contract YnEigenPostAllUpgradesTest is ynEigenSlashingTestBase {
    
    function setUp() public override {
        super.setUp();
        upgradeEigenlayerContracts();
        // Any additional setup specific to post-all-upgrades state
    }
    
    /**
     * @notice Tests deposit functionality after both EigenLayer and ynEigen upgrades
     */
    function testDepositAfterBothUpgrades() public {
        // Take snapshots before deposit
        YnEigenStateSnapshot memory beforeState = takeYnEigenStateSnapshot();
        TokenStakingNodeStateSnapshot[] memory nodeStatesBefore = takeTokenStakingNodesStateSnapshot();
        
        // All nodes should be synchronized after upgrade
        ITokenStakingNode[] memory nodes = tokenStakingNodesManager.getAllNodes();
        for (uint256 i = 0; i < nodes.length; i++) {
            assertTrue(nodes[i].isSynchronized(), "Node not synchronized after upgrade");
        }
        
        // Deposit after upgrade
        uint256 depositAmount = 10 ether;
        vm.startPrank(user);
        wstETH.approve(address(ynEigen), depositAmount);
        uint256 sharesBefore = ynEigen.balanceOf(user);
        ynEigen.deposit(wstETH, depositAmount, user);
        uint256 sharesReceived = ynEigen.balanceOf(user) - sharesBefore;
        vm.stopPrank();
        
        // Verify state changes
        YnEigenStateSnapshot memory afterState = takeYnEigenStateSnapshot();
        TokenStakingNodeStateSnapshot[] memory nodeStatesAfter = takeTokenStakingNodesStateSnapshot();
        
        assertEq(
            afterState.totalAssets,
            beforeState.totalAssets + convertToUnitOfAccount(wstETH, depositAmount),
            "totalAssets not changed correctly"
        );
        
        assertEq(
            afterState.totalSupply,
            beforeState.totalSupply + sharesReceived,
            "totalSupply not changed correctly"
        );
        
        // After upgrade, nodes need to check for proper migration of queued shares
        for (uint256 i = 0; i < nodeStatesBefore.length; i++) {
            // Legacy queued shares should now contain the old queued shares amount
            assertEq(
                nodeStatesBefore[i].queuedShares,
                nodeStatesAfter[i].legacyQueuedShares,
                "Legacy queued shares not set correctly"
            );
            
            // New queued shares should start at 0
            assertEq(
                nodeStatesAfter[i].queuedShares,
                0,
                "New queued shares not reset to 0"
            );
            
            // Delegation should remain unchanged
            assertEq(
                nodeStatesBefore[i].delegatedTo,
                nodeStatesAfter[i].delegatedTo,
                "delegatedTo changed unexpectedly"
            );
        }
    }
    
    /**
     * @notice Tests that node synchronization works correctly after both upgrades
     */
    function testNodeSynchronizationAfterBothUpgrades() public {
        ITokenStakingNode[] memory nodes = tokenStakingNodesManager.getAllNodes();
        
        // Test that synchronization now works properly
        for (uint256 i = 0; i < nodes.length; i++) {
            vm.prank(admin);
            nodes[i].synchronize();
            assertTrue(nodes[i].isSynchronized(), "Node failed to synchronize after upgrade");
        }
    }
}