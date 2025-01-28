// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import "./ynEigenIntegrationBaseTest.sol";
import {ProxyAdmin} from "lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {UpgradeableBeacon} from "lib/openzeppelin-contracts/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {ITransparentUpgradeableProxy} from "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IPausable} from "lib/eigenlayer-contracts/src/contracts/interfaces//IPausable.sol";
import {ITokenStakingNode} from "src/interfaces/ITokenStakingNode.sol";
import {ynBase} from "src/ynBase.sol";
import {IstETH} from "src/external/lido/IstETH.sol";

contract ynEigenDepositAdapterTest is ynEigenIntegrationBaseTest {


    TestAssetUtils testAssetUtils;
    constructor() {
        testAssetUtils = new TestAssetUtils();
    }

    function testDepositstETHSuccessWithOneDepositFuzz(
       uint256 depositAmount
    ) public {

        vm.assume(
            depositAmount < 10000 ether && depositAmount >= 2 wei
        );
        address depositor = address(0x123);
        address receiver = address(0x456);


        // Arrange: Setup the initial balance of stETH for the depositor
        IERC20 stETH = IERC20(chainAddresses.lsd.STETH_ADDRESS);

        uint256 initialSupply = ynEigenToken.totalSupply();
        uint256 initialReceiverBalance = ynEigenToken.balanceOf(receiver);

        // 1. Obtain wstETH and Deposit assets to ynEigen by User
        testAssetUtils.get_stETH(depositor, depositAmount * 10);

        // Preview deposit to get expected shares
        uint256 expectedShares = ynEigenDepositAdapterInstance.previewDeposit(stETH, depositAmount);

        vm.prank(depositor);
        stETH.approve(address(ynEigenDepositAdapterInstance), depositAmount);
        // Act: Perform the deposit operation using the ynEigenDepositAdapter
        vm.prank(depositor);
        uint256 shares = ynEigenDepositAdapterInstance.deposit(stETH, depositAmount, receiver);

        // Assert that the actual shares match the expected shares
        assertEq(shares, expectedShares, "Actual shares do not match expected shares");

        uint256 receiverBalance = ynEigenToken.balanceOf(receiver);
        uint256 treshold = depositAmount / 1e17 + 3;
        assertTrue(
            compareWithThreshold(receiverBalance, depositAmount, treshold),
            string.concat("Receiver's balance: ", vm.toString(receiverBalance), ", Expected balance: ", vm.toString(depositAmount))
        );

        uint256 finalSupply = ynEigenToken.totalSupply();
        uint256 finalReceiverBalance = ynEigenToken.balanceOf(receiver);

        assertEq(finalSupply, initialSupply + shares, "Total supply did not increase correctly");

        // Verify receiver balance increased
        assertEq(finalReceiverBalance, initialReceiverBalance + shares, "Receiver balance did not increase correctly");
    }

    function testDepositOETHSuccessWithOneDeposit(
       uint256 depositAmount
    ) public {

        vm.assume(
            depositAmount < 10000 ether && depositAmount >= 2 wei
        );
        address depositor = address(0x789);
        address receiver = address(0xABC);

        // Arrange: Setup the initial balance of oETH for the depositor
        IERC20 oETH = IERC20(chainAddresses.lsd.OETH_ADDRESS);

        uint256 initialSupply = ynEigenToken.totalSupply();
        uint256 initialReceiverBalance = ynEigenToken.balanceOf(receiver);

        // 1. Obtain woETH and Deposit assets to ynEigen by User
        testAssetUtils.get_OETH(depositor, depositAmount * 10);

        // Preview deposit to get expected shares
        uint256 expectedShares = ynEigenDepositAdapterInstance.previewDeposit(oETH, depositAmount);

        vm.prank(depositor);
        oETH.approve(address(ynEigenDepositAdapterInstance), depositAmount);
        // Act: Perform the deposit operation using the ynEigenDepositAdapter
        vm.prank(depositor);
        uint256 shares = ynEigenDepositAdapterInstance.deposit(oETH, depositAmount, receiver);

        // Assert that the actual shares match the expected shares
        assertEq(shares, expectedShares, "Actual shares do not match expected shares");

        uint256 receiverBalance = ynEigenToken.balanceOf(receiver);
        uint256 treshold = depositAmount / 1e17 + 3;
        assertTrue(
            compareWithThreshold(receiverBalance, depositAmount, treshold),
            string.concat("Receiver's balance: ", vm.toString(receiverBalance), ", Expected balance: ", vm.toString(depositAmount))
        );

        uint256 finalSupply = ynEigenToken.totalSupply();
        uint256 finalReceiverBalance = ynEigenToken.balanceOf(receiver);

        // // // Verify asset balance of ynEigenToken increased
        // // assertEq(finalAssetBalance, initialAssetBalance + balance, "Asset balance did not increase correctly");
        // Verify total supply increased
        assertEq(finalSupply, initialSupply + shares, "Total supply did not increase correctly");

        // Verify receiver balance increased
        assertEq(finalReceiverBalance, initialReceiverBalance + shares, "Receiver balance did not increase correctly");
    }

    function testDepositwstETHSuccessWithOneDepositFuzzWithAdapter(
        uint256 amount
    ) public {
        vm.assume(
            amount < 10000 ether && amount >= 2 wei
        );
        
        {
        // we need this to prevent revert: SAKE_LIMIT
            uint256 stakeLimit = IstETH(chainAddresses.lsd.STETH_ADDRESS).getCurrentStakeLimit();
            uint256 stETHToMint = amount * IwstETH(chainAddresses.lsd.WSTETH_ADDRESS).stEthPerToken() / 1e18 + 1 ether;
            vm.assume(stETHToMint <= stakeLimit);
        }

        IERC20 wstETH = IERC20(chainAddresses.lsd.WSTETH_ADDRESS);
        depositAssetAndVerify(wstETH, amount);
    }

    function testDepositsfrxETHSuccessWithOneDepositFuzzWithAdapter(
        uint256 amount
    ) public {
        vm.assume(
            amount < 10000 ether && amount >= 2 wei
        );

        IERC20 sfrxETH = IERC20(chainAddresses.lsd.SFRXETH_ADDRESS);
        depositAssetAndVerify(sfrxETH, amount);
    }

    function testDepositrETHSuccessWithOneDepositFuzzWithAdapter(
        uint256 amount
    ) public {
        vm.assume(
            amount < 10000 ether && amount >= 2 wei
        );

        IERC20 rETH = IERC20(chainAddresses.lsd.RETH_ADDRESS);
        depositAssetAndVerify(rETH, amount);
    }

    function testDepositmETHSuccessWithOneDepositFuzzWithAdapter(
        uint256 amount
     ) public {
        // NOTE: mETH doesn't usually work with 10k amounts at a time to stake ETH and obtain it in 1 tx
        vm.assume(
            amount < 1000 ether && amount >= 2 wei
        );

        IERC20 mETH = IERC20(chainAddresses.lsd.METH_ADDRESS);
        depositAssetAndVerify(mETH, amount);
    }

    function depositAssetAndVerify(IERC20 asset, uint256 amount) internal {
        address prankedUser = address(0x1234543210);
        address receiver = address(0x9876543210);

        uint256 initialSupply = ynEigenToken.totalSupply();
        uint256 initialAssetBalance = asset.balanceOf(address(ynEigenToken));
        uint256 initialReceiverBalance = ynEigenToken.balanceOf(receiver);

        // Obtain asset for prankedUser
        uint256 balance = testAssetUtils.get_Asset(address(asset), prankedUser, amount);

        uint256 expectedShares = ynEigenDepositAdapterInstance.previewDeposit(asset, balance);

        vm.startPrank(prankedUser);
        asset.approve(address(ynEigenDepositAdapterInstance), balance);
        uint256 shares = ynEigenDepositAdapterInstance.deposit(asset, balance, receiver);
        vm.stopPrank();

        // Verify that the actual shares received match the expected shares
        assertEq(shares, expectedShares, "Actual shares do not match expected shares");

        uint256 finalAssetBalance = asset.balanceOf(address(ynEigenToken));
        uint256 finalSupply = ynEigenToken.totalSupply();
        uint256 finalReceiverBalance = ynEigenToken.balanceOf(receiver);

        // Verify asset balance of ynEigenToken increased
        assertEq(finalAssetBalance, initialAssetBalance + balance, "Asset balance did not increase correctly");
        // Verify total supply increased
        assertEq(finalSupply, initialSupply + shares, "Total supply did not increase correctly");

        // Verify receiver balance increased
        assertEq(finalReceiverBalance, initialReceiverBalance + shares, "Receiver balance did not increase correctly");
    }

    function testDepositWithReferralWstETHFuzz(
        uint256 amount,
        address receiver,
        address referrer
    ) public {
        vm.assume(amount >= 2 wei && amount < 10000 ether);

        {
        // we need this to prevent revert: SAKE_LIMIT
            uint256 stakeLimit = IstETH(chainAddresses.lsd.STETH_ADDRESS).getCurrentStakeLimit();
            uint256 stETHToMint = amount * IwstETH(chainAddresses.lsd.WSTETH_ADDRESS).stEthPerToken() / 1e18 + 1 ether;
            vm.assume(stETHToMint <= stakeLimit);
        }

        vm.assume(receiver != address(0) && referrer != address(0) && receiver != referrer);

        address prankedUser = address(0x1234543210);
        IERC20 wstETH = IERC20(chainAddresses.lsd.WSTETH_ADDRESS);

        uint256 initialSupply = ynEigenToken.totalSupply();
        uint256 initialAssetBalance = wstETH.balanceOf(address(ynEigenToken));
        uint256 initialReceiverBalance = ynEigenToken.balanceOf(receiver);

        // Obtain asset for prankedUser
        uint256 balance = testAssetUtils.get_Asset(address(wstETH), prankedUser, amount);

        vm.startPrank(prankedUser);
        wstETH.approve(address(ynEigenDepositAdapterInstance), balance);

        uint256 shares = ynEigenDepositAdapterInstance.depositWithReferral(wstETH, balance, receiver, referrer);
        vm.stopPrank();

        uint256 finalAssetBalance = ynEigenToken.assetBalance(wstETH);
        uint256 finalSupply = ynEigenToken.totalSupply();
        uint256 finalReceiverBalance = ynEigenToken.balanceOf(receiver);

        // Verify wstETH balance of ynEigenToken increased
        assertEq(finalAssetBalance, initialAssetBalance + balance, "wstETH balance did not increase correctly");

        // Verify total supply increased
        assertEq(finalSupply, initialSupply + shares, "Total supply did not increase correctly");

        // Verify receiver balance increased
        assertEq(finalReceiverBalance, initialReceiverBalance + shares, "Receiver balance did not increase correctly");

        // Verify user balance increased
        assertEq(ynEigenToken.balanceOf(receiver), initialReceiverBalance + shares, "User balance did not increase correctly");
    }
}
