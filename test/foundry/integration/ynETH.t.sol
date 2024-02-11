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

    function testPreviewDeposit() public {
        // Arrange
        uint256 depositAmount = 1 ether;
        vm.deal(address(this), depositAmount);

        // Act
        uint256 shares = yneth.previewDeposit(depositAmount);

        // Assert
        assertTrue(shares > 0, "Preview deposit should return more than 0 shares");
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

    function testConvertToSharesBeforeAnyDeposits() public {
        // Arrange
        uint256 ethAmount = 1 ether;

        // Act
        uint256 sharesBeforeDeposit = yneth.previewDeposit(ethAmount);

        // Assert
        assertEq(sharesBeforeDeposit, ethAmount, "Shares should equal ETH amount before any deposits");
    }

    function testConvertToSharesAfterFirstDeposit() public {
        // Arrange
        uint256 ethAmount = 1 ether;
        yneth.depositETH{value: ethAmount}(address(this));

        // Act
        uint256 sharesAfterFirstDeposit = yneth.previewDeposit(ethAmount);

        uint expectedShares = ethAmount - startingExchangeAdjustmentRate * ethAmount / 10000;

        // Assert
        assertEq(sharesAfterFirstDeposit, expectedShares, "Shares should equal ETH amount after first deposit");
    }

    function testConvertToSharesAfterSecondDeposit() public {
        // Arrange
        uint256 ethAmount = 1 ether;
        yneth.depositETH{value: ethAmount}(address(this));
        yneth.depositETH{value: ethAmount}(address(this));

        // Act
        uint256 sharesAfterSecondDeposit = yneth.previewDeposit(ethAmount);

        uint256 expectedTotalAssets = 2 * ethAmount; // Assuming initial total assets were equal to ethAmount before rewards
        uint256 expectedTotalSupply = 2 * ethAmount - startingExchangeAdjustmentRate * ethAmount / 10000; // Assuming initial total supply equals shares after first deposit
        // Using the formula from ynETH to calculate expectedShares
        // Assuming exchangeAdjustmentRate is applied as in the _convertToShares function of ynETH
        uint256 expectedShares = Math.mulDiv(
                ethAmount,
                expectedTotalSupply * uint256(10000 - startingExchangeAdjustmentRate),
                expectedTotalAssets * uint256(10000),
                Math.Rounding.Floor
            );

        // Assert
        assertEq(sharesAfterSecondDeposit, expectedShares, "Shares should equal ETH amount after second deposit");
    }

    function testConvertToSharesAfterDepositAndRewardsUsingRewardsReceiver() public {
        // Arrange
        uint256 ethAmount = 1 ether;
        yneth.depositETH{value: ethAmount}(address(this));
        uint256 rawRewardAmount = 1 ether;
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
        // Assuming exchangeAdjustmentRate is applied as in the _convertToShares function of ynETH
        uint256 expectedShares = Math.mulDiv(
                ethAmount,
                expectedTotalSupply * uint256(10000 - startingExchangeAdjustmentRate),
                expectedTotalAssets * uint256(10000),
                Math.Rounding.Floor
            );

        // Assert
        assertEq(sharesAfterDepositAndRewards, expectedShares, "Shares should equal ETH amount after deposit and rewards processed through RewardsReceiver");
    }


    function testPauseDepositETHFunctionality() public {
        // Arrange
        yneth.setIsDepositETHPaused(true);

        // Act & Assert
        bool pauseState = yneth.isDepositETHPaused();
        assertTrue(pauseState, "Deposit ETH should be paused after setting pause state to true");

        // Trying to deposit ETH while paused
        uint256 depositAmount = 1 ether;
        vm.expectRevert(ynETH.Paused.selector);
        yneth.depositETH{value: depositAmount}(address(this));

        // Unpause and try depositing again
        yneth.setIsDepositETHPaused(false);
        pauseState = yneth.isDepositETHPaused();
        assertFalse(pauseState, "Deposit ETH should be unpaused after setting pause state to false");

        // Deposit should succeed now
        yneth.depositETH{value: depositAmount}(address(this));
        uint256 ynETHBalance = yneth.balanceOf(address(this));
        assertGt(ynETHBalance, 0, "ynETH balance should be greater than 0 after deposit");
    }
}
