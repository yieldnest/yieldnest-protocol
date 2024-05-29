// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import { ReferralDepositAdapter } from "src/ReferralDepositAdapter.sol";
import "forge-std/Vm.sol";
import "test/integration/IntegrationBaseTest.sol";

contract ReferralDepositAdapterTest is IntegrationBaseTest {

    function testDepositETHWithReferral() public {
        address depositor = vm.addr(3000); // Custom depositor address
        uint256 depositAmount = 1 ether;
        vm.deal(depositor, depositAmount);
        // Arrange
        uint256 initialETHBalance = depositor.balance;

        address referrer = vm.addr(9000);
        vm.prank(depositor);
        referralDepositAdapter.depositWithReferral{value: depositAmount}(depositor, referrer);

        // Assert
        uint256 finalETHBalance = depositor.balance;
        uint256 ynETHBalance = yneth.balanceOf(depositor);
        uint256 expectedETHBalance = initialETHBalance - depositAmount;

        assertEq(finalETHBalance, expectedETHBalance, "ETH was not correctly deducted from sender");
        assertGt(ynETHBalance, 0, "ynETH balance should be greater than 0 after deposit");
    }

    function testDepositETWithReferralWhenPaused() public {
        // Arrange
        vm.prank(actors.ops.PAUSE_ADMIN);
        yneth.pauseDeposits();

        uint256 depositAmount = 1 ether;
        vm.deal(address(this), depositAmount);

        // Act & Assert
        vm.expectRevert(ynETH.Paused.selector);
        address referrer = vm.addr(9000);
        referralDepositAdapter.depositWithReferral{value: depositAmount}(address(this), referrer);
    }

    function testDepositWithReferralZeroAmount() public {
        address depositor = vm.addr(3000);
        address referrer = vm.addr(9000);
        uint256 depositAmount = 0 ether; // Zero deposit amount
        vm.deal(depositor, depositAmount);

        vm.prank(depositor);
        vm.expectRevert(ReferralDepositAdapter.ZeroETH.selector);
        referralDepositAdapter.depositWithReferral{value: depositAmount}(depositor, referrer);
    }

    function testDepositWithReferralZeroAddressReferrer() public {
        address depositor = vm.addr(3000);
        uint256 depositAmount = 1 ether;
        vm.deal(depositor, depositAmount);

        vm.prank(depositor);
        vm.expectRevert(ReferralDepositAdapter.ZeroAddress.selector);
        referralDepositAdapter.depositWithReferral{value: depositAmount}(depositor, address(0));
    }

    function testDepositWithReferralZeroAddressReceiver() public {
        address referrer = vm.addr(9000);
        uint256 depositAmount = 1 ether;
        vm.deal(address(0), depositAmount); // This should not be possible, but testing for code robustness

        vm.expectRevert(ReferralDepositAdapter.ZeroAddress.selector);
        referralDepositAdapter.depositWithReferral{value: depositAmount}(address(0), referrer);
    }

    function testPublishReferrals() public {
 
        IReferralDepositAdapter.ReferralInfo[] memory referrals = new IReferralDepositAdapter.ReferralInfo[](1);
        {
                    // Arrange
            address depositor = vm.addr(1000);
            address referrer = vm.addr(2000);
            address referee = vm.addr(3000);
            uint256 amountDeposited = 1 ether;
            uint256 shares = 100;
            uint256 timestamp = block.timestamp;
            referrals[0] = IReferralDepositAdapter.ReferralInfo({
                depositor: depositor,
                referrer: referrer,
                referee: referee,
                amountDeposited: amountDeposited,
                shares: shares,
                timestamp: timestamp
            });
        }

        
        vm.startPrank(actors.ops.REFERAL_PUBLISHER);
        referralDepositAdapter.publishReferrals(referrals);
    }

    function testUnauthorizedPublishReferrals() public {
        IReferralDepositAdapter.ReferralInfo[] memory referrals = new IReferralDepositAdapter.ReferralInfo[](1);
        {
            // Arrange
            address depositor = vm.addr(1000);
            address referrer = vm.addr(2000);
            address referee = vm.addr(3000);
            uint256 amountDeposited = 1 ether;
            uint256 shares = 100;
            uint256 timestamp = block.timestamp;
            referrals[0] = IReferralDepositAdapter.ReferralInfo({
                depositor: depositor,
                referrer: referrer,
                referee: referee,
                amountDeposited: amountDeposited,
                shares: shares,
                timestamp: timestamp
            });
        }

        // Act
        address unauthorizedUser = vm.addr(4000);
        vm.prank(unauthorizedUser);
        vm.expectRevert();
        referralDepositAdapter.publishReferrals(referrals);
    }
}