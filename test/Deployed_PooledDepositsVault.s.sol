// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {PooledDepositsVault} from "src/PooledDepositsVault.sol";
import {IynETH} from "src/interfaces/IynETH.sol";
import "test/integration/IntegrationBaseTest.sol";
import "src/ynBase.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy} from "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "script/Utils.sol";
import "script/ContractAddresses.sol";


contract MockUpgradedVault is PooledDepositsVault {
    function foo() public pure returns (uint256) {
        return 123;
    }
}


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

abstract contract Deployed_PooledDepositsVaultTest is Test, Utils {

    PooledDepositsVault public pooledDepositsVault;

    ContractAddresses.YieldNestAddresses yn;

    IynETH yneth;

    function setUp() public virtual {
        ContractAddresses contractAddresses = new ContractAddresses();
        yn = contractAddresses.getChainAddresses(block.chainid).yn;
        yneth = IynETH(yn.YNETH_ADDRESS);
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

        uint256 previewAmount = yneth.previewDeposit(depositAmount);

        address[] memory depositors = new address[](1);
        depositors[0] = arbitraryDepositor;
        pooledDepositsVault.finalizeDeposits(depositors);

        // Assert depositor's balance using yneth
        uint256 ynethBalance = yneth.balanceOf(arbitraryDepositor);
        assertEq(ynethBalance, previewAmount, "ynETH balance should match the depositor's balance after conversion");
    }

    function testUpgradeVault() public {
        // Arrange
        MockUpgradedVault newVaultImplementation = new MockUpgradedVault();
        address proxyAdminAddress = getTransparentUpgradeableProxyAdminAddress(address(pooledDepositsVault));
        ProxyAdmin proxyAdmin = ProxyAdmin(proxyAdminAddress);

        // Act
        vm.prank(0xE1fAc59031520FD1eb901da990Da12Af295e6731); // Assuming the test contract has the rights to upgrade
        proxyAdmin.upgradeAndCall(ITransparentUpgradeableProxy(address(pooledDepositsVault)), address(newVaultImplementation), "");

        // Assert
        address newImplementation = getTransparentUpgradeableProxyImplementationAddress(address(pooledDepositsVault));
        assertEq(newImplementation, address(newVaultImplementation), "Vault should be upgraded to new implementation");

        // Act
        uint256 result = MockUpgradedVault(payable(address(pooledDepositsVault))).foo();
        
        // Assert
        assertEq(result, 123, "foo should return 123");
    }


    function testDepositAndSetYNETHForManyDepositors() public {
        // Arrange
        uint256 depositAmount = 2 ether;
        address ynethAddress = address(yneth);
        uint NUM_DEPOSITORS = 20;
        address[] memory depositors = new address[](NUM_DEPOSITORS);
        
        // Act
        for (uint i = 0; i < NUM_DEPOSITORS; i++) {
            address arbitraryDepositor = address(uint160(uint(keccak256(abi.encodePacked(i)))));
            depositors[i] = arbitraryDepositor;
            vm.deal(arbitraryDepositor, depositAmount);
            vm.prank(arbitraryDepositor);
            pooledDepositsVault.deposit{value: depositAmount}();
        }

        // Set YNETH for the vault
        vm.prank(0xE1fAc59031520FD1eb901da990Da12Af295e6731);
        pooledDepositsVault.setYnETH(IynETH(ynethAddress));
        assertEq(address(pooledDepositsVault.ynETH()), ynethAddress, "ynETH owner should be set correctly");

        // Assert
        for (uint i = 0; i < NUM_DEPOSITORS; i++) {
            uint256 balance = pooledDepositsVault.balances(depositors[i]);
            assertEq(balance, depositAmount, "Balance should match the deposit amount");
        }

        uint256 previewAmount = yneth.previewDeposit(depositAmount);
        pooledDepositsVault.finalizeDeposits(depositors);

        for (uint i = 0; i < NUM_DEPOSITORS; i++) {   // Assert depositor's balance using yneth
            uint256 ynethBalance = yneth.balanceOf(depositors[i]);
            assertEq(ynethBalance, previewAmount, "ynETH balance should match the depositor's balance after conversion");
        }
    }
}

contract Deployed_PooledDepositsVaultTest_0 is Deployed_PooledDepositsVaultTest {
    function setUp() public override {
        super.setUp();
        pooledDepositsVault = PooledDepositsVault(payable(0xA01F3Ac94EA005626Ce1cFa7C796136E041E02d6));
    }
}

contract Deployed_PooledDepositsVaultTest_1 is Deployed_PooledDepositsVaultTest {
    function setUp() public override {
        super.setUp();
        pooledDepositsVault = PooledDepositsVault(payable(0x2D54dbD928c8602D91aD393289dbF6E37E335C86));
    }
}

contract Deployed_PooledDepositsVaultTest_2 is Deployed_PooledDepositsVaultTest {
    function setUp() public override {
        super.setUp();
        pooledDepositsVault = PooledDepositsVault(payable(0x96565886E75950754870913c346C4fe6471Ac32c));
    }
}

contract Deployed_PooledDepositsVaultTest_3 is Deployed_PooledDepositsVaultTest {
    function setUp() public override {
        super.setUp();
        pooledDepositsVault = PooledDepositsVault(payable(0xbCFDb3E05B7B1A4154F680dcde94C90eF6360a2E));
    }
}

contract Deployed_PooledDepositsVaultTest_4 is Deployed_PooledDepositsVaultTest {
    function setUp() public override {
        super.setUp();
        pooledDepositsVault = PooledDepositsVault(payable(0x1f14DF42E7c6c6701B6D08AB13f63a42411fe790));
    }
}

contract Deployed_PooledDepositsVaultTest_5 is Deployed_PooledDepositsVaultTest {
    function setUp() public override {
        super.setUp();
        pooledDepositsVault = PooledDepositsVault(payable(0x75d85f4e8713EF9E7C0Fb5b8Eb739F6a776cA074));
    }
}

contract Deployed_PooledDepositsVaultTest_6 is Deployed_PooledDepositsVaultTest {
    function setUp() public override {
        super.setUp();
        pooledDepositsVault = PooledDepositsVault(payable(0x6CaaD94F29C7Bf1a569219b1ec400A2506fd4780));
    }

    function testHandleExistingDepositors() public {
        address[] memory existingDepositors = new address[](2);
        existingDepositors[0] = 0x72bD536087025156bD72FC1C28D02C198C521233;
        existingDepositors[1] = 0x7B58d24ed811B1cbA23887855982F283fADe1493;

        uint256[] memory depositAmounts = new uint256[](existingDepositors.length);
        for (uint i = 0; i < existingDepositors.length; i++) {
            depositAmounts[i] = pooledDepositsVault.balances(existingDepositors[i]);
        }

        address ynethAddress = address(yn.YNETH_ADDRESS);

        vm.prank(0xE1fAc59031520FD1eb901da990Da12Af295e6731);
        pooledDepositsVault.setYnETH(IynETH(ynethAddress));

        // Finalize deposits for all existing depositors
        pooledDepositsVault.finalizeDeposits(existingDepositors);

        // Assert all balances are correct after finalizing deposits
        for (uint i = 0; i < existingDepositors.length; i++) {
            uint256 expectedBalance = yneth.previewDeposit(depositAmounts[i]);
            uint256 actualBalance = yneth.balanceOf(existingDepositors[i]);
            assertEq(actualBalance, expectedBalance, "Balance should match the expected balance after finalizing deposits");
        }
    }
}
