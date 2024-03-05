// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity 0.8.24;

import "./IntegrationBaseTest.sol";

import {ILSDStakingNode} from "../../../src/interfaces/ILSDStakingNode.sol";
import {IynLSD} from "../../../src/interfaces/IynLSD.sol";
import {IPausable} from "../../../src/external/eigenlayer/v0.1.0/interfaces/IPausable.sol";

import "forge-std/Console.sol";

contract LSDStakingNodeTest is IntegrationBaseTest {

	ILSDStakingNode lsdStakingNode;

	function setUp() public override {
		super.setUp();
		vm.prank(actors.STAKING_NODE_CREATOR);
		lsdStakingNode = ynlsd.createLSDStakingNode();
	}
	
	function testYnLSDView() public {
		IynLSD _ynlsd = lsdStakingNode.ynLSD();
		assertEq(address(_ynlsd), address(ynlsd));
	}

	function testNodeIdView() public {
		uint256 _nodeId = lsdStakingNode.nodeId();
		assertEq(_nodeId, 0);
	}

	function testDepositAssetsToEigenlayerUnsupportedAsset() public {
		IERC20[] memory assets = new IERC20[](1);
		assets[0] = IERC20(address(ynlsd));
		uint256[] memory amounts = new uint256[](1);
		amounts[0] = 100;
		vm.prank(actors.LSD_RESTAKING_MANAGER);
		vm.expectRevert(abi.encodeWithSelector(LSDStakingNode.UnsupportedAsset.selector, assets[0]));
		lsdStakingNode.depositAssetsToEigenlayer(assets, amounts);
	}

	function testDepositAssetsToEigenlayerSuccess() public {

		// 1. Obtain stETH and Deposit assets to ynLSD by User
		IERC20 stETH = IERC20(chainAddresses.lsd.STETH_ADDRESS);
        uint256 amount = 1 ether;
        (bool success, ) = chainAddresses.lsd.STETH_ADDRESS.call{value: amount + 1}("");
        require(success, "ETH transfer failed");
        uint256 balance = stETH.balanceOf(address(this));
        assertEq(balance, amount, "Amount not received");
		stETH.approve(address(ynlsd), amount);
		ynlsd.deposit(stETH, amount, address(this));

		// 2. Deposit assets to Eigenlayer by LSD ReStaking Manager
        IPausable pausableStrategyManager = IPausable(address(strategyManager));
        vm.prank(actors.STAKING_NODE_CREATOR);
        address unpauser = pausableStrategyManager.pauserRegistry().unpauser();
        vm.startPrank(unpauser);
        pausableStrategyManager.unpause(0);
        vm.stopPrank();

		IERC20[] memory assets = new IERC20[](1);
		assets[0] = stETH;
		uint256[] memory amounts = new uint256[](1);
		amounts[0] = stETH.balanceOf(address(lsdStakingNode));
		vm.prank(actors.LSD_RESTAKING_MANAGER);
		lsdStakingNode.depositAssetsToEigenlayer(assets, amounts);
	}

}