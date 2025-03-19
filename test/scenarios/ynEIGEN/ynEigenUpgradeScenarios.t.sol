// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {ynLSDeScenarioBaseTest} from "./ynLSDeScenarioBaseTest.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAllocationManager} from "@eigenlayer/src/contracts/interfaces/IAllocationManager.sol";
import {IPermissionController} from "@eigenlayer/src/contracts/interfaces/IPermissionController.sol";
import {IPauserRegistry} from "@eigenlayer/src/contracts/interfaces/IPauserRegistry.sol";
import {IETHPOSDeposit} from "@eigenlayer/src/contracts/interfaces/IETHPOSDeposit.sol";
import {IBeacon} from "@openzeppelin-v4.9.0/contracts/proxy/beacon/IBeacon.sol";
import {ITokenStakingNode} from "src/interfaces/ITokenStakingNode.sol";
import {AllocationManager} from "@eigenlayer/src/contracts/core/AllocationManager.sol";
import {DelegationManager} from "@eigenlayer/src/contracts/core/DelegationManager.sol";
import {EigenPodManager} from "@eigenlayer/src/contracts/pods/EigenPodManager.sol";

contract ynEigenUpgradeScenarios is ynLSDeScenarioBaseTest {

    IAllocationManager public allocationManager;

    address private user1;

    IPauserRegistry public pauserRegistry = IPauserRegistry(0x0c431C66F4dE941d089625E5B423D00707977060);
    IETHPOSDeposit public ethposDeposit = IETHPOSDeposit(0x00000000219ab540356cBB839Cbe05303d7705Fa);
    IBeacon public eigenPodBeacon = IBeacon(0x5a2a4F2F3C18f09179B6703e63D9eDD165909073);

    // Test state capture
    struct SystemSnapshot {
        uint256 totalAssets;
        uint256 totalSupply;
        uint256 userBalance;
        uint256 wstEthBalance;
        uint256 tokenStakingNodesCount;
    }

    function setUp() public virtual override {
        super.setUp();

        user1 = makeAddr("user1");
        deal({token: chainAddresses.lsd.WSTETH_ADDRESS, to: user1, give: 1000 ether});
    }

    // forge test --fork-url $MAINNET_RPC --match-contract ynEigenUpgradeScenarios -vv --fork-block-number 22046726
    function testDepositBeforeELUpgradeAndBeforeynEigenUpgrade() public {
        // Capture system state before deposit
        SystemSnapshot memory beforeState = getSystemSnapshot(user1);
        
        vm.startPrank(user1);
        IERC20(chainAddresses.lsd.WSTETH_ADDRESS).approve(address(yneigen), 10 ether);
        uint256 expectedShares = yneigen.previewDeposit(IERC20(chainAddresses.lsd.WSTETH_ADDRESS), 10 ether);
        uint256 sharesBefore = yneigen.balanceOf(user1);
        yneigen.deposit(IERC20(chainAddresses.lsd.WSTETH_ADDRESS), 10 ether, user1);
        uint256 sharesAfter = yneigen.balanceOf(user1);
        vm.stopPrank();
        
        // Capture system state after deposit
        SystemSnapshot memory afterState = getSystemSnapshot(user1);
        
        // Assert basic accounting
        assertEq(sharesAfter - sharesBefore, expectedShares, "Shares minted don't match expected amount");
        assertGt(afterState.totalAssets, beforeState.totalAssets, "Total assets should increase after deposit");
        assertEq(afterState.totalSupply, beforeState.totalSupply + expectedShares, "Total supply didn't increase by expected amount");
        assertEq(afterState.userBalance, beforeState.userBalance + expectedShares, "User balance didn't increase by expected amount");
        assertEq(afterState.wstEthBalance, beforeState.wstEthBalance - 10 ether, "wstETH wasn't transferred from user");
        
        // Assert nodes weren't affected
        assertEq(afterState.tokenStakingNodesCount, beforeState.tokenStakingNodesCount, "Number of staking nodes shouldn't change");
        
        // Assert system is functional
        for (uint256 i = 0; i < tokenStakingNodesManager.nodesLength(); i++) {
            ITokenStakingNode node = tokenStakingNodesManager.getNodeById(i);
            assertTrue(node.isSynchronized(), "Node should be synchronized in normal state");
        }
        
        // Successfully call strategy manager functions
        eigenStrategyManager.getStakedAssetBalance(IERC20(chainAddresses.lsd.WSTETH_ADDRESS));
    }

    function testDepositAfterELUpgradeAndBeforeynEigenUpgrade() public {
        SystemSnapshot memory beforeState = getSystemSnapshot(user1);
        
        upgradeEigenLayerContracts();
        
        vm.startPrank(user1);
        IERC20(chainAddresses.lsd.WSTETH_ADDRESS).approve(address(yneigen), 10 ether);
        uint256 sharesBefore = yneigen.balanceOf(user1);
        yneigen.deposit(IERC20(chainAddresses.lsd.WSTETH_ADDRESS), 10 ether, user1);
        uint256 sharesAfter = yneigen.balanceOf(user1);
        vm.stopPrank();
        
        // Capture system state after deposit
        SystemSnapshot memory afterState = getSystemSnapshot(user1);
        
        uint256 sharesMinted = sharesAfter - sharesBefore;
        assertGt(sharesMinted, 0, "No shares were minted");
        assertGt(afterState.totalAssets, beforeState.totalAssets, "Total assets should increase after deposit");
        assertEq(afterState.totalSupply, beforeState.totalSupply + sharesMinted, "Total supply didn't increase by shares minted");
        assertEq(afterState.userBalance, beforeState.userBalance + sharesMinted, "User balance didn't increase by shares minted");
        assertEq(afterState.wstEthBalance, beforeState.wstEthBalance - 10 ether, "wstETH wasn't transferred from user");
        
        assertEq(afterState.tokenStakingNodesCount, beforeState.tokenStakingNodesCount, "Number of staking nodes shouldn't change");
        
    }
    
    function upgradeEigenLayerContracts() internal {
        allocationManager = new AllocationManager(
            delegationManager, 
            pauserRegistry, 
            IPermissionController(address(2)), 
            1, 
            1
        );

        DelegationManager newDelegationManager = new DelegationManager(
            strategyManager, 
            eigenPodManager, 
            allocationManager, 
            pauserRegistry, 
            IPermissionController(address(2)), 
            1
        );
        
        vm.etch(address(delegationManager), address(newDelegationManager).code);

        EigenPodManager newEigenPodManager = new EigenPodManager(
            ethposDeposit, 
            eigenPodBeacon, 
            delegationManager, 
            pauserRegistry
        );
        
        vm.etch(address(eigenPodManager), address(newEigenPodManager).code);
    }
    
    function getSystemSnapshot(address user) internal view returns (SystemSnapshot memory) {
        return SystemSnapshot({
            totalAssets: yneigen.totalAssets(),
            totalSupply: yneigen.totalSupply(),
            userBalance: yneigen.balanceOf(user),
            wstEthBalance: IERC20(chainAddresses.lsd.WSTETH_ADDRESS).balanceOf(user),
            tokenStakingNodesCount: tokenStakingNodesManager.nodesLength()
        });
    }
}