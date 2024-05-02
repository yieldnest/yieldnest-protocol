// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import { IntegrationBaseTest } from "test/integration/IntegrationBaseTest.sol";
import {TransparentUpgradeableProxy} from "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {PooledDepositsVault} from "src/PooledDepositsVault.sol";
import {IynETH} from "src/interfaces/IynETH.sol";
import {Test} from"forge-std/Test.sol";

contract MockynETH is IynETH {
    // Implement necessary mock functions
    function depositETH(address receiver) external payable override returns (uint256 shares) {}

    function balanceOf(address /* account */) external view override returns (uint256) {
        // Mock balanceOf function
        return 0;
    }
    function withdrawETH(uint256 ethAmount) external {}
    function pauseDeposits() external {}
    function unpauseDeposits() external {}
    function transferFrom(address from, address to, uint256 value) external returns (bool) {}
    function transfer(address to, uint256 value) external returns (bool) {}
    function totalSupply() external view returns (uint256) {}
    function receiveRewards() external payable {}
    function processWithdrawnETH() external payable {}
    function approve(address spender, uint256 value) external returns (bool) {}
    function allowance(address owner, address spender) external view returns (uint256) {}
}

contract PooledDepositsScenarioTest is IntegrationBaseTest {
    PooledDepositsVault public vault;
    MockynETH public mockynETH;

    function setUp() public override {

        super.setUp();
        // Deploy the mock ynETH contract
        mockynETH = new MockynETH();

        // Deploy the PooledDepositsVault contract and initialize it
        vault = new PooledDepositsVault();
        TransparentUpgradeableProxy vaultProxy = new TransparentUpgradeableProxy(address(vault), address(this), ""); // Assuming the test contract is the owner
        vault = PooledDepositsVault(payable(address(vaultProxy)));
        vault.initialize(address(this));
    }

    function testAttackBySendingManySmallDeposits() public {
        // Simulate an attacker sending a large number of small deposits
        uint256 numberOfDeposits = 1000; // Example number of deposits
        uint256 depositAmount = 1 wei;

        for (uint256 i = 0; i < numberOfDeposits; i++) {
            // Each call to `deposit` is a separate transaction
            (bool success, ) = address(vault).call{value: depositAmount}("");
            assertTrue(success, "Deposit failed");
        }

        // Assess the impact
        // Example: Check the contract's balance to ensure it matches expectations
        assertEq(address(vault).balance, numberOfDeposits * depositAmount, "Unexpected balance");
    }

    function testSelfDestructAttackOnPooledDepositsVault() public {

        // Amount of ether to be sent via self-destruct
        uint256 amountToSendViaSelfDestruct = 1 ether;

        // Ensure the test contract has enough ether to perform the attack
        vm.deal(address(this), amountToSendViaSelfDestruct);

        // Address to send ether to - the vault in this case
        address payable target = payable(address(vault));

        uint256 depositAmount1 = 50 ether;
        uint256 depositAmount2 = 100 ether;

        // Arrange
        PooledDepositsVault pooledDepositsVault = vault;
        address depositor = address(this);
        uint256 expectedBalanceAfterFirstDeposit = depositAmount1;
        uint256 expectedBalanceAfterSecondDeposit = depositAmount1 + depositAmount2;

        // Act and Assert
        vm.deal(depositor, expectedBalanceAfterSecondDeposit + 100 ether);
        vm.prank(depositor);
        pooledDepositsVault.deposit{value: depositAmount1}();
        assertEq(pooledDepositsVault.balances(depositor), expectedBalanceAfterFirstDeposit, "Balance after first deposit incorrect");

        // Initial balance of the vault before the attack
        uint256 initialVaultBalance = address(vault).balance;

        // Create and send ether via self-destruct
        // The SelfDestructSender contract is created with the specified amount and immediately self-destructs,
        // sending its balance to the target address (vault).
        address(new SelfDestructSender{value: amountToSendViaSelfDestruct}(target));

        // Check the balance of the vault after the attack
        uint256 finalVaultBalance = address(vault).balance;

        // Assert that the vault's balance has increased by the amount sent via self-destruct
        assertEq(finalVaultBalance, initialVaultBalance + amountToSendViaSelfDestruct, "Vault balance did not increase as expected after self-destruct attack");

        vm.prank(depositor);
        pooledDepositsVault.deposit{value: depositAmount2}();
        assertEq(pooledDepositsVault.balances(depositor), expectedBalanceAfterSecondDeposit, "Balance after second deposit incorrect");


        address[] memory depositors = new address[](1);
        depositors[0] = depositor;

        // Set ynETH before finalizing deposits
        vm.prank(pooledDepositsVault.owner());
        pooledDepositsVault.setYnETH(IynETH(address(yneth)));

        vm.warp(block.timestamp + 3 days); // Move time forward to allow finalizing deposits
        pooledDepositsVault.finalizeDeposits(depositors);
        // Assert
        // Assuming ynETH's depositETH function simply mints 1:1 ynETH for ETH deposited
        uint256 expectedYnETHAmount = expectedBalanceAfterSecondDeposit;
        assertEq(yneth.balanceOf(address(this)), expectedYnETHAmount, "ynETH should be minted and sent to the depositor");

        assertEq(address(vault).balance, amountToSendViaSelfDestruct, "Vault balance afte finalizeDeposits does not match self destruct amount");
    }

}


    // Add this contract definition outside of your existing contract definitions
contract SelfDestructSender {
        constructor(address payable _target) payable {
            selfdestruct(_target);
    }
}