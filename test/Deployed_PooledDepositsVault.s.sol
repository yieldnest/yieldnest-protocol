// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {PooledDepositsVault} from "src/PooledDepositsVault.sol";
import {IynETH} from "src/interfaces/IynETH.sol";
import "test/integration/IntegrationBaseTest.sol";
import "src/ynBase.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";


contract MockYnETH is ERC20 {
    address public admin;

    constructor() ERC20("Mock YnETH", "mYnETH") {
        admin = msg.sender;
    }

    function depositETH(address receiver) public payable returns (uint256) {
        require(msg.value > 0, "Deposit must be greater than zero");
        _mint(receiver, msg.value);
        return msg.value;
    }

    function mint(address to, uint256 amount) public  {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) public {
        _burn(from, amount);
    }

}


contract Deployed_PooledDepositsVaultTest is Test {

    PooledDepositsVault public pooledDepositsVault;

    function setUp() public {
        pooledDepositsVault = PooledDepositsVault(payable(0x6CaaD94F29C7Bf1a569219b1ec400A2506fd4780));
    }

    function testDepositFromArbitraryAddress() public {
        // Arrange
        address arbitraryDepositor = address(0x123);
        uint256 depositAmount = 1 ether;

        // Act
        vm.deal(arbitraryDepositor, depositAmount);
        vm.prank(arbitraryDepositor);
        pooledDepositsVault.deposit{value: depositAmount}();

        // Assert
        uint256 balance = pooledDepositsVault.balances(arbitraryDepositor);
        assertEq(balance, depositAmount, "Balance should match the deposit amount");
    }

    function testDepositAndSetYNETHAndThenToZeroAgain() public {
        // Arrange
        address arbitraryDepositor = address(0x456);
        uint256 depositAmount = 2 ether;
        MockYnETH yneth = new MockYnETH();
        address ynethAddress = address(yneth);
        // Act
        vm.deal(arbitraryDepositor, depositAmount);
        vm.prank(arbitraryDepositor);
        pooledDepositsVault.deposit{value: depositAmount}();

        // https://etherscan.io/address/0xe1fac59031520fd1eb901da990da12af295e6731#readProxyContract%23F9
        vm.prank(0xE1fAc59031520FD1eb901da990Da12Af295e6731);
        pooledDepositsVault.setYnETH(IynETH(ynethAddress));

        // Assert
        uint256 balance = pooledDepositsVault.balances(arbitraryDepositor);
        assertEq(balance, depositAmount, "Balance should match the deposit amount");
        assertEq(address(pooledDepositsVault.ynETH()), ynethAddress, "ynETH owner should be set correctly");

        // Act
        vm.expectRevert();
        pooledDepositsVault.deposit{value: depositAmount}();

        // Act
        vm.prank(0xE1fAc59031520FD1eb901da990Da12Af295e6731);
        pooledDepositsVault.setYnETH(IynETH(address(0)));

        // Arrange
        address additionalDepositor = address(0x789);
        uint256 additionalDepositAmount = 3 ether;

        // Act
        vm.deal(additionalDepositor, additionalDepositAmount);
        vm.prank(additionalDepositor);
        pooledDepositsVault.deposit{value: additionalDepositAmount}();

        // Assert
        uint256 additionalBalance = pooledDepositsVault.balances(additionalDepositor);
        assertEq(additionalBalance, additionalDepositAmount, "Balance should match the additional deposit amount");
    }

    function testDepositAndSetYNETH() public {
        // Arrange
        address arbitraryDepositor = address(0x456);
        uint256 depositAmount = 2 ether;
        MockYnETH yneth = new MockYnETH();
        address ynethAddress = address(yneth);
        // Act
        vm.deal(arbitraryDepositor, depositAmount);
        vm.prank(arbitraryDepositor);
        pooledDepositsVault.deposit{value: depositAmount}();

        // https://etherscan.io/address/0xe1fac59031520fd1eb901da990da12af295e6731#readProxyContract%23F9
        vm.prank(0xE1fAc59031520FD1eb901da990Da12Af295e6731);
        pooledDepositsVault.setYnETH(IynETH(ynethAddress));

        // Assert
        uint256 balance = pooledDepositsVault.balances(arbitraryDepositor);
        assertEq(balance, depositAmount, "Balance should match the deposit amount");
        assertEq(address(pooledDepositsVault.ynETH()), ynethAddress, "ynETH owner should be set correctly");

        address[] memory depositors = new address[](1);
        depositors[0] = arbitraryDepositor;
        pooledDepositsVault.finalizeDeposits(depositors);

        // Assert depositor's balance using yneth
        uint256 ynethBalance = yneth.balanceOf(arbitraryDepositor);
        assertEq(ynethBalance, balance, "ynETH balance should match the depositor's balance after conversion");
    }
}