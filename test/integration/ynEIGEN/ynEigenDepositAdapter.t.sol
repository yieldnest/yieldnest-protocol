// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity 0.8.24;

import "./ynEigenIntegrationBaseTest.sol";
import {ProxyAdmin} from "lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {UpgradeableBeacon} from "lib/openzeppelin-contracts/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {ITransparentUpgradeableProxy} from "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IPausable} from "lib/eigenlayer-contracts/src/contracts/interfaces//IPausable.sol";
import {ITokenStakingNode} from "src/interfaces/ITokenStakingNode.sol";
import {ynBase} from "src/ynBase.sol";

contract ynEigenDepositAdapterTest is ynEigenIntegrationBaseTest {

    function testDepositstETHSuccessWithOneDeposit() public {
        uint256 depositAmount = 1 ether;
        address depositor = address(0x123);
        address receiver = address(0x456);

        // 1. Obtain wstETH and Deposit assets to ynEigen by User
        TestAssetUtils testAssetUtils = new TestAssetUtils();
        testAssetUtils.get_stETH(depositor, depositAmount * 10);

        // Arrange: Setup the initial balance of stETH for the depositor
        IERC20 stETH = IERC20(chainAddresses.lsd.STETH_ADDRESS);

        vm.prank(depositor);
        stETH.approve(address(ynEigenDepositAdapterInstance), depositAmount);
        // Act: Perform the deposit operation using the ynEigenDepositAdapter
        vm.prank(depositor);
        ynEigenDepositAdapterInstance.depositStETH(depositAmount, receiver);
        
        uint256 receiverBalance = ynEigenToken.balanceOf(receiver);
        assertTrue(
            compareWithThreshold(receiverBalance, depositAmount, 2),
            "Receiver's balance should match the deposited amount"
        );
    }

    function testDepositOETHSuccessWithOneDeposit() public {
        uint256 depositAmount = 1 ether;
        address depositor = address(0x789);
        address receiver = address(0xABC);

        // 1. Obtain woETH and Deposit assets to ynEigen by User
        TestAssetUtils testAssetUtils = new TestAssetUtils();
        testAssetUtils.get_OETH(depositor, depositAmount * 10);

        // Arrange: Setup the initial balance of oETH for the depositor
        IERC20 oETH = IERC20(chainAddresses.lsd.OETH_ADDRESS);

        vm.prank(depositor);
        oETH.approve(address(ynEigenDepositAdapterInstance), depositAmount);
        // Act: Perform the deposit operation using the ynEigenDepositAdapter
        vm.prank(depositor);
        ynEigenDepositAdapterInstance.depositOETH(depositAmount, receiver);
        
        uint256 receiverBalance = ynEigenToken.balanceOf(receiver);
        assertTrue(
            compareWithThreshold(receiverBalance, depositAmount, 2),
            "Receiver's balance should match the deposited amount"
        );
    }
}