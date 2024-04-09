import "forge-std/Test.sol";
import "../../src/PooledDeposits.sol";
import "../../src/interfaces/IynETH.sol";
import "test/integration/IntegrationBaseTest.sol";


contract PooledDepositsTest is IntegrationBaseTest {
    function testDeposit() public {
        // Arrange
        PooledDeposits pooledDeposits = new PooledDeposits(IynETH(address(yneth)), block.timestamp + 2 days);
        uint256 depositAmount = 1 ether;
        address depositor = address(this);

        // Act
        vm.deal(depositor, depositAmount);
        vm.startPrank(depositor);
        pooledDeposits.deposit{value: depositAmount}();
        vm.stopPrank();

        // Assert
        assertEq(pooledDeposits.balances(depositor), depositAmount, "Deposit amount should be recorded in the depositor's balance");
    }

    function testFinalizeDeposits() public {
        // Arrange
        PooledDeposits pooledDeposits = new PooledDeposits(IynETH(address(yneth)), block.timestamp + 2 days);
        address[] memory depositors = new address[](1);
        depositors[0] = address(this);
        uint256 depositAmount = 1 ether;
        vm.deal(address(this), depositAmount);
        pooledDeposits.deposit{value: depositAmount}();

        // Act
        vm.warp(block.timestamp + 3 days); // Move time forward to allow finalizing deposits
        pooledDeposits.finalizeDeposits(depositors);

        // Assert
        // Assuming ynETH's depositETH function simply mints 1:1 ynETH for ETH deposited
        uint256 expectedYnETHAmount = depositAmount;
        assertEq(yneth.balanceOf(address(this)), expectedYnETHAmount, "ynETH should be minted and sent to the depositor");
    }

    receive() external payable {}
}

