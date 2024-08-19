// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Invariants} from "./Invariants.sol";
import "test/integration/ynEIGEN/ynEigenIntegrationBaseTest.sol";
import {ITokenStakingNode} from "src/interfaces/ITokenStakingNode.sol";

contract YnEIGENScenarioTest1 is ynEigenIntegrationBaseTest {

	/**
		Scenario 1: Successful ETH Deposit and Share Minting 
		Objective: Test that a user can deposit ETH and receive 
		the correct amount of shares in return.
	*/

	address user1 = address(0x01);
	address user2 = address(0x02);
	address user3 = address(0x03);

	function test_ynEIGEN_Scenario_1_Fuzz(uint256 random1, uint256 random2, uint256 random3) public {

		/**
			Users deposit random amounts
			- Check the total assets of ynEIGEN
			- Check the share balance of each user
			- Check the total deposited in the pool
			- Check total supply of ynEIGEN
		 */

		// We assume amounts are greater than 1 wei to avoid potential edge cases with zero or shares.
		vm.assume(random1 > 1 && random1 < 100_000_000 ether);
		vm.assume(random2 > 1 && random2 < 100_000_000 ether);
		vm.assume(random3 > 1 && random3 < 100_000_000 ether);
		uint256 previousTotalDeposited;
		uint256 previousTotalAssets;
		uint256 previousTotalShares;

		address asset = chainAddresses.lsd.WSTETH_ADDRESS;

		// user 1 deposits random1
		uint256 user1Amount = random1;
		deal({ token: asset, to: user1, give: user1Amount });

		uint256 user1Shares = ynEigenToken.previewDeposit(IERC20(asset), user1Amount);
		vm.startPrank(user1);
		IERC20(asset).approve(address(ynEigenToken), user1Amount);
		ynEigenToken.deposit(IERC20(asset), user1Amount, user1);
		vm.stopPrank();

		previousTotalDeposited = 0;
		previousTotalAssets = 0;
		previousTotalShares = 0;

		runInvariants(IERC20(asset), user1, previousTotalAssets, previousTotalDeposited, previousTotalShares, user1Amount, user1Shares);

		// user 2 deposits random2
		uint256 user2Amount = random2;
		deal({ token: asset, to: user2, give: user2Amount });

		uint256 user2Shares = ynEigenToken.previewDeposit(IERC20(asset), user2Amount);
		vm.startPrank(user2);
		IERC20(asset).approve(address(ynEigenToken), user2Amount);
		ynEigenToken.deposit(IERC20(asset), user2Amount, user2);
		vm.stopPrank();

		previousTotalDeposited += user1Amount;
		previousTotalAssets += assetRegistry.convertToUnitOfAccount(IERC20(asset), user1Amount);
		previousTotalShares += user1Shares;

		runInvariants(IERC20(asset), user2, previousTotalAssets, previousTotalDeposited, previousTotalShares, user2Amount, user2Shares);

		// user 3 deposits random3
		uint256 user3Amount = random3;
		deal({ token: asset, to: user3, give: user3Amount });

		uint256 user3Shares = ynEigenToken.previewDeposit(IERC20(asset), user3Amount);
		vm.startPrank(user3);
		IERC20(asset).approve(address(ynEigenToken), user3Amount);
		ynEigenToken.deposit(IERC20(asset), user3Amount, user3);
		vm.stopPrank();

		previousTotalDeposited += user2Amount;
		previousTotalAssets += assetRegistry.convertToUnitOfAccount(IERC20(asset), user2Amount);
		previousTotalShares += user2Shares;

		runInvariants(IERC20(asset), user3, previousTotalAssets, previousTotalDeposited, previousTotalShares, user3Amount, user3Shares);
	}

	function runInvariants(IERC20 asset, address user, uint256 previousTotalAssets, uint256 previousTotalDeposited, uint256 previousTotalShares, uint256 userAmount, uint256 userShares) public view {
		Invariants.totalDepositIntegrity(ynEigenToken.assetBalance(asset), previousTotalDeposited, userAmount);
		Invariants.totalAssetsIntegrity(ynEigenToken.totalAssets(), previousTotalAssets, assetRegistry.convertToUnitOfAccount(asset, userAmount));
		Invariants.shareMintIntegrity(ynEigenToken.totalSupply(), previousTotalShares, userShares);
		Invariants.userSharesIntegrity(ynEigenToken.balanceOf(user), 0, userShares);
	}
}

contract YnEIGENScenarioTest2 is ynEigenIntegrationBaseTest {

	error Paused();
	error TransfersPaused();

	/**
		Scenario 2: Deposit Paused 
		Objective: Ensure that deposits are correctly 
		paused and resumed, preventing or allowing ETH 
		deposits accordingly.
	 */

	address user1 = address(0x01);
	address user2 = address(0x02);

	// pause ynEIGEN and try to deposit fail
	function test_ynEIGEN_Scenario_2_Pause() public {

		vm.prank(actors.ops.PAUSE_ADMIN);
	 	ynEigenToken.pauseDeposits();

		address asset = chainAddresses.lsd.WSTETH_ADDRESS;
		deal({ token: asset, to: user1, give: 1 ether });
		vm.startPrank(user1);
		IERC20(asset).approve(address(ynEigenToken), 1 ether);
		vm.expectRevert(Paused.selector);
		ynEigenToken.deposit(IERC20(asset), 1 ether, user1);
		vm.stopPrank();
	}

	function test_ynEIGEN_Scenario_2_Unpause() public {

	 	vm.prank(actors.ops.PAUSE_ADMIN);
	 	ynEigenToken.pauseDeposits();
		assertTrue(ynEigenToken.depositsPaused());
	 	vm.prank(actors.admin.UNPAUSE_ADMIN);
		ynEigenToken.unpauseDeposits();
		assertFalse(ynEigenToken.depositsPaused());
		vm.stopPrank();

		address asset = chainAddresses.lsd.WSTETH_ADDRESS;
		deal({ token: asset, to: user1, give: 1 ether });
		vm.startPrank(user1);
		IERC20(asset).approve(address(ynEigenToken), 1 ether);
		ynEigenToken.deposit(IERC20(asset), 1 ether, user1);
		vm.stopPrank();
		assertEq(ynEigenToken.balanceOf(user1), assetRegistry.convertToUnitOfAccount(IERC20(asset), 1 ether));
	}

	function test_ynEIGEN_Scenario_2_Pause_Transfer(uint256 random1) public {
		vm.assume(random1 > 0 && random1 < 100_000_000 ether);
		
		uint256 amount = random1;
		address asset = chainAddresses.lsd.WSTETH_ADDRESS;
		deal({ token: asset, to: user1, give: amount });
		vm.startPrank(user1);
		IERC20(asset).approve(address(ynEigenToken), amount);
		ynEigenToken.deposit(IERC20(asset), amount, user1);
		assertEq(ynEigenToken.balanceOf(user1), assetRegistry.convertToUnitOfAccount(IERC20(asset), amount));

		// should fail when not on the pause whitelist
		ynEigenToken.approve(user2, amount);
		vm.expectRevert(TransfersPaused.selector);
		ynEigenToken.transfer(user2, amount);
		vm.stopPrank();

		// should pass when on the pause whitelist
		deal({ token: asset, to: actors.eoa.DEFAULT_SIGNER, give: amount });
		vm.startPrank(actors.eoa.DEFAULT_SIGNER);
		IERC20(asset).approve(address(ynEigenToken), amount);
		ynEigenToken.deposit(IERC20(asset), amount, actors.eoa.DEFAULT_SIGNER);

		uint256 transferEnabledEOABalance = ynEigenToken.balanceOf(actors.eoa.DEFAULT_SIGNER);
		ynEigenToken.transfer(user2, transferEnabledEOABalance);
		vm.stopPrank();
		assertEq(ynEigenToken.balanceOf(user2), transferEnabledEOABalance);
	}
}

contract YnEIGENScenarioTest3 is ynEigenIntegrationBaseTest {

	/**
		Scenario 3: Deposit LSD to Strategy Manager
		Objective: Test that the Strategy Manager 
		can withdraw ETH from ynEIGEN.
	 */

	address user1 = address(0x01);
	
	function test_ynETH_Scenario_3_Deposit() public {

		depositLSD_and_createNode();
	}

	function depositLSD_and_createNode() public returns (ITokenStakingNode tokenStakingNode) {
		IERC20 asset = IERC20(chainAddresses.lsd.WSTETH_ADDRESS);
        uint256 amount = 64 ether;

        vm.prank(actors.ops.STAKING_NODE_CREATOR);
        tokenStakingNodesManager.createTokenStakingNode();

        tokenStakingNode = tokenStakingNodesManager.nodes(0);
       
        deal({ token: address(asset), to: user1, give: amount });
		vm.startPrank(user1);
		IERC20(asset).approve(address(ynEigenToken), amount);
		ynEigenToken.deposit(IERC20(asset), amount, user1);
		vm.stopPrank();

		{
            IERC20[] memory assets = new IERC20[](1);
            uint256[] memory amounts = new uint256[](1);
            assets[0] = asset;
            amounts[0] = amount;

            uint256 nodeId = tokenStakingNode.nodeId();
            vm.prank(actors.ops.STRATEGY_CONTROLLER);
            eigenStrategyManager.stakeAssetsToNode(nodeId, assets, amounts);
        }

		assertApproxEqAbs(amount, eigenStrategyManager.getStakedAssetBalanceForNode(asset, 0), 2);
	}
}