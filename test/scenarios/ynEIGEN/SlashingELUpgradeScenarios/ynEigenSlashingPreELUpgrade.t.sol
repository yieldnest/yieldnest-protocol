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
 * @title YnEigenPreUpgradeTest
 * @notice Tests for ynEigen functionality before any upgrades are applied
 */
contract YnEigenPreUpgradeTest is ynEigenSlashingTestBase {
    
    function setUp() public override {
        super.setUp();
    }
    
    /**
     * @notice Tests deposit functionality before any upgrades
     */
    function testDepositBeforeSlashingUpgrade() public {
        // Start with a snapshot of the current state
        YnEigenStateSnapshot memory beforeState = takeYnEigenStateSnapshot();
        TokenStakingNodeStateSnapshot[] memory nodeStatesBefore = takeTokenStakingNodesStateSnapshot();
        
        // Execute deposit
        uint256 depositAmount = 10 ether;
        vm.startPrank(user);
        wstETH.approve(address(ynEigen), depositAmount);
        uint256 sharesBefore = ynEigen.balanceOf(user);
        ynEigen.deposit(wstETH, depositAmount, user);
        uint256 sharesReceived = ynEigen.balanceOf(user) - sharesBefore;
        vm.stopPrank();
        
        // Take snapshot after deposit
        YnEigenStateSnapshot memory afterState = takeYnEigenStateSnapshot();
        TokenStakingNodeStateSnapshot[] memory nodeStatesAfter = takeTokenStakingNodesStateSnapshot();
        
        // Verify correct state changes
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
        
        assertEq(
            afterState.totalStakingNodes,
            beforeState.totalStakingNodes,
            "totalStakingNodes changed unexpectedly"
        );
        
        verifyNodeStatesUnchanged(nodeStatesBefore, nodeStatesAfter);
    }
    
    /**
     * @notice Tests queuing withdrawals before any upgrades
     */
    function testQueueWithdrawalsBeforeSlashingUpgrade() public {
    }
}