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
            .upgradeAndCall(ITransparentUpgradeableProxy(address(ynEigenToken)), newImplementation, "");

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
            .upgradeAndCall(ITransparentUpgradeableProxy(address(ynEigenToken)), newYnEigenTokenImpl, "");

        TestTokenStakingNodeV2 testTokenStakingNodeV2 = new TestTokenStakingNodeV2();
        vm.prank(actors.admin.STAKING_ADMIN);
        tokenStakingNodesManager.upgradeTokenStakingNodeImplementation(address(testTokenStakingNodeV2));

        UpgradeableBeacon beacon = tokenStakingNodesManager.upgradeableBeacon();
        address upgradedImplementationAddress = beacon.implementation();
        assertEq(upgradedImplementationAddress, address(testTokenStakingNodeV2));

        TestTokenStakingNodeV2 testTokenStakingNodeV2Instance = TestTokenStakingNodeV2(payable(address(tokenStakingNodeInstance)));
        uint256 redundantFunctionResult = testTokenStakingNodeV2Instance.redundantFunction();
        assertEq(redundantFunctionResult, 1234567);

        assertEq(testTokenStakingNodeV2Instance.valueToBeInitialized(), 23, "Value to be initialized does not match expected value");
    }

    function testFailRegisterTokenStakingNodeImplementationTwice() public {
        address initialImplementation = address(new TestTokenStakingNodeV2());
        tokenStakingNodesManager.registerTokenStakingNodeImplementationContract(initialImplementation);

        address newImplementation = address(new TestTokenStakingNodeV2());
        vm.expectRevert("ynEigenToken: Implementation already exists");
        tokenStakingNodesManager.registerTokenStakingNodeImplementationContract(newImplementation);
    }

    function testRegisterTokenStakingNodeImplementationAlreadyExists() public {
        // address initialImplementation = address(new TestTokenStakingNodeV2());
        // vm.startPrank(actors.STAKING_ADMIN);
        // ynEigenToken.registerTokenStakingNodeImplementationContract(initialImplementation);

        // // vm.expectRevert("ynEigenToken: Implementation already exists");

        // ynEigenToken.registerTokenStakingNodeImplementationContract(initialImplementation);
        // vm.stopPrank();
        // TODO: Come back to this
    }

    // function testRetrieveAssetsNotLSDStakingNode() public {
    //     IERC20 asset = IERC20(chainAddresses.lsd.RETH_ADDRESS);
    //     uint256 amount = 1000;

    //     vm.prank(actors.ops.STAKING_NODE_CREATOR);
    //     ynlsd.createLSDStakingNode();
    //     vm.expectRevert(abi.encodeWithSelector(ynLSD.NotLSDStakingNode.selector, address(this), 0));
    //     ynlsd.retrieveAsset(0, asset, amount);
    // }

    // function testRetrieveAssetsUnsupportedAsset() public {
    //     // come back to this
    // }

    // function testRetrieveTransferExceedsBalance() public {
    //     IERC20 asset = IERC20(chainAddresses.lsd.RETH_ADDRESS);
    //     uint256 amount = 1000;

    //     vm.prank(actors.ops.STAKING_NODE_CREATOR);
    //     ynlsd.createTokenStakingNode();

    //     ITokenStakingNode tokenStakingNode = ynlsd.nodes(0);

    //     vm.startPrank(address(tokenStakingNode));
    //     vm.expectRevert();
    //     ynlsd.retrieveAsset(0, asset, amount);
    //     vm.stopPrank();
    // }

    // function testRetrieveAssetsSuccess() public {
    //     IERC20 asset = IERC20(chainAddresses.lsd.STETH_ADDRESS);
    //     uint256 amount = 64 ether;

    //     vm.prank(actors.ops.STAKING_NODE_CREATOR);
    //     ynlsd.createTokenStakingNode();

    //     ITokenStakingNode tokenStakingNode = ynlsd.nodes(0);
    //     vm.deal(address(tokenStakingNode), 1000);

    //     // 1. Obtain stETH and Deposit assets to ynLSD by User
    //     TestAssetUtils testAssetUtils = new TestAssetUtils();
    //     uint256 balance = testAssetUtils.get_stETH(address(this), amount);
    //     assertEq(compareRebasingTokenBalances(balance, amount), true, "Amount not received");
       
    //     asset.approve(address(ynlsd), balance);
    //     ynlsd.deposit(asset, balance, address(this));

    //     vm.startPrank(address(tokenStakingNode));
    //     asset.approve(address(ynlsd), 32 ether);
    //     ynlsd.retrieveAsset(0, asset, balance);
    //     vm.stopPrank();
    // }

    function testSetMaxNodeCount() public {
        uint256 maxNodeCount = 10;
        vm.prank(actors.admin.STAKING_ADMIN);
        tokenStakingNodesManager.setMaxNodeCount(maxNodeCount);
        assertEq(tokenStakingNodesManager.maxNodeCount(), maxNodeCount, "Max node count does not match expected value");
    }

    // function testPauseDepositsFunctionality() public {
    //     IERC20 stETH = IERC20(chainAddresses.lsd.STETH_ADDRESS);

    //     uint256 depositAmount = 0.1 ether;

	// 	// 1. Obtain stETH and Deposit assets to ynLSD by User
    //     TestAssetUtils testAssetUtils = new TestAssetUtils();
    //     uint256 balance = testAssetUtils.get_stETH(address(this), depositAmount);
    //     stETH.approve(address(ynlsd), balance);

    //     // Arrange
    //     vm.prank(actors.ops.PAUSE_ADMIN);
    //     ynlsd.pauseDeposits();

    //     // Act & Assert
    //     bool pauseState = ynlsd.depositsPaused();
    //     assertTrue(pauseState, "Deposit ETH should be paused after setting pause state to true");

    //     // Trying to deposit ETH while pause
    //     vm.expectRevert(ynLSD.Paused.selector);
    //     ynlsd.deposit(stETH, balance, address(this));

    //     // Unpause and try depositing again
    //     vm.prank(actors.admin.UNPAUSE_ADMIN);
    //     ynlsd.unpauseDeposits();
    //     pauseState = ynlsd.depositsPaused();

    //     assertFalse(pauseState, "Deposit ETH should be unpaused after setting pause state to false");

    //     // Deposit should succeed now
    //     ynlsd.deposit(stETH, balance, address(this));
    //     assertGt(ynlsd.totalAssets(), 0, "ynLSD balance should be greater than 0 after deposit");
    // }

}