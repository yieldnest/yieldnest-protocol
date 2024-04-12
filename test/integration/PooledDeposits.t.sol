pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../../src/PooledDeposits.sol";
import "../../src/interfaces/IynETH.sol";
import "test/integration/IntegrationBaseTest.sol";

contract PooledDepositsTest is IntegrationBaseTest {

    function createPooledDeposits() internal returns (PooledDeposits pooledDeposits, address owner) {
        PooledDeposits implementation = new PooledDeposits();
        bytes memory initData = abi.encodeWithSelector(PooledDeposits.initialize.selector, address(this));
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(implementation), address(this), initData);
        pooledDeposits = PooledDeposits(payable(address(proxy)));
        owner = address(this);
        return (pooledDeposits, owner);
    }

    function testDepositFuzz(uint256 depositAmount) public {
        // Fuzz input
        vm.assume(depositAmount > 0.01 ether && depositAmount <= 100 ether); // Assuming a reasonable range for deposit amounts
        // Arrange
        (PooledDeposits pooledDeposits, ) = createPooledDeposits();
        address depositor = address(this);

        // Act
        vm.deal(depositor, depositAmount);
        vm.startPrank(depositor);
        pooledDeposits.deposit{value: depositAmount}();
        vm.stopPrank();

        // Assert
        assertEq(pooledDeposits.balances(depositor), depositAmount, "Deposit amount should be recorded in the depositor's balance");
    }
    function testMultipleSequentialDepositsForSameUserFuzz(uint256 depositAmount1) public {
        // Fuzz inputs
        vm.assume(depositAmount1 > 0.01 ether && depositAmount1 <= 100 ether); // Assuming a reasonable range for the first deposit amount
        uint256 depositAmount2 = depositAmount1 + 100 ether;

        // Arrange
        (PooledDeposits pooledDeposits, ) = createPooledDeposits();
        address depositor = address(this);
        uint256 expectedBalanceAfterFirstDeposit = depositAmount1;
        uint256 expectedBalanceAfterSecondDeposit = depositAmount1 + depositAmount2;

        // Act and Assert
        vm.deal(depositor, expectedBalanceAfterSecondDeposit);
        vm.startPrank(depositor);
        pooledDeposits.deposit{value: depositAmount1}();
        assertEq(pooledDeposits.balances(depositor), expectedBalanceAfterFirstDeposit, "Balance after first deposit incorrect");
        pooledDeposits.deposit{value: depositAmount2}();
        assertEq(pooledDeposits.balances(depositor), expectedBalanceAfterSecondDeposit, "Balance after second deposit incorrect");
        vm.stopPrank();
    }

    function testFinalizeDeposits() public {
        // Arrange
        (PooledDeposits pooledDeposits, address owner) = createPooledDeposits();
        address[] memory depositors = new address[](1);
        depositors[0] = address(this);
        uint256 depositAmount = 1 ether;
        vm.deal(address(this), depositAmount);
        pooledDeposits.deposit{value: depositAmount}();

        // Set ynETH before finalizing deposits
        vm.prank(owner);
        pooledDeposits.setYnETH(IynETH(address(yneth)));

        // Act
        vm.warp(block.timestamp + 3 days); // Move time forward to allow finalizing deposits
        pooledDeposits.finalizeDeposits(depositors);

        // Assert
        // Assuming ynETH's depositETH function simply mints 1:1 ynETH for ETH deposited
        uint256 expectedYnETHAmount = depositAmount;
        assertEq(yneth.balanceOf(address(this)), expectedYnETHAmount, "ynETH should be minted and sent to the depositor");
    }

    function testFinalizeDepositsFuzz(uint8 depositorsCount, uint256 baseDepositAmount) public {
        // Fuzz inputs
        vm.assume(depositorsCount > 0 && depositorsCount <= 100); // Limiting the number of depositors to a reasonable range
        vm.assume(baseDepositAmount > 0.01 ether && baseDepositAmount <= 100 ether); // Assuming a reasonable range for deposit amounts

        // Arrange
        (PooledDeposits pooledDeposits, address owner) = createPooledDeposits();
        address[] memory depositors = new address[](depositorsCount);
        uint256 totalDepositAmount = 0;
        uint256 varyingDepositAmount = baseDepositAmount;

        for (uint8 i = 0; i < depositorsCount; i++) {
            address depositor = address(uint160(uint(keccak256(abi.encodePacked(i, block.timestamp)))));
            depositors[i] = depositor;
            vm.deal(depositor, varyingDepositAmount);
            vm.prank(depositor);
            pooledDeposits.deposit{value: varyingDepositAmount}();
            totalDepositAmount += varyingDepositAmount;
            varyingDepositAmount += 1 ether; // Increase the deposit amount by 1 ether for each depositor
        }

        // Set ynETH before finalizing deposits
        vm.prank(owner);
        pooledDeposits.setYnETH(IynETH(address(yneth)));

        // Act
        vm.warp(block.timestamp + 3 days); // Move time forward to allow finalizing deposits
        pooledDeposits.finalizeDeposits(depositors);

        // Assert
        // Assuming ynETH's depositETH function simply mints 1:1 ynETH for ETH deposited
        varyingDepositAmount = baseDepositAmount; // Reset varyingDepositAmount for assertion checks
        for (uint8 i = 0; i < depositorsCount; i++) {
            uint256 expectedYnETHAmount = varyingDepositAmount;
            assertEq(yneth.balanceOf(depositors[i]), expectedYnETHAmount, "ynETH should be minted and sent to the depositor");
            varyingDepositAmount += 1 ether; // Increase the expected amount by 1 ether for each depositor
        }
    }

    function testDepositAfterSettingYnETH() public {
        // Arrange
        (PooledDeposits pooledDeposits, address owner) = createPooledDeposits();
        uint256 depositAmount = 1 ether;
        vm.deal(address(this), depositAmount);

                // Set ynETH before finalizing deposits
        vm.prank(owner);
        pooledDeposits.setYnETH(IynETH(address(yneth)));

        // Act & Assert
        vm.expectRevert(PooledDeposits.YnETHIsSet.selector);
        pooledDeposits.deposit{value: depositAmount}();
    }

    function testFinalizeDepositsBeforeSettingYnETH() public {
        // Arrange
        (PooledDeposits pooledDeposits,) = createPooledDeposits();
        address[] memory depositors = new address[](1);
        depositors[0] = address(this);

        // Act & Assert
        vm.expectRevert(PooledDeposits.YnETHNotSet.selector);
        pooledDeposits.finalizeDeposits(depositors);
    }

    function testDepositZeroAmount() public {
        // Arrange
        (PooledDeposits pooledDeposits,) = createPooledDeposits();

        // Act & Assert
        vm.expectRevert(PooledDeposits.DepositMustBeGreaterThanZero.selector);
        pooledDeposits.deposit{value: 0}();
    }

    function testFinalizeDepositsWithNoDepositors() public {
        // Arrange
        (PooledDeposits pooledDeposits, address owner) = createPooledDeposits();
        address[] memory depositors = new address[](0);

        // Set ynETH before finalizing deposits
        vm.prank(owner);
        pooledDeposits.setYnETH(IynETH(address(yneth)));

        pooledDeposits.finalizeDeposits(depositors);

        // Assert
        // No revert means success, but nothing to assert as there were no depositors
    }

    function testDirectETHSendForDepositFuzzed(uint256 depositAmount) public {
        // Only proceed with valid deposit amounts to avoid unnecessary test failures
        vm.assume(depositAmount > 0 && depositAmount <= 100 ether);
        
        // Arrange
        (PooledDeposits pooledDeposits,) = createPooledDeposits();
        vm.deal(address(this), depositAmount);

        // Act
        (bool success, ) = address(pooledDeposits).call{value: depositAmount}("");

        // Assert
        assertTrue(success, "ETH send should succeed");
        assertEq(pooledDeposits.balances(address(this)), depositAmount, "Deposit amount should be recorded in balances");
    }

    function testFinalizeDepositsMultipleTimesForSameUser() public {
        // Arrange
        (PooledDeposits pooledDeposits, address owner) = createPooledDeposits();
        address[] memory depositors = new address[](1);
        depositors[0] = address(this);
        uint256 depositAmount = 1 ether;
        vm.deal(address(this), depositAmount);
        pooledDeposits.deposit{value: depositAmount}();

        // Set ynETH before finalizing deposits
        vm.prank(owner);
        pooledDeposits.setYnETH(IynETH(address(yneth)));

        // Act
        vm.warp(block.timestamp + 1 days + 1); // Move time forward to allow finalizing deposits
        pooledDeposits.finalizeDeposits(depositors);

        // Assert first finalize
        uint256 sharesAfterFirstFinalize = IynETH(address(yneth)).balanceOf(address(this));
        assertTrue(sharesAfterFirstFinalize > 0, "Shares should be allocated after first finalize");

        // Check balance after first finalize
        uint256 balanceAfterFirstFinalize = pooledDeposits.balances(address(this));
        assertEq(balanceAfterFirstFinalize, 0, "Balance should be 0 after first finalize");

        // Attempt to finalize again
        pooledDeposits.finalizeDeposits(depositors);

        // Assert second finalize
        uint256 sharesAfterSecondFinalize = IynETH(address(yneth)).balanceOf(address(this));
        assertEq(sharesAfterFirstFinalize, sharesAfterSecondFinalize, "Shares should not change after second finalize");

        // Check balance after second finalize
        uint256 balanceAfterSecondFinalize = pooledDeposits.balances(address(this));
        assertEq(balanceAfterSecondFinalize, 0, "Balance should remain 0 after second finalize");
    }
    
    receive() external payable {}
}

