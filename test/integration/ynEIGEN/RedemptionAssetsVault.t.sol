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

contract RedemptionAssetsVaultTest is ynEigenIntegrationBaseTest {


    TestAssetUtils testAssetUtils;
    constructor() {
        testAssetUtils = new TestAssetUtils();
    }

    function testDepositAndVerifyAssetBalances(uint256 depositAmount) public {
        vm.assume(depositAmount > 1 ether && depositAmount < 100 ether);

        

        // Get wstETH token from chainAddresses
        IERC20 wstETH = IERC20(chainAddresses.lsd.WSTETH_ADDRESS);
        address user = address(0xABCD);

        // Obtain wstETH for user
        testAssetUtils.get_wstETH(user, depositAmount);

        // Check initial balances
        uint256 initialVaultBalance = wstETH.balanceOf(address(redemptionAssetsVault));
        uint256 initialAvailableAssets = redemptionAssetsVault.availableRedemptionAssets();
        uint256 initialUserBalance = wstETH.balanceOf(user);

        // User deposits wstETH into redemption assets vault
        vm.startPrank(user);
        wstETH.approve(address(redemptionAssetsVault), depositAmount);
        redemptionAssetsVault.deposit(depositAmount, address(wstETH));
        vm.stopPrank();

        // Verify balances after deposit
        uint256 finalVaultBalance = wstETH.balanceOf(address(redemptionAssetsVault));
        uint256 finalAvailableAssets = redemptionAssetsVault.availableRedemptionAssets();
        uint256 finalUserBalance = wstETH.balanceOf(user);

        // Assert that the vault's balance increased by the deposit amount
        assertEq(finalVaultBalance, initialVaultBalance + depositAmount, "Vault balance should increase by deposit amount");
        
        // Assert that the available redemption assets increased by the deposit amount converted to ETH
        uint256 depositAmountInEth =  assetRegistry.convertToUnitOfAccount(wstETH, depositAmount);
        assertEq(finalAvailableAssets, initialAvailableAssets + depositAmountInEth, "Available redemption assets should increase by deposit amount in ETH");
        
        // Assert that the user's balance decreased by the deposit amount
        assertEq(finalUserBalance, initialUserBalance - depositAmount, "User balance should decrease by deposit amount");
    }

    function testDepositMultipleAssetsAndVerifyBalances() public {
        // Get LSDs from chainAddresses
        IERC20 wstETH = IERC20(chainAddresses.lsd.WSTETH_ADDRESS);
        IERC20 rETH = IERC20(chainAddresses.lsd.RETH_ADDRESS);
        IERC20 sfrxETH = IERC20(chainAddresses.lsd.SFRXETH_ADDRESS);
        
        address user = address(0xDEF1);
        
        // Define deposit amounts
        uint256 wstETHAmount = 10 ether;
        uint256 rETHAmount = 5 ether;
        uint256 sfrxETHAmount = 7 ether;
        
        // Obtain LSDs for user
        testAssetUtils.get_wstETH(user, wstETHAmount);
        testAssetUtils.get_rETH(user, rETHAmount);
        testAssetUtils.get_sfrxETH(user, sfrxETHAmount);

        uint256 initialAvailableAssets = redemptionAssetsVault.availableRedemptionAssets();
        {      
            // Record initial balances
            uint256 initialWstETHVaultBalance = wstETH.balanceOf(address(redemptionAssetsVault));
            uint256 initialRETHVaultBalance = rETH.balanceOf(address(redemptionAssetsVault));
            uint256 initialSfrxETHVaultBalance = sfrxETH.balanceOf(address(redemptionAssetsVault));

            
            // User deposits multiple assets
            vm.startPrank(user);
            
            wstETH.approve(address(redemptionAssetsVault), wstETHAmount);
            redemptionAssetsVault.deposit(wstETHAmount, address(wstETH));
            
            rETH.approve(address(redemptionAssetsVault), rETHAmount);
            redemptionAssetsVault.deposit(rETHAmount, address(rETH));
            
            sfrxETH.approve(address(redemptionAssetsVault), sfrxETHAmount);
            redemptionAssetsVault.deposit(sfrxETHAmount, address(sfrxETH));
            
            vm.stopPrank();
        

            // Verify final balances
            uint256 finalWstETHVaultBalance = wstETH.balanceOf(address(redemptionAssetsVault));
            uint256 finalRETHVaultBalance = rETH.balanceOf(address(redemptionAssetsVault));
            uint256 finalSfrxETHVaultBalance = sfrxETH.balanceOf(address(redemptionAssetsVault));

            
            // Assert that each asset's balance increased correctly
            assertEq(finalWstETHVaultBalance, initialWstETHVaultBalance + wstETHAmount, "wstETH vault balance should increase by deposit amount");
            assertEq(finalRETHVaultBalance, initialRETHVaultBalance + rETHAmount, "rETH vault balance should increase by deposit amount");
            assertEq(finalSfrxETHVaultBalance, initialSfrxETHVaultBalance + sfrxETHAmount, "sfrxETH vault balance should increase by deposit amount");
        }

        // Assert that the total available redemption assets increased by the sum of all deposits
        IAssetRegistry assetRegistry = redemptionAssetsVault.assetRegistry();
        uint256 totalDeposited = assetRegistry.convertToUnitOfAccount(wstETH, wstETHAmount) +
                                 assetRegistry.convertToUnitOfAccount(rETH, rETHAmount) +
                                 assetRegistry.convertToUnitOfAccount(sfrxETH, sfrxETHAmount);
        assertEq(redemptionAssetsVault.availableRedemptionAssets(), initialAvailableAssets + totalDeposited, "Available redemption assets should increase by total deposit amount");
    }

    function testRewardDonationsThroughRedemptionAssetsVault(
       uint256 depositAmount
    ) public {

        vm.assume(
            depositAmount < 100_000 ether && depositAmount >= 2 wei
        );

        // This test verifies that rewards can be donated through the RedemptionAssetsVault
        // and that the redemption rate increases as a result
                      
        // Get wstETH token from chainAddresses
        IERC20 wstETH = IERC20(chainAddresses.lsd.WSTETH_ADDRESS);
        {
            // Setup test addresses
            address user = address(0x123456);

            
            // Define deposit amount
            uint256 userDepositAmount = 100 ether;
            
            // Obtain wstETH for depositor
            testAssetUtils.get_wstETH(user, userDepositAmount);
            
            // Deposit wstETH into ynEigenToken
            vm.startPrank(user);
            wstETH.approve(address(ynEigenToken), userDepositAmount);
            ynEigenToken.deposit(wstETH, userDepositAmount, user);
            vm.stopPrank();
        }

        uint256 rewardsAmount = 100 ether;

        // Get initial rate
        uint256 initialRate = ynEigenToken.previewRedeem(1e18);
        // Read initial total assets in ynEigen
        uint256 initialTotalAssets = ynEigenToken.totalAssets();
        // Read initial total supply of ynEigenToken
        uint256 initialTotalSupply = ynEigenToken.totalSupply();
        {
            address depositor = address(0x123);
            
            testAssetUtils.get_wstETH(depositor, rewardsAmount);
            // Get initial available redemption assets
            uint256 initialAvailableAssets = redemptionAssetsVault.availableRedemptionAssets();


            vm.startPrank(depositor);
            // Approve wstETH for redemption assets vault deposit
            wstETH.approve(address(redemptionAssetsVault), rewardsAmount);
            redemptionAssetsVault.deposit(rewardsAmount, address(wstETH));
            vm.stopPrank();

                        
            // Verify redemption assets increased
            uint256 newAvailableAssets = redemptionAssetsVault.availableRedemptionAssets();
            assertGt(newAvailableAssets, initialAvailableAssets, "Redemption assets should increase after donation");
        }

        assertEq(
            wstETH.balanceOf(address(redemptionAssetsVault)), 
            rewardsAmount, 
            "Redemption vault should have the correct wstETH balance after deposit"
        );

        uint256 depositAmountInEth = assetRegistry.convertToUnitOfAccount(wstETH, rewardsAmount);

        
        // 4. Call withdrawSurplus to process the rewards
        vm.prank(actors.ops.REDEMPTION_ASSET_WITHDRAWER);
        withdrawalQueueManager.withdrawSurplusRedemptionAssets(depositAmountInEth);


        // Verify that the redemption assets vault has no more wstETH after withdrawal
        assertEq(
            wstETH.balanceOf(address(redemptionAssetsVault)),
            0,
            "Redemption vault should have 0 wstETH balance after withdrawal"
        );
        
        assertEq(
            redemptionAssetsVault.availableRedemptionAssets(),
            0,
            "Available redemption assets should be back to initial value after withdrawal"
        );

        assertEq(redemptionAssetsVault.balances(address(wstETH)), 0, "Redemption vault should have 0 wstETH balance after withdrawal");
        
        assertEq(
            ynEigenToken.totalAssets(),
            initialTotalAssets + depositAmountInEth,
            "Total assets should increase by the deposited amount after processing rewards"
        );

        // Verify that the total supply remains unchanged after processing rewards
        assertEq(
            ynEigenToken.totalSupply(),
            initialTotalSupply,
            "Total supply should remain unchanged after processing rewards"
        );

        assertGt(
            ynEigenToken.previewRedeem(1e18),
            initialRate,
            "Exchange rate should increase after processing rewards"
        );
    
    }
}