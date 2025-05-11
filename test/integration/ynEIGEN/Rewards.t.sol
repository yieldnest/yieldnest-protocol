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
import {console} from "forge-std/console.sol";


contract ynEigenRewardsTest is ynEigenIntegrationBaseTest {


    TestAssetUtils testAssetUtils;
    constructor() {
        testAssetUtils = new TestAssetUtils();
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
            uint256 depositAmount = 100 ether;
            
            // Obtain wstETH for depositor
            testAssetUtils.get_wstETH(user, depositAmount);
            
            // Deposit wstETH into ynEigenToken
            vm.startPrank(user);
            wstETH.approve(address(ynEigenToken), depositAmount);
            ynEigenToken.deposit(wstETH, depositAmount, user);
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