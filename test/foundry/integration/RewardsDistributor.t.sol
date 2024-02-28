// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IntegrationBaseTest} from "./IntegrationBaseTest.sol";


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
}