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
}