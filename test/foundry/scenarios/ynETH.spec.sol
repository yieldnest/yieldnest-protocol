// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import { IntegrationBaseTest } from "test/foundry/integration/IntegrationBaseTest.sol";

contract YnETHScenarioTest1 is IntegrationBaseTest {

	/**
	Scenario 1: Successful ETH Deposit and Share Minting 
	Objective: Test that a user can deposit ETH and receive 
	the correct amount of shares in return.
	*/

	// users
	address user1 = address(0x01);
	address user2 = address(0x02);
	address user3 = address(0x03);

	function test_ynETH_Scenario_1() public {
		
		// user1 deposits 1 ETH
		// check the total assets of ynETH
		// check the balance of user

		uint256 user1Amount = 1 ether;
		vm.deal(user1, user1Amount);
		yneth.depositETH{value: user1Amount}(user1);
		assertEq(yneth.totalAssets(), user1Amount);
		assertEq(yneth.balanceOf(user1), user1Amount);

		uint256 user2Amount = 32 ether;
		vm.deal(user2, user2Amount);
		yneth.depositETH{value: user2Amount}(user2);
		assertEq(yneth.totalAssets(), user1Amount + user2Amount);
		assertEq(yneth.balanceOf(user2), user2Amount);

		uint256 user3Amount = 128 ether;
		vm.deal(user3, user3Amount);
		yneth.depositETH{value: 128 ether}(user3);
	}


}