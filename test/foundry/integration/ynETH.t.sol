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

    function testPauseDepositETH() public {
        // Arrange
        yneth.setIsDepositETHPaused(true);

        // Act & Assert
        bool pauseState = yneth.isDepositETHPaused();
        assertTrue(pauseState, "Deposit ETH should be paused");
    }

    function testUnpauseDepositETH() public {
        // Arrange
        yneth.setIsDepositETHPaused(true);
        yneth.setIsDepositETHPaused(false);

        // Act & Assert
        bool pauseState = yneth.isDepositETHPaused();
        assertFalse(pauseState, "Deposit ETH should be unpaused");
    }

    // function testReceiveRewards() public {
    //     // Arrange
    //     uint256 rewardAmount = 0.5 ether;
    //     vm.deal(address(rewardsDistributor), rewardAmount);

    //     uint256 initialPoolBalance = yneth.totalAssets();

    //     // Act
    //     rewardsDistributor.sendValue(address(yneth), rewardAmount);

    //     // Assert
    //     uint256 finalPoolBalance = yneth.totalAssets();
    //     assertEq(finalPoolBalance, initialPoolBalance + rewardAmount, "Reward was not correctly added to the pool");
    // }
}
