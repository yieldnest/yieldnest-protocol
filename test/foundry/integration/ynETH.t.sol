import "./IntegrationBaseTest.sol";

contract ynETHIntegrationTest is IntegrationBaseTest {

    function testDepositETH() public {

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

    function testFailDepositETHWhenPaused() public {
        // Arrange
        yneth.setIsDepositETHPaused(true);

        // Act & Assert
        yneth.depositETH{value: 1 ether}(address(this));
    }
}
