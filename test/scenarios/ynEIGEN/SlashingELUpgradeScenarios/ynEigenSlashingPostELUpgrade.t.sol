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
 * @title YnEigenPostEigenLayerUpgradeTest
 * @notice Tests for ynEigen functionality after EigenLayer upgrade but before ynEigen upgrade
 */
contract YnEigenPostEigenLayerUpgradeTest is ynEigenSlashingTestBase {
    
    function setUp() public override {
        super.setUp();
        upgradeEigenlayerContracts();
        // Any additional setup specific to post-EigenLayer upgrade state
    }
    
    /**
     * @notice Tests deposit functionality after EigenLayer upgrade but before ynEigen upgrade
     */
    function testDepositAfterEigenlayerUpgradeBeforeYnEigenUpgrade() public {
        // This may revert due to incompatibility with new EigenLayer interfaces
        vm.expectRevert();
        eigenStrategyManager.updateTokenStakingNodesBalances(wstETH);
        
        // Deposit should still work despite incompatibility
        uint256 depositAmount = 10 ether;
        YnEigenStateSnapshot memory beforeState = takeYnEigenStateSnapshot();
        TokenStakingNodeStateSnapshot[] memory nodeStatesBefore = takeTokenStakingNodesStateSnapshot();
        
        vm.startPrank(user);
        wstETH.approve(address(ynEigen), depositAmount);
        uint256 sharesBefore = ynEigen.balanceOf(user);
        ynEigen.deposit(wstETH, depositAmount, user);
        uint256 sharesReceived = ynEigen.balanceOf(user) - sharesBefore;
        vm.stopPrank();
        
        YnEigenStateSnapshot memory afterState = takeYnEigenStateSnapshot();
        TokenStakingNodeStateSnapshot[] memory nodeStatesAfter = takeTokenStakingNodesStateSnapshot();
        
        // Verify basic accounting still works
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
        
        assertEq(afterState.rate, beforeState.rate, "rate changed unexpectedly");
        
        // Node states should be unchanged since they can't sync correctly
        verifyNodeStatesUnchanged(nodeStatesBefore, nodeStatesAfter);
    }
    
    /**
     * @notice Tests that synchronize function reverts after EigenLayer upgrade but before ynEigen upgrade
     */
    function testSynchronizeRevertsAfterEigenlayerUpgradeBeforeYnEigenUpgrade() public {
        // Add implementation for this test
        ITokenStakingNode[] memory nodes = tokenStakingNodesManager.getAllNodes();
        for (uint256 i = 0; i < nodes.length; i++) {
            vm.expectRevert();
            vm.prank(admin);
            nodes[i].synchronize();
        }
    }
}