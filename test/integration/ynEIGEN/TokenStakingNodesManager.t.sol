// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import "./ynEigenIntegrationBaseTest.sol";
import {ProxyAdmin} from "lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {UpgradeableBeacon} from "lib/openzeppelin-contracts/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {ITransparentUpgradeableProxy} from "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IPausable} from "lib/eigenlayer-contracts/src/contracts/interfaces//IPausable.sol";
import {ITokenStakingNode} from "src/interfaces/ITokenStakingNode.sol";
import {ynBase} from "src/ynBase.sol";
import {TestTokenStakingNodeV2} from "test/mocks/TestTokenStakingNodeV2.sol";
import {TestTokenStakingNodesManagerV2} from "test/mocks/TestTokenStakingNodesManagerV2.sol";


import "forge-std/console.sol";

contract TokenStakingNodesManagerAdminTest is ynEigenIntegrationBaseTest {

    function testCreateTokenStakingNode() public {
        vm.prank(actors.ops.STAKING_NODE_CREATOR);
        ITokenStakingNode tokenStakingNodeInstance = tokenStakingNodesManager.createTokenStakingNode();

        uint256 expectedNodeId = 0;
        assertEq(tokenStakingNodeInstance.nodeId(), expectedNodeId, "Node ID does not match expected value");
    }

    function testCreateStakingNodeOverMax() public {
        vm.startPrank(actors.ops.STAKING_NODE_CREATOR);
        for (uint256 i = 0; i < 10; i++) {
            tokenStakingNodesManager.createTokenStakingNode();
        }
        vm.expectRevert(abi.encodeWithSelector(TokenStakingNodesManager.TooManyStakingNodes.selector, 10));
        tokenStakingNodesManager.createTokenStakingNode();
        vm.stopPrank();
    } 

    function testCreate2TokenStakingNodes() public {
        vm.prank(actors.ops.STAKING_NODE_CREATOR);
        ITokenStakingNode tokenStakingNodeInstance1 = tokenStakingNodesManager.createTokenStakingNode();
        uint256 expectedNodeId1 = 0;
        assertEq(tokenStakingNodeInstance1.nodeId(), expectedNodeId1, "Node ID for node 1 does not match expected value");

        vm.prank(actors.ops.STAKING_NODE_CREATOR);
        ITokenStakingNode tokenStakingNodeInstance2 = tokenStakingNodesManager.createTokenStakingNode();
        uint256 expectedNodeId2 = 1;
        assertEq(tokenStakingNodeInstance2.nodeId(), expectedNodeId2, "Node ID for node 2 does not match expected value");
    }

    function testCreateTokenStakingNodeAfterUpgradeWithoutUpgradeability() public {
        // Upgrade the ynEigenToken implementation to TestTokenStakingNodesManagerV2
        address newImplementation = address(new TestTokenStakingNodesManagerV2());
        vm.prank(actors.admin.PROXY_ADMIN_OWNER);
        ProxyAdmin(getTransparentUpgradeableProxyAdminAddress(address(tokenStakingNodesManager)))
            .upgradeAndCall(ITransparentUpgradeableProxy(address(tokenStakingNodesManager)), newImplementation, "");

        // Attempt to create a token staking node after the upgrade - should fail since implementation is not there
        vm.expectRevert();
        vm.prank(actors.ops.STAKING_NODE_CREATOR);
        tokenStakingNodesManager.createTokenStakingNode();
    }

    function testUpgradeTokenStakingNodeImplementation() public {
        vm.prank(actors.ops.STAKING_NODE_CREATOR);
        ITokenStakingNode tokenStakingNodeInstance = tokenStakingNodesManager.createTokenStakingNode();

        // upgrade the ynEigenToken to support the new initialization version.
        address newYnEigenTokenImpl = address(new TestTokenStakingNodesManagerV2());
        vm.prank(actors.admin.PROXY_ADMIN_OWNER);
        ProxyAdmin(getTransparentUpgradeableProxyAdminAddress(address(tokenStakingNodesManager)))
            .upgradeAndCall(ITransparentUpgradeableProxy(address(tokenStakingNodesManager)), newYnEigenTokenImpl, "");

        TestTokenStakingNodeV2 testTokenStakingNodeV2 = new TestTokenStakingNodeV2();
        vm.prank(actors.admin.STAKING_ADMIN);
        tokenStakingNodesManager.upgradeTokenStakingNode(address(testTokenStakingNodeV2));

        UpgradeableBeacon beacon = tokenStakingNodesManager.upgradeableBeacon();
        address upgradedImplementationAddress = beacon.implementation();
        assertEq(upgradedImplementationAddress, address(testTokenStakingNodeV2));

        TestTokenStakingNodeV2 testTokenStakingNodeV2Instance = TestTokenStakingNodeV2(payable(address(tokenStakingNodeInstance)));
        uint256 redundantFunctionResult = testTokenStakingNodeV2Instance.redundantFunction();
        assertEq(redundantFunctionResult, 1234567);

        assertEq(testTokenStakingNodeV2Instance.valueToBeInitialized(), 23, "Value to be initialized does not match expected value");
    }

    function testRevertIfRegisterTokenStakingNodeImplementationTwice() public {

        address newImplementation = address(new TestTokenStakingNodeV2());
        vm.expectRevert(abi.encodeWithSelector(TokenStakingNodesManager.BeaconImplementationAlreadyExists.selector));
        vm.prank(actors.admin.STAKING_ADMIN);
        tokenStakingNodesManager.registerTokenStakingNode(newImplementation);
    }

    function testSetMaxNodeCount() public {
        uint256 maxNodeCount = 10;
        vm.prank(actors.admin.STAKING_ADMIN);
        tokenStakingNodesManager.setMaxNodeCount(maxNodeCount);
        assertEq(tokenStakingNodesManager.maxNodeCount(), maxNodeCount, "Max node count does not match expected value");
    }

    function testPauseDepositsFunctionality() public {
        IERC20 wstETH = IERC20(chainAddresses.lsd.WSTETH_ADDRESS);

        uint256 depositAmount = 0.1 ether;

		// 1. Obtain wstETH and Deposit assets to ynEigen by User
        TestAssetUtils testAssetUtils = new TestAssetUtils();
        uint256 balance = testAssetUtils.get_wstETH(address(this), depositAmount);
        wstETH.approve(address(ynEigenToken), balance);

        // Arrange
        vm.prank(actors.ops.PAUSE_ADMIN);
        ynEigenToken.pauseDeposits();

        // Act & Assert
        bool pauseState = ynEigenToken.depositsPaused();
        assertTrue(pauseState, "Deposit ETH should be paused after setting pause state to true");

        // Trying to deposit ETH while pause
        vm.expectRevert(ynEigen.Paused.selector);
        ynEigenToken.deposit(wstETH, balance, address(this));

        // Unpause and try depositing again
        vm.prank(actors.admin.UNPAUSE_ADMIN);
        ynEigenToken.unpauseDeposits();
        pauseState = ynEigenToken.depositsPaused();

        assertFalse(pauseState, "Deposit ETH should be unpaused after setting pause state to false");

        // Deposit should succeed now
        ynEigenToken.deposit(wstETH, balance, address(this));
        assertGt(ynEigenToken.totalAssets(), 0, "ynEigenToken balance should be greater than 0 after deposit");
    }

}