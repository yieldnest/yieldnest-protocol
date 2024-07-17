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
import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {IrETH} from "src/external/rocketpool/IrETH.sol";
import { IwstETH } from "src/external/lido/IwstETH.sol";
import {IstETH} from "src/external/lido/IstETH.sol";
import {IAccessControl} from "lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";

import "forge-std/console.sol";

/**
 * @dev Work in progress (WIP) for generating NatSpec comments for the AssetRegistryTest contract.
 * This includes descriptions for test functions that validate the functionality of the AssetRegistry.
 */

contract AssetRegistryTest is ynEigenIntegrationBaseTest {

    TestAssetUtils testAssetUtils;
    IERC20 swellAsset = IERC20(0xf951E335afb289353dc249e82926178EaC7DEd78); // Swell asset address

    constructor() {
        testAssetUtils = new TestAssetUtils();
    }
    
    function testTotalAssetsWithFuzzedDeposits(
        uint256 wstethAmount,
        uint256 woethAmount,
        uint256 rethAmount
        ) public {
        vm.assume(
            wstethAmount < 100 ether && wstethAmount >= 1 wei &&
            woethAmount < 100 ether && woethAmount >= 1 wei &&
            rethAmount < 100 ether && rethAmount >= 1 wei
        );

        {
            address prankedUserWstETH = address(uint160(uint256(keccak256(abi.encodePacked("wstETHUser")))));
            depositAsset(chainAddresses.lsd.WSTETH_ADDRESS, wstethAmount, prankedUserWstETH);
        }

        {
            // Deposit woETH using utility function
            address prankedUserWoETH = address(uint160(uint256(keccak256(abi.encodePacked("woETHUser")))));
            depositAsset(chainAddresses.lsd.WOETH_ADDRESS, woethAmount, prankedUserWoETH);
        }

        {
            // Deposit rETH using utility function
            address prankedUserRETH = address(uint160(uint256(keccak256(abi.encodePacked("rETHUser")))));
            depositAsset(chainAddresses.lsd.RETH_ADDRESS, rethAmount, prankedUserRETH);
        }

        uint256 wstethRate = IstETH(chainAddresses.lsd.STETH_ADDRESS).getPooledEthByShares(1e18);
        uint256 woethRate = IERC4626(chainAddresses.lsd.WOETH_ADDRESS).previewRedeem(1e18);
        uint256 rethRate = IrETH(chainAddresses.lsd.RETH_ADDRESS).getExchangeRate();

        // Calculate expected total assets
        uint256 expectedTotalAssets = (wstethAmount * wstethRate / 1e18) + (woethAmount * woethRate / 1e18) + (rethAmount * rethRate / 1e18);

        // Fetch total assets from the registry
        uint256 totalAssets = assetRegistry.totalAssets();

        // Assert total assets
        assertEq(totalAssets, expectedTotalAssets, "Total assets should match expected value based on deposited amounts and rates");

        assertEq(ynEigenToken.totalAssets(), totalAssets, "ynEigen.totalAssets should be equal to totalAssets from the registry");
    }

    function testGetAllAssetBalancesWithoutDeposits(
        uint256 wstethAmount,
        uint256 woethAmount,
        uint256 rethAmount
        ) public {
        vm.assume(
            wstethAmount < 100 ether && wstethAmount >= 1 wei &&
            woethAmount < 100 ether && woethAmount >= 1 wei &&
            rethAmount < 100 ether && rethAmount >= 1 wei
        );

        {
            address prankedUserWstETH = address(uint160(uint256(keccak256(abi.encodePacked("wstETHUser")))));
            depositAsset(chainAddresses.lsd.WSTETH_ADDRESS, wstethAmount, prankedUserWstETH);
        }

        {
            // Deposit woETH using utility function
            address prankedUserWoETH = address(uint160(uint256(keccak256(abi.encodePacked("woETHUser")))));
            depositAsset(chainAddresses.lsd.WOETH_ADDRESS, woethAmount, prankedUserWoETH);
        }

        {
            // Deposit rETH using utility function
            address prankedUserRETH = address(uint160(uint256(keccak256(abi.encodePacked("rETHUser")))));
            depositAsset(chainAddresses.lsd.RETH_ADDRESS, rethAmount, prankedUserRETH);
        }

        uint256[] memory balances = assetRegistry.getAllAssetBalances();
        IERC20[] memory assets = assetRegistry.getAssets();
        assertEq(balances.length, assets.length, "Balances and assets arrays should have the same length");
        uint256[] memory expectedBalances = new uint256[](assets.length);
        for (uint i = 0; i < assets.length; i++) {
            address assetAddress = address(assets[i]);
            if (assetAddress == chainAddresses.lsd.WSTETH_ADDRESS) {
                expectedBalances[i] = wstethAmount;
            } else if (assetAddress == chainAddresses.lsd.WOETH_ADDRESS) {
                expectedBalances[i] = woethAmount;
            } else if (assetAddress == chainAddresses.lsd.RETH_ADDRESS) {
                expectedBalances[i] = rethAmount;
            } else {
                expectedBalances[i] = 0; // Default to 0 for any other assets
            }
        }

        for (uint i = 0; i < assets.length; i++) {
            assertEq(balances[i], expectedBalances[i], "Deposited amount does not match the expected balance for the asset");
        }

        assertEq(balances.length, assets.length, "Balances array length should match the assets array length");
    }

    function testWstETHConvertToUnitOfAccountFuzz(uint256 amount) public {
        vm.assume(amount < 1000000 ether);

        // End of the Selection
        IERC20 asset = IERC20(chainAddresses.lsd.WSTETH_ADDRESS); // Using wstETH as the asset
        uint256 realRate = IstETH(chainAddresses.lsd.STETH_ADDRESS).getPooledEthByShares(1e18);
        uint256 expectedConvertedAmount = amount * realRate / 1e18; // Calculating the expected converted amount based on the real rate
        uint256 convertedAmount = assetRegistry.convertToUnitOfAccount(asset, amount);
        assertEq(convertedAmount, expectedConvertedAmount, "Converted amount should match expected value based on real rate");
    }

    function testsfrxETHConvertToUnitOfAccountFuzz(uint256 amount) public {
        vm.assume(amount < 1000000 ether);

        // End of the Selection
        IERC20 asset = IERC20(chainAddresses.lsd.SFRXETH_ADDRESS); // Using wstETH as the asset
        address FRAX_ASSET = chainAddresses.lsd.SFRXETH_ADDRESS;
        uint256 realRate = IERC4626(FRAX_ASSET).totalAssets() * 1e18 / IERC20(FRAX_ASSET).totalSupply();
        uint256 expectedConvertedAmount = amount * realRate / 1e18; // Calculating the expected converted amount based on the real rate
        uint256 convertedAmount = assetRegistry.convertToUnitOfAccount(asset, amount);
        assertEq(convertedAmount, expectedConvertedAmount, "Converted amount should match expected value based on real rate");
    }

    function testrETHConvertToUnitOfAccountFuzz(uint256 amount) public {
        vm.assume(amount < 1000000 ether);

        IERC20 asset = IERC20(chainAddresses.lsd.RETH_ADDRESS); // Using rETH as the asset
        uint256 realRate = IrETH(chainAddresses.lsd.RETH_ADDRESS).getExchangeRate();
        uint256 expectedConvertedAmount = amount * realRate / 1e18; // Calculating the expected converted amount based on the real rate
        uint256 convertedAmount = assetRegistry.convertToUnitOfAccount(asset, amount);
        assertEq(convertedAmount, expectedConvertedAmount, "Converted amount should match expected value based on real rate");
    }

    function testWoETHConvertToUnitOfAccountFuzz(uint256 amount) public {
        vm.assume(amount < 1000000 ether);

        IERC20 asset = IERC20(chainAddresses.lsd.WOETH_ADDRESS); // Using woETH as the asset
        uint256 realRate = IERC4626(chainAddresses.lsd.WOETH_ADDRESS).previewRedeem(1e18);
        uint256 expectedConvertedAmount = amount * realRate / 1e18; // Calculating the expected converted amount based on the real rate
        uint256 convertedAmount = assetRegistry.convertToUnitOfAccount(asset, amount);
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

    function testPauseActionsWrongCaller() public {
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), assetRegistry.PAUSER_ROLE()));
        assetRegistry.pauseActions();
    }

    function testUnpauseActionsWrongCaller() public {
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), assetRegistry.UNPAUSER_ROLE()));
        assetRegistry.unpauseActions();
    }

    function testGetAssets() public {
        IERC20[] memory registeredAssets = assetRegistry.getAssets();
        uint256 numAssets = registeredAssets.length;
        assertEq(numAssets, assets.length, "There should be at least one registered asset");

        for (uint i = 0; i < numAssets; i++) {
            address assetAddress = address(registeredAssets[i]);
            assertEq(assetAddress, address(assets[i]));
        }
    }

    function testAddAsset() public {

        vm.prank(actors.admin.ASSET_MANAGER);
        assetRegistry.addAsset(swellAsset);
        assertTrue(assetRegistry.assetData(swellAsset).active, "Swell asset should be active after addition");
    }

    function testAddDuplicateAsset() public {
        vm.prank(actors.admin.ASSET_MANAGER);
        assetRegistry.addAsset(swellAsset); // First addition should succeed

        vm.prank(actors.admin.ASSET_MANAGER);
        vm.expectRevert(abi.encodeWithSelector(AssetRegistry.AssetAlreadyActive.selector, address(swellAsset)));
        assetRegistry.addAsset(swellAsset); // Attempt to add the same asset again should fail
    }

    function testAddExistingAsset() public {

        address sfrxETHAddress = address(chainAddresses.lsd.SFRXETH_ADDRESS);
        vm.prank(actors.admin.ASSET_MANAGER);
        vm.expectRevert(abi.encodeWithSelector(AssetRegistry.AssetAlreadyActive.selector, sfrxETHAddress));
        assetRegistry.addAsset(IERC20(sfrxETHAddress)); // Attempt to add the same asset again should fail
    }


    // Utility functions

    function depositAsset(address assetAddress, uint256 amount, address user) internal {
        IERC20 asset = IERC20(assetAddress);
        testAssetUtils.get_Asset(assetAddress, user, amount);
        vm.prank(user);
        asset.approve(address(ynEigenToken), amount);
        vm.prank(user);
        ynEigenToken.deposit(asset, amount, user);
    }
}