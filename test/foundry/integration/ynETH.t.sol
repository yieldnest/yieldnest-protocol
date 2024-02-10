import "./IntegrationBaseTest.sol";
import "forge-std/console.sol";
import "../../../src/ynETH.sol";


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
        yneth.setIsDepositETHPaused(true);

        uint256 depositAmount = 1 ether;
        vm.deal(address(this), depositAmount);
        // Arrange

        bool pauseState = yneth.isDepositETHPaused();
        console.log("Pause state:", pauseState);

        // Act & Assert
        vm.expectRevert(ynETH.Paused.selector);
        yneth.depositETH{value: depositAmount}(address(this));
    }
}
