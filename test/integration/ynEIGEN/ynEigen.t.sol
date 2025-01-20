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

contract ynEigenTest is ynEigenIntegrationBaseTest {

    TestAssetUtils testAssetUtils;
    constructor() {
        testAssetUtils = new TestAssetUtils();
    }

    struct DepositTestVars {
        uint256 initialSupply;
        uint256 initialAssetBalance;
        uint256 internalAssetBalanceBefore;
        uint256 totalAssetsBefore;
        uint256 balance;
        uint256 finalAssetBalance;
        uint256 finalSupply;
        uint256 internalAssetBalanceAfter;
        uint256 userYnEigenBalanceAfter;
        uint256 ethEquivalent;
        uint256 totalAssetsAfter;

        uint256 userYnEigenBalanceBefore;
    }

    function depositAssetAndVerify(IERC20 asset, uint256 amount) public {

        address prankedUser = address(0x1234543210);
        DepositTestVars memory vars;
        vars.initialSupply = ynEigenToken.totalSupply();
        vars.initialAssetBalance = asset.balanceOf(address(ynEigenToken));
        vars.internalAssetBalanceBefore = ynEigenToken.assetBalance(asset);
        vars.totalAssetsBefore = ynEigenToken.totalAssets();

        // 1. Obtain asset and Deposit assets to ynEigen by User
        vars.balance = testAssetUtils.get_Asset(address(asset), prankedUser, amount);

        vars.userYnEigenBalanceBefore = ynEigenToken.balanceOf(prankedUser);

        vm.prank(prankedUser);
        asset.approve(address(ynEigenToken), vars.balance);
        vm.prank(prankedUser);
        ynEigenToken.deposit(asset, vars.balance, prankedUser);

        vars.finalAssetBalance = asset.balanceOf(address(ynEigenToken));
        vars.finalSupply = ynEigenToken.totalSupply();
        vars.internalAssetBalanceAfter = ynEigenToken.assetBalance(asset);

        vars.userYnEigenBalanceAfter = ynEigenToken.balanceOf(prankedUser);


        assertEq(
            vars.finalSupply,
            vars.initialSupply + (vars.userYnEigenBalanceAfter - vars.userYnEigenBalanceBefore),
        "Total supply did not increase correctly");

        vars.ethEquivalent = rateProvider.rate(address(asset)) * amount / 1e18;
        vars.totalAssetsAfter = ynEigenToken.totalAssets();
        assertTrue(
            compareWithThreshold(vars.totalAssetsAfter, vars.totalAssetsBefore + vars.ethEquivalent, 2),
            string.concat(
                "Total assets did not increase by the correct ETH equivalent amount. Expected: ",
                vm.toString(vars.totalAssetsBefore + vars.ethEquivalent),
                ", Got: ",
                vm.toString(vars.totalAssetsAfter)
            )
        );
    }

    function testDepositwstETHSuccessWithOneDepositFuzz(uint256 amount) public {
        vm.assume(
            amount < 10000 ether && amount >= 2 wei
        );        

        IERC20 wstETH = IERC20(chainAddresses.lsd.WSTETH_ADDRESS);
        depositAssetAndVerify(wstETH, amount);
    }

    function testDepositsfrxETHSuccessWithOneDepositFuzz(uint256 amount) public {
        vm.assume(
            amount < 10000 ether && amount >= 2 wei
        );        

        IERC20 sfrxETH = IERC20(chainAddresses.lsd.SFRXETH_ADDRESS);
        depositAssetAndVerify(sfrxETH, amount);
    }

    function testDepositrETHSuccessWithOneDepositFuzz(uint256 amount) public {
        vm.assume(
            amount < 10000 ether && amount >= 2 wei
        );        

        IERC20 rETH = IERC20(chainAddresses.lsd.RETH_ADDRESS);
        depositAssetAndVerify(rETH, amount);
    }

    function testDepositmETHSuccessWithOneDepositFuzz(
        uint256 amount
     ) public {
        
        // NOTE: mETH doesn't usually work with 10k amounts at a time to stake ETH and obtain it in 1 tx
        vm.assume(
            amount < 1000 ether && amount >= 2 wei
        );        

        IERC20 mETH = IERC20(chainAddresses.lsd.METH_ADDRESS);
        depositAssetAndVerify(mETH, amount);
    }

    function testMultipleDepositsFuzz(
        uint8 asset0Index,
        uint8 asset1Index,
        uint256 asset0Amount,
        uint256 asset1Amount
        ) public {

        vm.assume(asset0Index < 4 && asset1Index < 4);
        vm.assume(
            asset0Amount < 10000 ether && asset0Amount >= 2 wei &&
            asset1Amount < 10000 ether && asset1Amount >= 2 wei
        );

        IERC20[] memory assets = new IERC20[](4);
        assets[0] = IERC20(chainAddresses.lsd.WSTETH_ADDRESS);
        assets[1] = IERC20(chainAddresses.lsd.SFRXETH_ADDRESS);
        assets[2] = IERC20(chainAddresses.lsd.RETH_ADDRESS);
        assets[3] = IERC20(chainAddresses.lsd.WOETH_ADDRESS);

        depositAssetAndVerify(assets[asset0Index], asset0Amount);
        depositAssetAndVerify(assets[asset1Index], asset1Amount);

    }
    
    function testDepositwstETHSuccessWithMultipleDeposits() public {
        IERC20 wstETH = IERC20(chainAddresses.lsd.WSTETH_ADDRESS);
        uint256 amount = 32 ether;

        address prankedUser = address(0x123);
        uint256 initialSupply = ynEigenToken.totalSupply();

        // 1. Obtain wstETH and Deposit assets to ynEigen by User
        uint256 balance = testAssetUtils.get_wstETH(prankedUser, amount);
        assertEq(compareRebasingTokenBalances(balance, amount), true, "Amount not received");

        vm.prank(prankedUser);
        wstETH.approve(address(ynEigenToken), 32 ether);
        uint256 depositAmountOne = 5 ether;
        uint256 depositAmountTwo = 3 ether;
        uint256 depositAmountThree = 7 ether;

        vm.prank(prankedUser);
        ynEigenToken.deposit(wstETH, depositAmountOne, prankedUser);
        vm.prank(prankedUser);
        ynEigenToken.deposit(wstETH, depositAmountTwo, prankedUser);
        vm.prank(prankedUser);
        ynEigenToken.deposit(wstETH, depositAmountThree, prankedUser);

        assertEq(ynEigenToken.balanceOf(prankedUser), ynEigenToken.totalSupply() - initialSupply, "ynEigen balance does not match total supply");
    }
    
    function testDepositUnsupportedAsset() public {
        IERC20 asset = IERC20(address(1));
        uint256 amount = 1 ether;
        address receiver = address(this);

        vm.expectRevert(abi.encodeWithSelector(ynEigen.UnsupportedAsset.selector, address(asset)));
        ynEigenToken.deposit(asset, amount, receiver);
    }
    
    function testDepositWithZeroAmount() public {
        IERC20 asset = IERC20(chainAddresses.lsd.WSTETH_ADDRESS);
        uint256 amount = 0; // Zero amount for deposit
        address receiver = address(this);

        vm.expectRevert(ynEigen.ZeroAmount.selector);
        ynEigenToken.deposit(asset, amount, receiver);
    }

    function testConvertToShares() public {
        IERC20 asset = IERC20(address(this));
        uint256 amount = 1000;
        vm.expectRevert(abi.encodeWithSelector(ynEigen.UnsupportedAsset.selector, address(asset)));
        ynEigenToken.convertToShares(asset, amount);
    }

    function testConvertToSharesWithNoAssets() public {
        vm.prank(actors.ops.STAKING_NODE_CREATOR);
        tokenStakingNodesManager.createTokenStakingNode();
        uint256 totalAssets = ynEigenToken.totalAssets();
        assertEq(totalAssets, 0, "Total assets should be zero initially");
    }

    function testGetTotalAssetsConsistency() public {
        uint256 totalAssets = ynEigenToken.totalAssets();
        assertEq(totalAssets, 0, "Total assets should match bootstrap amount in ETH");
    }
    
    function testDepositUnsupportedAssetReverts() public {
        IERC20 asset = IERC20(address(1));
        vm.expectRevert(abi.encodeWithSelector(ynEigen.UnsupportedAsset.selector, asset));
        ynEigenToken.convertToShares(asset, 1000);
    }

    function testCalculateSharesForAsset() public {
        IERC20 asset = IERC20(chainAddresses.lsd.RETH_ADDRESS);
        uint256 amount = 1000;
        uint256 shares = ynEigenToken.convertToShares(asset, amount);
        uint256 assetRate = rateProvider.rate(address(asset));

        assertEq(shares, (uint256(assetRate) * amount) / 1e18, "Total shares calculation mismatch");
    }
    function testTotalAssetsAfterDeposit() public {
        IERC20 asset = IERC20(chainAddresses.lsd.WSTETH_ADDRESS);
        uint256 amount = 1 ether;

        IPausable pausableStrategyManager = IPausable(address(eigenLayer.strategyManager));
        vm.prank(actors.ops.STAKING_NODE_CREATOR);
        ITokenStakingNode tokenStakingNode = tokenStakingNodesManager.createTokenStakingNode();

        address unpauser = pausableStrategyManager.pauserRegistry().unpauser();

        vm.startPrank(unpauser);
        pausableStrategyManager.unpause(0);
        vm.stopPrank();

        uint256 totalAssetsBeforeDeposit = ynEigenToken.totalAssets();
        
        // 1. Obtain wstETH and Deposit assets to ynEigen by User
        uint256 balance = testAssetUtils.get_wstETH(address(this), amount);
        assertEq(balance == amount, true, "Amount not received");
        asset.approve(address(ynEigenToken), balance);
        ynEigenToken.deposit(asset, balance, address(this));
        {
            IERC20[] memory assets = new IERC20[](1);
            uint256[] memory amounts = new uint256[](1);
            assets[0] = asset;
            amounts[0] = amount;

            uint256 nodeId = tokenStakingNode.nodeId();
            vm.prank(actors.ops.STRATEGY_CONTROLLER);
            eigenStrategyManager.stakeAssetsToNode(nodeId, assets, amounts);
        }
        uint256 totalAssetsAfterDeposit = ynEigenToken.totalAssets();

        IStrategy strategy = eigenStrategyManager.strategies(IERC20(chainAddresses.lsd.WSTETH_ADDRESS));
        uint256 balanceInStrategyForNode  = strategy.userUnderlyingView((address(tokenStakingNode)));
        
        // expectedBalance is the same as in the strategy because 1 stETH = 1 ETH. 
        uint256 expectedBalance = balanceInStrategyForNode;

        // Assert that totalAssets reflects the deposit
        assertEq(
            compareWithThreshold(totalAssetsAfterDeposit - totalAssetsBeforeDeposit, expectedBalance, 2),
            true, 
            "Total assets do not reflect the deposit"
        );
    }

    function testPreviewDepositwstETH(uint256 amount) public {
        vm.assume(
            amount < 10000 ether && amount >= 2 wei
        );

        IERC20 asset = IERC20(chainAddresses.lsd.WSTETH_ADDRESS);

        uint256 wstethPrice = rateProvider.rate(chainAddresses.lsd.WSTETH_ADDRESS);

        uint256 expectedDepositPreview = amount * wstethPrice / 1e18;
        uint256 previewDeposit = ynEigenToken.previewDeposit(asset, amount);
        assertEq(previewDeposit, expectedDepositPreview, "Preview deposit does not match expected value");
    }

    function testPreviewDepositwoETH(uint256 amount) public {
        vm.assume(
            amount < 10000 ether && amount >= 2 wei
        );

        IERC20 asset = IERC20(chainAddresses.lsd.WOETH_ADDRESS);


        uint256 woethPrice = rateProvider.rate(chainAddresses.lsd.WOETH_ADDRESS);

        uint256 expectedDepositPreview = amount * woethPrice / 1e18;
        uint256 previewDeposit = ynEigenToken.previewDeposit(asset, amount);
        assertEq(previewDeposit, expectedDepositPreview, "Preview deposit does not match expected value");
    }

    function testPreviewDepositsfrxETH(uint256 amount) public {
        vm.assume(
            amount < 10000 ether && amount >= 2 wei
        );

        IERC20 asset = IERC20(chainAddresses.lsd.SFRXETH_ADDRESS);

        uint256 sfrxETHPrice = rateProvider.rate(chainAddresses.lsd.SFRXETH_ADDRESS);

        uint256 expectedDepositPreview = amount * sfrxETHPrice / 1e18;
        uint256 previewDeposit = ynEigenToken.previewDeposit(asset, amount);
        assertEq(previewDeposit, expectedDepositPreview, "Preview deposit does not match expected value");
    }

    function testConvertToETH() public {
        IERC20 asset = IERC20(chainAddresses.lsd.WSTETH_ADDRESS);
        uint256 amount = 1 ether;

        uint256 wstethPrice = rateProvider.rate(chainAddresses.lsd.WSTETH_ADDRESS);

        uint256 expectedETHAmount = amount * wstethPrice / 1e18;

        uint256 ethAmount = assetRegistry.convertToUnitOfAccount(asset, amount);
        assertEq(ethAmount, expectedETHAmount, "convertToEth does not match expected value");
    }

    function testPreviewRedeemWSTETH(uint256 amount) public {
        vm.assume(
            amount < 10000 ether && amount >= 10 wei
        );

        IERC20 asset = IERC20(chainAddresses.lsd.WSTETH_ADDRESS);

        uint256 wstethPrice = rateProvider.rate(chainAddresses.lsd.WSTETH_ADDRESS);

        uint256 expectedRedeemPreview = amount * 1e18 / wstethPrice;
        uint256 previewRedeem = ynEigenToken.previewRedeem(asset, amount);
        assertEq(previewRedeem, expectedRedeemPreview, "testPreviewRedeemWSTETH: E0");
    }

    function testPreviewRedeemWOETH(uint256 amount) public {
        vm.assume(
            amount < 10000 ether && amount >= 10 wei
        );

        IERC20 asset = IERC20(chainAddresses.lsd.WOETH_ADDRESS);

        uint256 woethPrice = rateProvider.rate(chainAddresses.lsd.WOETH_ADDRESS);

        uint256 expectedRedeemPreview = amount * 1e18 / woethPrice;
        uint256 previewRedeem = ynEigenToken.previewRedeem(asset, amount);
        assertEq(previewRedeem, expectedRedeemPreview, "testPreviewRedeemWOETH: E0");
    }

    function testPreviewRedeemSFRXETH(uint256 amount) public {
        vm.assume(
            amount < 10000 ether && amount >= 10 wei
        );

        IERC20 asset = IERC20(chainAddresses.lsd.SFRXETH_ADDRESS);

        uint256 sfrxETHPrice = rateProvider.rate(chainAddresses.lsd.SFRXETH_ADDRESS);

        uint256 expectedRedeemPreview = amount * 1e18 / sfrxETHPrice;
        uint256 previewRedeem = ynEigenToken.previewRedeem(asset, amount);
        assertEq(previewRedeem, expectedRedeemPreview, "testPreviewRedeemSFRXETH: E0");
    }

    function testPreviewRedeemRETH(uint256 amount) public {
        vm.assume(
            amount < 10000 ether && amount >= 10 wei
        );

        IERC20 asset = IERC20(chainAddresses.lsd.RETH_ADDRESS);

        uint256 rethPrice = rateProvider.rate(chainAddresses.lsd.RETH_ADDRESS);

        uint256 expectedRedeemPreview = amount * 1e18 / rethPrice;
        uint256 previewRedeem = ynEigenToken.previewRedeem(asset, amount);
        assertEq(previewRedeem, expectedRedeemPreview, "testPreviewRedeemRETH: E0");
    }

    function testPreviewRedeemNoAssets(uint256 amount) public {
        vm.assume(
            amount < 10000 ether && amount >= 10 wei
        );

        assertEq(amount, ynEigenToken.previewRedeem(amount), "testPreviewRedeemNoAssets: E0");
    }

    function testPreviewRedeemUnknownAsset() public {
        // Use a random address as an unknown asset
        address unknownAsset = address(0x1234567890123456789012345678901234567890);
        uint256 amount = 1 ether;

        // Expect the function to revert with UnsupportedAsset error
        vm.expectRevert(abi.encodeWithSelector(ynEigen.UnsupportedAsset.selector, unknownAsset));
        ynEigenToken.previewRedeem(IERC20(unknownAsset), amount);
    }
}

contract ynTransferPauseTest is ynEigenIntegrationBaseTest {

    TestAssetUtils testAssetUtils;
    constructor() {
        testAssetUtils = new TestAssetUtils();
    }

    function testTransferFailsForNonWhitelistedAddresses() public {
        // Arrange
        uint256 transferAmount = 1 ether;
        address nonWhitelistedAddress = address(4); // An arbitrary address not in the whitelist
        address recipient = address(5); // An arbitrary recipient address

        // Act & Assert
        // Ensure transfer from a non-whitelisted address reverts
        vm.expectRevert(ynBase.TransfersPaused.selector);
        vm.prank(nonWhitelistedAddress);
        ynEigenToken.transfer(recipient, transferAmount);
    }

    function testTransferSucceedsForWhitelistedAddress() public {
        // Arrange
        uint256 depositAmount = 1 ether;
        address whitelistedAddress = actors.eoa.DEFAULT_SIGNER; // Using the pre-defined whitelisted address from setup
        address recipient = address(6); // An arbitrary recipient address

        // 1. Obtain wstETH and Deposit assets to ynEigen by User
        IERC20 wstETH = IERC20(chainAddresses.lsd.WSTETH_ADDRESS);
        uint256 balance = testAssetUtils.get_wstETH(address(this), depositAmount);
        wstETH.approve(address(ynEigenToken), balance);
        ynEigenToken.deposit(wstETH, balance, whitelistedAddress); 

        uint256 transferAmount = ynEigenToken.balanceOf(whitelistedAddress);

        // Act
        address[] memory whitelist = new address[](1);
        whitelist[0] = whitelistedAddress;
        vm.prank(actors.admin.UNPAUSE_ADMIN);
        ynEigenToken.addToPauseWhitelist(whitelist); // Whitelisting the address
        vm.prank(whitelistedAddress);
        ynEigenToken.transfer(recipient, transferAmount);

        // Assert
        uint256 recipientBalance = ynEigenToken.balanceOf(recipient);
        assertEq(recipientBalance, transferAmount, "Transfer did not succeed for whitelisted address");
    }

    function testAddToPauseWhitelist() public {
        // Arrange
        address[] memory addressesToWhitelist = new address[](2);
        addressesToWhitelist[0] = address(1);
        addressesToWhitelist[1] = address(2);

        // Act
        vm.prank(actors.admin.UNPAUSE_ADMIN);
        ynEigenToken.addToPauseWhitelist(addressesToWhitelist);

        // Assert
        assertTrue(ynEigenToken.pauseWhiteList(addressesToWhitelist[0]), "Address 1 should be whitelisted");
        assertTrue(ynEigenToken.pauseWhiteList(addressesToWhitelist[1]), "Address 2 should be whitelisted");
    }

    function testTransferSucceedsForNewlyWhitelistedAddress() public {
        // Arrange
        uint256 depositAmount = 1 ether;
        address newWhitelistedAddress = vm.addr(7); // Using a new address for whitelisting
        address recipient = address(8); // An arbitrary recipient address

        // 1. Obtain wstETH and Deposit assets to ynEigen by User
        IERC20 wstETH = IERC20(chainAddresses.lsd.WSTETH_ADDRESS);
        uint256 balance = testAssetUtils.get_wstETH(address(this), depositAmount);

        wstETH.approve(address(ynEigenToken), balance);
        ynEigenToken.deposit(wstETH, balance, newWhitelistedAddress);

        address[] memory whitelistAddresses = new address[](1);
        whitelistAddresses[0] = newWhitelistedAddress;
        vm.prank(actors.admin.UNPAUSE_ADMIN);
        ynEigenToken.addToPauseWhitelist(whitelistAddresses); // Whitelisting the new address

        uint256 transferAmount = ynEigenToken.balanceOf(newWhitelistedAddress);

        // Act
        vm.prank(newWhitelistedAddress);
        ynEigenToken.transfer(recipient, transferAmount);

        // Assert
        uint256 recipientBalance = ynEigenToken.balanceOf(recipient);
        assertEq(recipientBalance, transferAmount, "Transfer did not succeed for newly whitelisted address");
    }
    function testTransferEnabledForAnyAddress() public {
        // Arrange
        uint256 depositAmount = 1 ether;
        address arbitraryAddress = vm.addr(9999); // Using an arbitrary address
        address recipient = address(10000); // An arbitrary recipient address

        // 1. Obtain wstETH and Deposit assets to ynEigen by User
        IERC20 wstETH = IERC20(chainAddresses.lsd.WSTETH_ADDRESS);
        uint256 balance = testAssetUtils.get_wstETH(address(this), depositAmount);
        wstETH.approve(address(ynEigenToken), balance);
        ynEigenToken.deposit(wstETH, balance, arbitraryAddress);

        uint256 transferAmount = ynEigenToken.balanceOf(arbitraryAddress);

        // Act
        vm.prank(actors.admin.UNPAUSE_ADMIN);
        ynEigenToken.unpauseTransfers(); // Unpausing transfers for all
        
        vm.prank(arbitraryAddress);
        ynEigenToken.transfer(recipient, transferAmount);

        // Assert
        uint256 recipientBalance = ynEigenToken.balanceOf(recipient);
        assertEq(recipientBalance, transferAmount, "Transfer did not succeed for any address after enabling transfers");
    }

    function testRemoveInitialWhitelistedAddress() public {
        // Arrange
        address[] memory whitelistAddresses = new address[](1);
        whitelistAddresses[0] = actors.eoa.DEFAULT_SIGNER; // EOA address to be removed from whitelist

        // Act
        vm.prank(actors.admin.UNPAUSE_ADMIN);
        ynEigenToken.removeFromPauseWhitelist(whitelistAddresses); // Removing the EOA address from whitelist

        // Assert
        bool isWhitelisted = ynEigenToken.pauseWhiteList(actors.eoa.DEFAULT_SIGNER);
        assertFalse(isWhitelisted, "EOA address was not removed from whitelist");
    }

    function testRemoveMultipleNewWhitelistAddresses() public {
        // Arrange
        address[] memory newWhitelistAddresses = new address[](2);
        newWhitelistAddresses[0] = address(20000); // First new whitelist address
        newWhitelistAddresses[1] = address(20001); // Second new whitelist address

        // Adding addresses to whitelist first
        vm.prank(actors.admin.UNPAUSE_ADMIN);
        ynEigenToken.addToPauseWhitelist(newWhitelistAddresses);

        // Act
        vm.prank(actors.admin.UNPAUSE_ADMIN);
        ynEigenToken.removeFromPauseWhitelist(newWhitelistAddresses); // Removing the new whitelist addresses

        // Assert
        bool isFirstAddressWhitelisted = ynEigenToken.pauseWhiteList(newWhitelistAddresses[0]);
        bool isSecondAddressWhitelisted = ynEigenToken.pauseWhiteList(newWhitelistAddresses[1]);
        assertFalse(isFirstAddressWhitelisted, "First new whitelist address was not removed");
        assertFalse(isSecondAddressWhitelisted, "Second new whitelist address was not removed");
    }
}

contract ynEigen_retrieveAssetsTest is ynEigenIntegrationBaseTest {

    TestAssetUtils testAssetUtils;
    constructor() {
        testAssetUtils = new TestAssetUtils();
    }

    function testRetrieveAssetsNotEigenStrategyManager() public {
        IERC20 asset = IERC20(chainAddresses.lsd.RETH_ADDRESS);
        uint256 amount = 1000;

        vm.prank(actors.ops.STAKING_NODE_CREATOR);
        tokenStakingNodesManager.createTokenStakingNode();

        IERC20[] memory assets = new IERC20[](1);
        uint256[] memory amounts = new uint256[](1);
        assets[0] = asset;
        amounts[0] = amount;
        vm.expectRevert(abi.encodeWithSelector(ynEigen.NotStrategyManager.selector, address(this)));
        ynEigenToken.retrieveAssets(assets, amounts);
    }

    function testRetrieveAssetsUnsupportedAsset() public {
        // come back to this
    }

    function testRetrieveTransferExceedsBalance() public {
        IERC20 asset = IERC20(chainAddresses.lsd.RETH_ADDRESS);
        uint256 amount = 1000;

        vm.startPrank(address(eigenStrategyManager));
        IERC20[] memory assets = new IERC20[](1);
        uint256[] memory amounts = new uint256[](1);
        assets[0] = asset;
        amounts[0] = amount;
        vm.expectRevert(abi.encodeWithSelector(ynEigen.InsufficientAssetBalance.selector, asset, 0, amount));
        ynEigenToken.retrieveAssets(assets, amounts);
        vm.stopPrank();
    }

    function testRetrieveAssetsSuccess() public {
        IERC20 asset = IERC20(chainAddresses.lsd.WSTETH_ADDRESS);
        uint256 amount = 64 ether;

        vm.prank(actors.ops.STAKING_NODE_CREATOR);
        tokenStakingNodesManager.createTokenStakingNode();

        ITokenStakingNode tokenStakingNode = tokenStakingNodesManager.nodes(0);
        vm.deal(address(tokenStakingNode), 1000);

        // 1. Obtain stETH and Deposit assets to ynEigenToken by User
        uint256 balance = testAssetUtils.get_wstETH(address(this), amount);
        assertEq(compareRebasingTokenBalances(balance, amount), true, "Amount not received");
       
        asset.approve(address(ynEigenToken), balance);
        ynEigenToken.deposit(asset, balance, address(this));

        vm.startPrank(address(eigenStrategyManager));
        asset.approve(address(ynEigenToken), 32 ether);
        IERC20[] memory assets = new IERC20[](1);
        uint256[] memory amounts = new uint256[](1);
        assets[0] = asset;
        amounts[0] = amount;
        ynEigenToken.retrieveAssets(assets, amounts);
        vm.stopPrank();

        uint256 strategyManagerBalance = asset.balanceOf(address(eigenStrategyManager));
        assertEq(strategyManagerBalance, amount, "Strategy manager does not have the correct balance of the token");
    }
}

contract ynEigenDonationsTest is ynEigenIntegrationBaseTest {

    TestAssetUtils testAssetUtils;
    constructor() {
        testAssetUtils = new TestAssetUtils();
    }

    function testYnEigendonationToZeroShareAttackResistance() public {

        uint INITIAL_AMOUNT = 10 ether;

        address alice = makeAddr("Alice");
        address bob = makeAddr("Bob");

        IERC20 assetToken = IERC20(chainAddresses.lsd.WSTETH_ADDRESS);

        // 1. Obtain wstETH and Deposit assets to ynEigen by User
        testAssetUtils.get_wstETH(alice, INITIAL_AMOUNT);
        testAssetUtils.get_wstETH(bob, INITIAL_AMOUNT);

        vm.prank(alice);
        assetToken.approve(address(ynEigenToken), type(uint256).max);

        vm.startPrank(bob);
        assetToken.approve(address(ynEigenToken), type(uint256).max);

        // Front-running part
        uint256 bobDepositAmount = INITIAL_AMOUNT / 2;
        // Alice knows that Bob is about to deposit INITIAL_AMOUNT*0.5 wstETH to the Vault by observing the mempool
        vm.startPrank(alice);
        uint256 aliceDepositAmount = 1;
        uint256 aliceShares = ynEigenToken.deposit(assetToken, aliceDepositAmount, alice);
        // Since there are bootstrap funds, this has no effect
        assertEq(compareWithThreshold(aliceShares, 1, 1), true, "Alice's shares should be dust"); 
        // Try to inflate shares value
        assetToken.transfer(address(ynEigenToken), bobDepositAmount);
        vm.stopPrank();

        // Check that Bob did not get 0 share when he deposits
        vm.prank(bob);
        uint256 bobShares = ynEigenToken.deposit(assetToken, bobDepositAmount, bob);

        assertGt(bobShares, 1 wei, "Bob's shares should be greater than 1 wei");
    }   
}