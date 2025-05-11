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

contract ynEigenRewardsTest is ynEigenIntegrationBaseTest {


    TestAssetUtils testAssetUtils;
    constructor() {
        testAssetUtils = new TestAssetUtils();
    }

    function testRewardDonationsThroughRedemptionAssetsVault(
       // uint256 depositAmount
    ) public {

        // vm.assume(
        //     depositAmount < 10000 ether && depositAmount >= 2 wei
        // );

        uint256 depositAmount = 100 ether;

        address depositor = address(0x123);
        address receiver = address(0x456);

        // Arrange: Setup the initial balance of wstETH
        IERC20 wstETH = IERC20(chainAddresses.lsd.WSTETH_ADDRESS);
        
        // Get initial rate
        uint256 initialRate = ynEigenToken.previewRedeem(1e18);
        
        // 1. Obtain wstETH for depositor
        testAssetUtils.get_wstETH(depositor, depositAmount);
        
        // 2. Deposit assets to ynEigen by User
        vm.startPrank(depositor);
        wstETH.approve(address(ynEigenToken), depositAmount);
        ynEigenToken.deposit(wstETH, depositAmount, receiver);
        vm.stopPrank();
        
        testAssetUtils.get_wstETH(address(this), depositAmount);
        // Get initial available redemption assets
        uint256 initialAvailableAssets = redemptionAssetsVault.availableRedemptionAssets();
        
        vm.startPrank(address(this));
        // Approve wstETH for redemption assets vault deposit
        wstETH.approve(address(redemptionAssetsVault), depositAmount);
        redemptionAssetsVault.deposit(depositAmount, address(wstETH));
        vm.stopPrank();
        
        // Verify redemption assets increased
        uint256 newAvailableAssets = redemptionAssetsVault.availableRedemptionAssets();
        assertGt(newAvailableAssets, initialAvailableAssets, "Redemption assets should increase after donation");
        
        // 4. Call withdrawSurplus to process the rewards
        vm.prank(actors.ops.REDEMPTION_ASSET_WITHDRAWER);
        withdrawalQueueManager.withdrawSurplusRedemptionAssets(depositAmount / 2);
    
    }
}