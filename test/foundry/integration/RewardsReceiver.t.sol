// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IntegrationBaseTest} from "./IntegrationBaseTest.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {RewardsReceiver} from "../../../src/RewardsReceiver.sol";

contract RewardsReceiverTest is IntegrationBaseTest {

	MockERC20 public mockERC20;

	function setUp() public override {
		super.setUp();
		mockERC20 = new MockERC20("MockERC20", "MERC20");
	}

	function testTransferETHOnlyWithrdrawerRole() public {
		address newReceiver = address(33);
		vm.deal(address(executionLayerReceiver), 100);
		vm.prank(address(rewardsDistributor));
		executionLayerReceiver.transferETH(payable(newReceiver), 100);
		assertEq(address(newReceiver).balance, 100);
	}

	function testFailTransferETHNotWithrdrawerRole() public {
		address newReceiver = address(33);
		vm.deal(address(executionLayerReceiver), 100);
		executionLayerReceiver.transferETH(payable(newReceiver), 100);
	}

	function testTransferETHInsufficientBalance() public {
		address newReceiver = address(33);
		vm.prank(address(rewardsDistributor));
		vm.expectRevert(abi.encodeWithSelector(RewardsReceiver.InsufficientBalance.selector));
		executionLayerReceiver.transferETH(payable(newReceiver), 100);
	}

	function testTransferETHTransferFailed() public {
		address newReceiver = address(this);
		vm.deal(address(executionLayerReceiver), 1);
		vm.prank(address(rewardsDistributor));
		vm.expectRevert(abi.encodeWithSelector(RewardsReceiver.TransferFailed.selector));
		executionLayerReceiver.transferETH(payable(newReceiver), 1);
	}	

	function testERC20TransferOnlyWithrdrawerRole() public {
		address receiver = address(33);
		mockERC20.mint(address(executionLayerReceiver), 100);
		vm.prank(address(rewardsDistributor));
		executionLayerReceiver.transferERC20(mockERC20, receiver, 100);
		assertEq(mockERC20.balanceOf(receiver), 100);
	}

	function testFailERC20TransferNotWithrdrawerRole() public {
		address receiver = address(33);
		mockERC20.mint(address(executionLayerReceiver), 100);
		executionLayerReceiver.transferERC20(mockERC20, receiver, 100);
	}
}