// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IntegrationBaseTest} from "test/integration/IntegrationBaseTest.sol";
import {RewardsDistributor} from "src/RewardsDistributor.sol";
import {NonPayableContract} from "test/utils/NonPayableContract.sol";

contract RewardsDistributorTest is IntegrationBaseTest {

	function testSetFeeReceiver() public {
		address newReceiver = address(0x123);
		vm.prank(actors.admin.REWARDS_ADMIN);
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
		vm.prank(actors.admin.ADMIN);
		uint256 fees = (totalRewards * 100) / rewardsDistributor.feesBasisPoints();

		uint256 initialBalance = address(actors.admin.FEE_RECEIVER).balance;
		rewardsDistributor.processRewards();
		uint256 finalBalance = address(actors.admin.FEE_RECEIVER).balance;
		assertEq(finalBalance, initialBalance + fees);
	}

	function testProcessRewardSendFeeFailed() public {
		// send 1 eth to elr and 2 eth to clr
		vm.deal(address(executionLayerReceiver), 2 ether);
		vm.deal(address(consensusLayerReceiver), 3 ether);

		// set invalid fee receiver
		vm.prank(actors.admin.REWARDS_ADMIN);
		address nonPayableAddress = address(new NonPayableContract());
		address payable payableAddress = payable(nonPayableAddress);
		rewardsDistributor.setFeesReceiver(payableAddress);

		// process rewards
		vm.startPrank(actors.admin.ADMIN);
		vm.expectRevert(abi.encodeWithSelector(RewardsDistributor.FeeSendFailed.selector));
		rewardsDistributor.processRewards();
		vm.stopPrank();
	}

	function testSetFeeBasisPoints() public {
		uint16 newFeeBasisPoints = 500; // 5%
		vm.prank(actors.admin.REWARDS_ADMIN);
		rewardsDistributor.setFeesBasisPoints(newFeeBasisPoints);
		assertEq(rewardsDistributor.feesBasisPoints(), newFeeBasisPoints);
	}

	function testFailSetFeeBasisPointsExceedsLimit() public {
		
		uint16 newFeeBasisPoints = 15000; // 150%, exceeds 100%
		vm.prank(actors.admin.REWARDS_ADMIN);
		vm.expectRevert(abi.encodeWithSelector(RewardsDistributor.InvalidBasisPoints.selector, newFeeBasisPoints));
		rewardsDistributor.setFeesBasisPoints(newFeeBasisPoints);
	}
}