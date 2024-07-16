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
import { LidoToken } from "src/ynEIGEN/LSDRateProvider.sol";

import "forge-std/console.sol";


/**
 * @dev Work in progress (WIP) for generating NatSpec comments for the AssetRegistryTest contract.
 * This includes descriptions for test functions that validate the functionality of the AssetRegistry.
 */

contract AssetRegistryTest is ynEigenIntegrationBaseTest {
    function testTotalAssetsWithFuzzedDeposits(uint256 wstethAmount, uint256 woethAmount, uint256 rethAmount) public {
        vm.assume(
            wstethAmount < 100 ether && 
            wstethAmount > 10 wei && 
            woethAmount < 100 ether && 
            woethAmount > 10 wei && 
            rethAmount < 100 ether && 
            rethAmount > 10 wei
        );

        TestAssetUtils testAssetUtils = new TestAssetUtils();

        {
            // Deposit wstETH
            IERC20 wstETH = IERC20(chainAddresses.lsd.WSTETH_ADDRESS);
            address prankedUserWstETH = address(uint160(uint256(keccak256(abi.encodePacked("wstETHUser")))));
            TestAssetUtils testAssetUtils = new TestAssetUtils();
            testAssetUtils.get_wstETH(prankedUserWstETH, wstethAmount);

            vm.prank(prankedUserWstETH);
            wstETH.approve(address(ynEigenToken), wstethAmount);
            vm.prank(prankedUserWstETH);
            ynEigenToken.deposit(wstETH, wstethAmount, prankedUserWstETH);
        }

        {
            // Deposit woETH
            IERC20 woETH = IERC20(chainAddresses.lsd.WOETH_ADDRESS);
            address prankedUserWoETH = address(uint160(uint256(keccak256(abi.encodePacked("woETHUser")))));
            vm.prank(prankedUserWoETH);
            testAssetUtils.get_wOETH(prankedUserWoETH, woethAmount);
            vm.prank(prankedUserWoETH);
            woETH.approve(address(ynEigenToken), woethAmount);
            vm.prank(prankedUserWoETH);
            ynEigenToken.deposit(woETH, woethAmount, prankedUserWoETH);
        }

        {
            // Deposit rETH
            IERC20 rETH = IERC20(chainAddresses.lsd.RETH_ADDRESS);
            address prankedUserRETH = address(uint160(uint256(keccak256(abi.encodePacked("rETHUser")))));
            testAssetUtils.get_rETH(prankedUserRETH, rethAmount);
            vm.prank(prankedUserRETH);
            rETH.approve(address(ynEigenToken), rethAmount);
            vm.prank(prankedUserRETH);
            ynEigenToken.deposit(rETH, rethAmount, prankedUserRETH);
        }

        uint256 wstethRate = rateProvider.rate(chainAddresses.lsd.WSTETH_ADDRESS);
        uint256 woethRate = rateProvider.rate(chainAddresses.lsd.WOETH_ADDRESS);
        uint256 rethRate = rateProvider.rate(chainAddresses.lsd.RETH_ADDRESS);

        // Calculate expected total assets
        uint256 expectedTotalAssets = (wstethAmount * wstethRate / 1e18) + (woethAmount * woethRate / 1e18) + (rethAmount * rethRate / 1e18);

        // Fetch total assets from the registry
        uint256 totalAssets = assetRegistry.totalAssets();

        // Assert total assets
        assertEq(totalAssets, expectedTotalAssets, "Total assets should match expected value based on deposited amounts and rates");
    }

    function testGetAllAssetBalances() public {
        uint256[] memory expectedBalances = new uint256[](2);
        expectedBalances[0] = 500000; // Example balance for asset 1
        expectedBalances[1] = 500000; // Example balance for asset 2
        uint256[] memory balances = assetRegistry.getAllAssetBalances();
        for (uint i = 0; i < balances.length; i++) {
            assertEq(balances[i], expectedBalances[i], "Asset balance does not match expected value");
        }
    }

    function testConvertToUnitOfAccountFuzz(uint256 amount) public {
        vm.assume(amount < 1000000 ether);
        // End of the Selection
        IERC20 asset = IERC20(chainAddresses.lsd.WSTETH_ADDRESS); // Using wstETH as the asset
        uint256 realRate = LidoToken(chainAddresses.lsd.STETH_ADDRESS).getPooledEthByShares(1e18); // Fetching the rate using LidoToken interface
        uint256 expectedConvertedAmount = amount * realRate / 1e18; // Calculating the expected converted amount based on the real rate
        uint256 convertedAmount = assetRegistry.convertToUnitOfAccount(asset, amount);
        console.log("Expected Converted Amount:", expectedConvertedAmount);
        console.log("Actual Converted Amount:", convertedAmount);
        assertEq(convertedAmount, expectedConvertedAmount, "Converted amount should match expected value based on real rate");
    }

    function testPauseActions() public {
        vm.prank(actors.ops.PAUSE_ADMIN);
        assetRegistry.pauseActions();
        assertTrue(assetRegistry.actionsPaused(), "Actions should be paused");
    }

    function testUnpauseActions() public {
        vm.prank(actors.admin.UNPAUSE_ADMIN);
        assetRegistry.unpauseActions();
        assertFalse(assetRegistry.actionsPaused(), "Actions should be unpaused");
    }
}