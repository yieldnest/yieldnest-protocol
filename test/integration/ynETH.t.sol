// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IntegrationBaseTest} from "test/integration/IntegrationBaseTest.sol";
import {ynETH} from "src/ynETH.sol";
import {ynBase} from "src/ynBase.sol";
import {IStakingNode} from "src/interfaces/IStakingNode.sol";
import {Math} from "lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import {IEigenPod} from "lib/eigenlayer-contracts/src/contracts/interfaces/IEigenPod.sol";

import "forge-std/console.sol";

contract ynETHIntegrationTest is IntegrationBaseTest {

    function testDepositETH() public {

        emit log_named_uint("Block number at deposit test", block.number);

        uint256 depositAmount = 1 ether;
        vm.deal(address(this), depositAmount);
        // Arrange
        uint256 initialETHBalance = address(this).balance;

        yneth.depositETH{value: depositAmount}(address(this));

        // Assert
        uint256 finalETHBalance = address(this).balance;
        uint256 ynETHBalance = yneth.balanceOf(address(this));
        uint256 expectedETHBalance = initialETHBalance - depositAmount;

        assertEq(finalETHBalance, expectedETHBalance, "ETH was not correctly deducted from sender");
        assertGt(ynETHBalance, 0, "ynETH balance should be greater than 0 after deposit");
    }

    function testDepositETHWhenPaused() public {
        // Arrange
        vm.prank(actors.ops.PAUSE_ADMIN);
        yneth.pauseDeposits();

        uint256 depositAmount = 1 ether;
        vm.deal(address(this), depositAmount);

        // Act & Assert
        vm.expectRevert(ynETH.Paused.selector);
        yneth.depositETH{value: depositAmount}(address(this));
    }

    function testPauseDepositETH() public {
        // Arrange
        vm.prank(actors.ops.PAUSE_ADMIN);
        yneth.pauseDeposits();

        // Act & Assert
        bool pauseState = yneth.depositsPaused();
        assertTrue(pauseState, "Deposit ETH should be paused");
    }

    function testUnpauseDepositETH() public {
        // Arrange
        vm.prank(actors.ops.PAUSE_ADMIN);
        yneth.pauseDeposits();
        vm.prank(actors.admin.UNPAUSE_ADMIN);
        yneth.unpauseDeposits();

        // Act & Assert
        bool pauseState = yneth.depositsPaused();
        assertFalse(pauseState, "Deposit ETH should be unpaused");
    }

    function testPreviewDeposit() public {
        // Arrange
        uint256 depositAmount = 1 ether;
        vm.deal(address(this), depositAmount);

        // Act
        uint256 shares = yneth.previewDeposit(depositAmount);

        // Assert
        assertTrue(shares > 0, "Preview deposit should return more than 0 shares");
        vm.stopPrank();
    }

    function testTotalAssets() public {
        // Arrange
        uint256 initialTotalAssets = yneth.totalAssets();
        uint256 depositAmount = 1 ether;
        yneth.depositETH{value: depositAmount}(address(this));

        // Act
        uint256 totalAssetsAfterDeposit = yneth.totalAssets();

        // Assert
        assertEq(totalAssetsAfterDeposit, initialTotalAssets + depositAmount, "Total assets should increase by the deposit amount");
    }

    function testFuzzConvertToSharesBeforeAnyDeposits(uint ethAmount) public {

       vm.assume(ethAmount > 0 ether && ethAmount <= 10000 ether);
        // Act
        uint256 sharesBeforeDeposit = yneth.previewDeposit(ethAmount);

        // Assert
        assertEq(sharesBeforeDeposit, ethAmount, "Shares should equal ETH amount before any deposits");
    }

    function testFuzzConvertToSharesAfterFirstDeposit(uint256 firstDepositAmount, uint256 secondDepositAmount) public {
        // Arrange
        vm.assume(firstDepositAmount > 0 ether && firstDepositAmount <= 10000 ether);
        vm.assume(secondDepositAmount > 0 ether && secondDepositAmount <= 10000 ether);
        yneth.depositETH{value: firstDepositAmount}(address(this));

        // Act
        uint256 sharesAfterFirstDeposit = yneth.previewDeposit(secondDepositAmount);

        uint256 expectedShares = secondDepositAmount;

        // Assert
        assertEq(sharesAfterFirstDeposit, expectedShares, "Fuzz: Shares should match expected shares");
        
        uint256 totalAssetsAfterDeposit = yneth.totalAssets();
        // Assert
        assertEq(totalAssetsAfterDeposit, firstDepositAmount, "Total assets should increase by the deposit amount");
    }

    function testFuzzConvertToSharesAfterSecondDeposit(uint256 firstDepositAmount, uint256 secondDepositAmount, uint256 thirdDepositAmount) public {

        vm.assume(firstDepositAmount > 0 ether && firstDepositAmount <= 10000 ether);
        vm.assume(secondDepositAmount > 0 ether && secondDepositAmount <= 10000 ether);
        vm.assume(thirdDepositAmount > 0 ether && thirdDepositAmount <= 10000 ether);

        yneth.depositETH{value: firstDepositAmount}(address(this));

        uint256 totalAssetsAfterFirstDeposit = yneth.totalAssets();
        assertEq(totalAssetsAfterFirstDeposit, firstDepositAmount, "Total assets should match first deposit amount");
        yneth.depositETH{value: secondDepositAmount}(address(this));

        // Assuming initial total assets were equal to firstDepositAmount before rewards
        uint256 expectedTotalAssets = firstDepositAmount + secondDepositAmount; 
        uint256 totalAssetsAfterSecondDeposit = yneth.totalAssets();
        assertEq(totalAssetsAfterSecondDeposit, expectedTotalAssets, "Total assets should match expected total after second deposit");

                // Assuming initial total supply equals shares after first deposit
        uint256 expectedTotalSupply = firstDepositAmount + secondDepositAmount; 
        uint256 totalSupplyAfterSecondDeposit = yneth.totalSupply();
        // TODO: figure out this precision issue
        assertTrue(compareWithThreshold(totalSupplyAfterSecondDeposit, expectedTotalSupply, 1), "Total supply should match expected total supply after second deposit");

        expectedTotalSupply = totalSupplyAfterSecondDeposit;
        // Act
        uint256 sharesAfterSecondDeposit = yneth.previewDeposit(thirdDepositAmount);

        // Using the formula from ynETH to calculate expectedShares
        uint256 expectedShares = Math.mulDiv(
                thirdDepositAmount,
                expectedTotalSupply,
                expectedTotalAssets,
                Math.Rounding.Floor
            );

        // Assert
        assertEq(sharesAfterSecondDeposit, expectedShares, "Shares should equal ETH amount after second deposit");
    }

    function testFuzzConvertToSharesAfterDepositAndRewardsUsingRewardsReceiver(uint256 ethAmount, uint256 rawRewardAmount) public {

        vm.assume(ethAmount > 0 ether && ethAmount <= 10000 ether);
        vm.assume(rawRewardAmount > 0 ether && rawRewardAmount <= 10000 ether);
        // Arrange
        //uint256 ethAmount = 1 ether;
        yneth.depositETH{value: ethAmount}(address(this));
        //uint256 rawRewardAmount = 1 ether;
        // Deal directly to the executionLayerReceiver
        vm.deal(address(executionLayerReceiver), rawRewardAmount);
        // Simulate RewardsDistributor processing rewards which are then forwarded to yneth
        rewardsDistributor.processRewards();
        uint256 expectedNetRewardAmount = rawRewardAmount * 9 / 10;

        // Act
        uint256 sharesAfterDepositAndRewards = yneth.previewDeposit(ethAmount);

        uint256 expectedTotalAssets = ethAmount + expectedNetRewardAmount; // Assuming initial total assets were equal to ethAmount before rewards
        uint256 expectedTotalSupply = ethAmount; // Assuming initial total supply equals shares after first deposit
        // Using the formula from ynETH to calculate expectedShares
        uint256 expectedShares = Math.mulDiv(
                ethAmount,
                expectedTotalSupply,
                expectedTotalAssets,
                Math.Rounding.Floor
            );

        // Assert
        assertTrue(compareWithThreshold(sharesAfterDepositAndRewards, expectedShares, 1), "Shares should be within threshold of 1 of the expected ETH amount after deposit and rewards processed through RewardsReceiver");
    }

    function testRewardsDistributionToYnETHAndFeeReceiver() public {
        // Arrange
        uint256 initialYnETHBalance = address(yneth).balance;
        uint256 initialFeeReceiverBalance = address(actors.admin.FEE_RECEIVER).balance;
        uint256 rewardAmount = 10 ether;
        uint256 expectedFees = rewardAmount * rewardsDistributor.feesBasisPoints() / 10000;
        uint256 expectedNetRewards = rewardAmount - expectedFees;

        // Simulate sending rewards to the executionLayerReceiver
        vm.deal(address(executionLayerReceiver), rewardAmount);

        // Act
        rewardsDistributor.processRewards();

        // Assert
        uint256 finalYnETHBalance = address(yneth).balance;
        uint256 finalFeeReceiverBalance = address(actors.admin.FEE_RECEIVER).balance;

        assertEq(finalYnETHBalance, initialYnETHBalance + expectedNetRewards, "Incorrect ynETH balance after rewards distribution");
        assertEq(finalFeeReceiverBalance, initialFeeReceiverBalance + expectedFees, "Incorrect feeReceiver balance after rewards distribution");
    }

    function testPauseDepositETHFunctionality() public {
        // Arrange
        vm.prank(actors.ops.PAUSE_ADMIN);
        yneth.pauseDeposits();

        // Act & Assert
        bool pauseState = yneth.depositsPaused();
        assertTrue(pauseState, "Deposit ETH should be paused after setting pause state to true");

        // Trying to deposit ETH while paused
        uint256 depositAmount = 1 ether;
        vm.expectRevert(ynETH.Paused.selector);
        yneth.depositETH{value: depositAmount}(address(this));

        // Unpause and try depositing again
        vm.prank(actors.admin.UNPAUSE_ADMIN);
        yneth.unpauseDeposits();
        pauseState = yneth.depositsPaused();

        assertFalse(pauseState, "Deposit ETH should be unpaused after setting pause state to false");

        // Deposit should succeed now
        yneth.depositETH{value: depositAmount}(address(this));
        uint256 ynETHBalance = yneth.balanceOf(address(this));
        assertGt(ynETHBalance, 0, "ynETH balance should be greater than 0 after deposit");
    }

    function testTransferFailsForNonWhitelistedAddresses() public {
        // Arrange
        uint256 transferAmount = 1 ether;
        address nonWhitelistedAddress = address(4); // An arbitrary address not in the whitelist
        address recipient = address(5); // An arbitrary recipient address

        // Act & Assert
        // Ensure transfer from a non-whitelisted address reverts
        vm.expectRevert(ynBase.TransfersPaused.selector);
        vm.prank(nonWhitelistedAddress);
        yneth.transfer(recipient, transferAmount);
    }

    function testTransferSucceedsForWhitelistedAddress() public {
        // Arrange
        uint256 depositAmount = 1 ether;
        address whitelistedAddress = actors.eoa.DEFAULT_SIGNER; // Using the pre-defined whitelisted address from setup
        address recipient = address(6); // An arbitrary recipient address


        yneth.depositETH{value: depositAmount}(whitelistedAddress); 

        uint256 transferAmount = yneth.balanceOf(whitelistedAddress);

        // Act
        address[] memory whitelist = new address[](1);
        whitelist[0] = whitelistedAddress;
        vm.prank(actors.admin.UNPAUSE_ADMIN);
        yneth.addToPauseWhitelist(whitelist); // Whitelisting the address
        vm.prank(whitelistedAddress);
        yneth.transfer(recipient, transferAmount);

        // Assert
        uint256 recipientBalance = yneth.balanceOf(recipient);
        assertEq(recipientBalance, transferAmount, "Transfer did not succeed for whitelisted address");
    }

    function testAddToPauseWhitelist() public {
        // Arrange
        address[] memory addressesToWhitelist = new address[](2);
        addressesToWhitelist[0] = address(1);
        addressesToWhitelist[1] = address(2);

        // Act
        vm.prank(actors.admin.UNPAUSE_ADMIN);
        yneth.addToPauseWhitelist(addressesToWhitelist);

        // Assert
        assertTrue(yneth.pauseWhiteList(addressesToWhitelist[0]), "Address 1 should be whitelisted");
        assertTrue(yneth.pauseWhiteList(addressesToWhitelist[1]), "Address 2 should be whitelisted");
    }

    function testTransferSucceedsForNewlyWhitelistedAddress() public {
        // Arrange
        uint256 depositAmount = 1 ether;
        address newWhitelistedAddress = vm.addr(7); // Using a new address for whitelisting
        address recipient = address(8); // An arbitrary recipient address

        address[] memory whitelistAddresses = new address[](1);
        whitelistAddresses[0] = newWhitelistedAddress;
        vm.prank(actors.admin.UNPAUSE_ADMIN);
        yneth.addToPauseWhitelist(whitelistAddresses); // Whitelisting the new address
        vm.deal(newWhitelistedAddress, depositAmount); // Providing the new whitelisted address with some ETH
        vm.prank(newWhitelistedAddress);
        yneth.depositETH{value: depositAmount}(newWhitelistedAddress); // Depositing ETH to get ynETH

        uint256 transferAmount = yneth.balanceOf(newWhitelistedAddress);

        // Act
        vm.prank(newWhitelistedAddress);
        yneth.transfer(recipient, transferAmount);

        // Assert
        uint256 recipientBalance = yneth.balanceOf(recipient);
        assertEq(recipientBalance, transferAmount, "Transfer did not succeed for newly whitelisted address");
    }

    function testTransferEnabledForAnyAddress() public {
        // Arrange
        uint256 depositAmount = 1 ether;
        address arbitraryAddress = vm.addr(9999); // Using an arbitrary address
        address recipient = address(10000); // An arbitrary recipient address

        vm.deal(arbitraryAddress, depositAmount); // Providing the arbitrary address with some ETH
        vm.prank(arbitraryAddress);
        yneth.depositETH{value: depositAmount}(arbitraryAddress); // Depositing ETH to get ynETH

        uint256 transferAmount = yneth.balanceOf(arbitraryAddress);

        // Act
        vm.prank(actors.admin.UNPAUSE_ADMIN);
        yneth.unpauseTransfers(); // Unpausing transfers for all
        
        vm.prank(arbitraryAddress);
        yneth.transfer(recipient, transferAmount);

        // Assert
        uint256 recipientBalance = yneth.balanceOf(recipient);
        assertEq(recipientBalance, transferAmount, "Transfer did not succeed for any address after enabling transfers");
    }

    function testDepositEthWithZeroEth() public {
        bytes memory encodedError = abi.encodeWithSelector(ynETH.ZeroETH.selector);
        vm.expectRevert(encodedError);
        yneth.depositETH{value: 0}(address(this));
    }

    function testReceiveRewardsWithBadRewardsDistributor() public {
        bytes memory encodedError = abi.encodeWithSelector(ynETH.NotRewardsDistributor.selector);
        vm.expectRevert(encodedError);
        yneth.receiveRewards();
    }

    function testWithdrawETHWithZeroBalance() public {
        bytes memory encodedError = abi.encodeWithSelector(ynETH.InsufficientBalance.selector);
        vm.startPrank(address(stakingNodesManager));
        vm.expectRevert(encodedError);
        yneth.withdrawETH(1);
        vm.stopPrank();
    } 
}


contract ynETHTotalAssetsTest is IntegrationBaseTest {
    function testFuzzTotalAssetsWithDifferentDeposits(uint256 depositAmount1, uint256 depositAmount2) public {
        // Arrange
        vm.assume(depositAmount1 > 0 ether && depositAmount1 <= 10000 ether);
        vm.assume(depositAmount2 > 0 ether && depositAmount2 <= 10000 ether);
        uint256 initialTotalAssets = yneth.totalAssets();

        // Act
        yneth.depositETH{value: depositAmount1}(address(this));
        uint256 totalAssetsAfterFirstDeposit = yneth.totalAssets();
        yneth.depositETH{value: depositAmount2}(address(this));
        uint256 totalAssetsAfterSecondDeposit = yneth.totalAssets();

        // Assert
        assertEq(totalAssetsAfterFirstDeposit, initialTotalAssets + depositAmount1, "Total assets should increase by the first deposit amount");
        assertEq(totalAssetsAfterSecondDeposit, initialTotalAssets + depositAmount1 + depositAmount2, "Total assets should increase by the sum of both deposit amounts");
    }

    function testFuzzTotalAssetsWithRewards(uint256 depositAmount, uint256 rewardAmount) public {
        // Arrange
        vm.assume(depositAmount > 0 ether && depositAmount <= 10000 ether);
        vm.assume(rewardAmount > 0 ether && rewardAmount <= 10000 ether);
        yneth.depositETH{value: depositAmount}(address(this));
        uint256 totalAssetsAfterDeposit = yneth.totalAssets();

        // Act
        vm.deal(address(rewardsDistributor), rewardAmount);
        vm.startPrank(address(rewardsDistributor));
        yneth.receiveRewards{value: rewardAmount}();
        uint256 totalAssetsAfterRewards = yneth.totalAssets();

        // Assert
        assertEq(totalAssetsAfterRewards, totalAssetsAfterDeposit + rewardAmount, "Total assets should increase by the reward amount");
    }

    function skiptestFuzzTotalAssetsWithRewardsInEigenPods(uint256 depositAmount, uint256 rewardAmount, uint256 stakingNodeCount) public {
        // Arrange
        vm.assume(depositAmount > 0 ether && depositAmount <= 10000 ether);
        vm.assume(rewardAmount > 0 ether && rewardAmount <= 5000 ether); // Assuming rewards are less than or equal to half the deposit for this test
        uint256 maxStakingNodeCount = stakingNodesManager.maxNodeCount();
        vm.assume(stakingNodeCount > 0 && stakingNodeCount <= maxStakingNodeCount);

        yneth.depositETH{value: depositAmount}(address(this));
        uint256 totalAssetsAfterDeposit = yneth.totalAssets();

        assertEq(totalAssetsAfterDeposit, depositAmount, "Total assets should increase by the deposit amount after rewards in eigenPods");

        // deal beacon-chain rewards into eigenpods
        uint256 totalRewards = 0;
        for (uint256 i = 0; i < stakingNodeCount; i++) {
            vm.prank(actors.ops.STAKING_NODE_CREATOR);
            IStakingNode stakingNode = stakingNodesManager.createStakingNode();
            IEigenPod eigenPod = stakingNode.eigenPod();
            vm.deal(address(eigenPod), rewardAmount);
            totalRewards += rewardAmount;
            rewardAmount += 1 ether;
        }

        // NOTE: rewards sitting in EigenPods are NOT counted as total TVL
        uint256 totalAssetsAfterRewards = yneth.totalAssets();
        assertEq(totalAssetsAfterRewards, depositAmount, "Total assets should increase by the reward amount in eigenPods");
    }

}