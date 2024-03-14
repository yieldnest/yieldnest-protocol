// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import { IntegrationBaseTest } from "test/foundry/integration/IntegrationBaseTest.sol";
import { Invariants } from "test/foundry/scenarios/Invariants.sol";
import { IynETH } from "src/interfaces/IynETH.sol";

contract YnETHScenarioTest1 is IntegrationBaseTest {

	/**
	Scenario 1: Successful ETH Deposit and Share Minting 
	Objective: Test that a user can deposit ETH and receive 
	the correct amount of shares in return.
	*/

	address user1 = address(0x01);
	address user2 = address(0x02);
	address user3 = address(0x03);

	function test_ynETH_Scenario_1_Fuzz(uint256 random1, uint256 random2, uint256 random3) public {

		/**
			3 Users deposit random amounts of fuzz
			- Check the total assets of ynETH
			- Check the share balance of each user
			- Check the total deposited in the pool
			- Check total supply of ynETH
		 */

		vm.assume(random1 > 0 && random1 < 100_000_000 ether);
		vm.assume(random2 > 0 && random2 < 100_000_000 ether);
		vm.assume(random3 > 0 && random3 < 100_000_000 ether);
		
		uint256 previousTotalDeposited;
		uint256 previousTotalShares;

		// user 1 deposits random1
		uint256 user1Amount = random1;
		vm.deal(user1, user1Amount);

		uint256 user1Shares = yneth.previewDeposit(user1Amount);
		yneth.depositETH{value: user1Amount}(user1);

		previousTotalDeposited = 0;
		previousTotalShares = 0;

		runInvariants(user1, previousTotalDeposited, previousTotalShares, user1Amount, user1Shares);

		// user 2 deposits random2
		uint256 user2Amount = random2;
		vm.deal(user2, user2Amount);

		uint256 user2Shares = yneth.previewDeposit(user2Amount);
		yneth.depositETH{value: user2Amount}(user2);

		previousTotalDeposited += user1Amount;
		previousTotalShares += user1Shares;

		runInvariants(user2, previousTotalDeposited, previousTotalShares, user2Amount, user2Shares);

		// user 3 deposits random3
		uint256 user3Amount = random3;
		vm.deal(user3, user3Amount);

		uint256 user3Shares = yneth.previewDeposit(user3Amount);
		yneth.depositETH{value: user3Amount}(user3);

		previousTotalDeposited += user2Amount;
		previousTotalShares += user2Shares;

		runInvariants(user3, previousTotalDeposited, previousTotalShares, user3Amount, user3Shares);
	}

	function runInvariants(address user, uint256 previousTotalDeposited, uint256 previousTotalShares, uint256 userAmount, uint256 userShares) public view {
		Invariants.totalDepositIntegrity(yneth.totalDepositedInPool(), previousTotalDeposited, userAmount);
		Invariants.totalAssetsIntegrity(yneth.totalAssets(), previousTotalDeposited, userAmount);
		Invariants.shareMintIntegrity(yneth.totalSupply(), previousTotalShares, userShares);
		Invariants.userSharesIntegrity(yneth.balanceOf(user), 0, userShares);
	}

	// NOTE: Various efforts to circumvent the deposit mechanism are not included in this test
}

contract YnETHScenarioTest2 is IntegrationBaseTest {

	/**
		Scenario 2: Deposit Paused 
		Objective: Ensure that deposits are correctly 
		paused and resumed, preventing or allowing ETH 
		deposits accordingly.
	 */

	address user1 = address(0x01);
	address user2 = address(0x02);

	// pause ynETH and try to deposit fail
	function test_ynETH_Scenario_2_Pause() public {

		vm.prank(actors.PAUSE_ADMIN);
	 	yneth.updateDepositsPaused(true);

	 	vm.deal(user1, 1 ether);
	 	vm.expectRevert(bytes4(keccak256(abi.encodePacked("Paused()"))));
	 	yneth.depositETH{value: 1 ether}(user1);
	}

	function test_ynETH_Scenario_2_Unpause() public {

	 	vm.startPrank(actors.PAUSE_ADMIN);
	 	yneth.updateDepositsPaused(true);
		assertTrue(yneth.depositsPaused());
		yneth.updateDepositsPaused(false);
		assertFalse(yneth.depositsPaused());
		vm.stopPrank();

		vm.deal(user1, 1 ether);
		vm.prank(user1);
		yneth.depositETH{value: 1 ether}(user1);
		assertEq(yneth.balanceOf(user1), 1 ether);
	}

	function test_ynETH_Scenario_2_Pause_Transfer(uint256 random1) public {

		vm.assume(random1 > 0 && random1 < 100_000_000 ether);
		
		uint256 amount = random1;
		vm.deal(user1, amount);
		vm.startPrank(user1);
		yneth.depositETH{value: amount}(user1);
		assertEq(yneth.balanceOf(user1), amount);

		// should fail when not on the pause whitelist
		yneth.approve(user2, amount);
		vm.expectRevert(bytes4(keccak256(abi.encodePacked("TransfersPaused()"))));
		yneth.transfer(user2, amount);
		vm.stopPrank();

		// should pass when on the pause whitelist
		vm.startPrank(actors.TRANSFER_ENABLED_EOA);
		vm.deal(actors.TRANSFER_ENABLED_EOA, amount);
		yneth.depositETH{value: amount}(actors.TRANSFER_ENABLED_EOA);

		uint256 transferEnabledEOABalance = yneth.balanceOf(actors.TRANSFER_ENABLED_EOA);
		yneth.transfer(user2, transferEnabledEOABalance);
		assertEq(yneth.balanceOf(user2), transferEnabledEOABalance);
	}

	// NOTE: circumvention experiments are not included with these tests
	// that overlap with integration tests. Just leaving a few tests above...
}

contract YnETHScenarioTest3 is IntegrationBaseTest {

	/**
		Scenario 3: Withdraw ETH to Staking Nodes Manager 
		Objective: Test that only the Staking Nodes Manager 
		can withdraw ETH from the contract.
	 */
}

contract YnETHScenarioTest4 is IntegrationBaseTest {

	/**
		Scenario 4: Share Accouting and Yield Accrual 
		Objective: Verify that the share price correctly 
		increases after the contract earns yield from 
		consensus and execution rewards.
	 */
}

contract YnETHScenarioTest5 is IntegrationBaseTest {

	/**
		Scenario 5: Emergency Withdrawal of ETH 
		Objective: Test ynETH's ability to 
		administer beacon upgrades to Staking Nodes.
	 */
}