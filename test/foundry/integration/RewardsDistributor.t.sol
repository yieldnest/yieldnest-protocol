// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IntegrationBaseTest} from "./IntegrationBaseTest.sol";
import {RewardsDistributor} from "../../../src/RewardsDistributor.sol";

contract RewardsDistributorTest is IntegrationBaseTest {

	function testSetFeeReceiver() public {
		address newReceiver = address(0x123);
		vm.prank(actors.ADMIN);
		rewardsDistributor.setFeesReceiver(payable(newReceiver));
		assertEq(rewardsDistributor.feesReceiver(), newReceiver);
	}

	function testFailSetFeeReceiverNotAdmin() public {
		address newReceiver = address(0x123);
		rewardsDistributor.setFeesReceiver(payable(newReceiver));
	}

	function testProcessRewards() public {
		// send 1 eth to elr and 2 eth to clr
		uint256 totalRewards = 5 ether;
		vm.deal(address(executionLayerReceiver), 2 ether);
		vm.deal(address(consensusLayerReceiver), 3 ether);
		vm.prank(actors.ADMIN);
		uint256 fees = (totalRewards * 100) / rewardsDistributor.feesBasisPoints();
		rewardsDistributor.processRewards();
		assertEq(address(actors.FEE_RECEIVER).balance, fees);
	}

	function testProcessRewardSendFeeFailed() public {
		// send 1 eth to elr and 2 eth to clr
		vm.deal(address(executionLayerReceiver), 2 ether);
		vm.deal(address(consensusLayerReceiver), 3 ether);

		// set invalid fee receiver
		vm.prank(actors.ADMIN);
		address nonPayableAddress = address(yieldNestOracle);
		address payable payableAddress = payable(nonPayableAddress);
		rewardsDistributor.setFeesReceiver(payableAddress);

		// process rewards
		vm.startPrank(actors.ADMIN);
		vm.expectRevert(abi.encodeWithSelector(RewardsDistributor.FeeSendFailed.selector));
		rewardsDistributor.processRewards();
		vm.stopPrank();
	}
}