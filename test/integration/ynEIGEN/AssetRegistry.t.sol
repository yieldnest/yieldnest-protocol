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
import {IFrxEthWethDualOracle} from "src/external/frax/IFrxEthWethDualOracle.sol";
import {IsfrxETH} from "src/external/frax/IsfrxETH.sol";
import {IAccessControl} from "lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";

import "forge-std/console.sol";

contract AssetRegistryTest is ynEigenIntegrationBaseTest {

    TestAssetUtils testAssetUtils;

    constructor() {
        testAssetUtils = new TestAssetUtils();
    }

    function setUp() public override {
        super.setUp();

        vm.prank(actors.ops.STAKING_NODE_CREATOR);
        tokenStakingNodesManager.createTokenStakingNode();
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
        IFrxEthWethDualOracle FRX_ETH_WETH_DUAL_ORACLE = IFrxEthWethDualOracle(testAssetUtils.FRX_ETH_WETH_DUAL_ORACLE());
        uint256 realRate = IsfrxETH(FRAX_ASSET).pricePerShare() * FRX_ETH_WETH_DUAL_ORACLE.getCurveEmaEthPerFrxEth() / 1e18;
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

    function testWSTETHconvertFromUnitOfAccountFuzz(uint256 amount) public {
        vm.assume(amount < 1000000 ether);

        IERC20 asset = IERC20(chainAddresses.lsd.WSTETH_ADDRESS); // Using wstETH as the asset
        uint256 realRate = IstETH(chainAddresses.lsd.STETH_ADDRESS).getPooledEthByShares(1e18);
        uint256 expectedConvertedAmount = amount * 1e18 / realRate; // Calculating the expected converted amount based on the real rate
        uint256 convertedAmount = assetRegistry.convertFromUnitOfAccount(asset, amount);
        assertEq(convertedAmount, expectedConvertedAmount, "Converted amount should match expected value based on real rate");
    }

    function testsfrxETHconvertFromUnitOfAccountFuzz(uint256 amount) public {
        vm.assume(amount < 1000000 ether);

        IERC20 asset = IERC20(chainAddresses.lsd.SFRXETH_ADDRESS); // Using wstETH as the asset
        address FRAX_ASSET = chainAddresses.lsd.SFRXETH_ADDRESS;
        IFrxEthWethDualOracle FRX_ETH_WETH_DUAL_ORACLE = IFrxEthWethDualOracle(testAssetUtils.FRX_ETH_WETH_DUAL_ORACLE());
        uint256 realRate = IsfrxETH(FRAX_ASSET).pricePerShare() * FRX_ETH_WETH_DUAL_ORACLE.getCurveEmaEthPerFrxEth() / 1e18;
        uint256 expectedConvertedAmount = amount * 1e18 / realRate; // Calculating the expected converted amount based on the real rate
        uint256 convertedAmount = assetRegistry.convertFromUnitOfAccount(asset, amount);
        assertEq(convertedAmount, expectedConvertedAmount, "Converted amount should match expected value based on real rate");
    }

    function testRETHconvertFromUnitOfAccountFuzz(uint256 amount) public {
        vm.assume(amount < 1000000 ether);

        IERC20 asset = IERC20(chainAddresses.lsd.RETH_ADDRESS); // Using rETH as the asset
        uint256 realRate = IrETH(chainAddresses.lsd.RETH_ADDRESS).getExchangeRate();
        uint256 expectedConvertedAmount = amount * 1e18 / realRate; // Calculating the expected converted amount based on the real rate
        uint256 convertedAmount = assetRegistry.convertFromUnitOfAccount(asset, amount);
        assertEq(convertedAmount, expectedConvertedAmount, "Converted amount should match expected value based on real rate");
    }

    function testWOETHconvertFromUnitOfAccountFuzz(uint256 amount) public {
        vm.assume(amount < 1000000 ether);

        IERC20 asset = IERC20(chainAddresses.lsd.WOETH_ADDRESS); // Using woETH as the asset
        uint256 realRate = IERC4626(chainAddresses.lsd.WOETH_ADDRESS).previewRedeem(1e18);
        uint256 expectedConvertedAmount = amount * 1e18 / realRate; // Calculating the expected converted amount based on the real rate
        uint256 convertedAmount = assetRegistry.convertFromUnitOfAccount(asset, amount);
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

    // ============================================================================================
    // AssetRegistry.addAsset
    // ============================================================================================

    function testAddAsset() public {
        uint256 totalAssetsBefore = assetRegistry.totalAssets();

        IERC20 swellAsset = IERC20(chainAddresses.lsd.SWELL_ADDRESS);
        IStrategy swellStrategy = IStrategy(chainAddresses.lsdStrategies.SWELL_STRATEGY_ADDRESS);
        vm.prank(actors.admin.EIGEN_STRATEGY_ADMIN);
        eigenStrategyManager.setStrategy(swellAsset, swellStrategy);

        vm.prank(actors.admin.ASSET_MANAGER);
        assetRegistry.addAsset(IERC20(chainAddresses.lsd.SWELL_ADDRESS));
        assertEq(
            uint256(assetRegistry.assetData(IERC20(chainAddresses.lsd.SWELL_ADDRESS)).status),
            uint256(IAssetRegistry.AssetStatus.Active),
            "Swell asset should be active after addition"
        );

        uint256 totalAssetsAfter = assetRegistry.totalAssets();
        assertEq(totalAssetsBefore, totalAssetsAfter, "Total assets count should remain the same after adding an asset");
    }

    function testAddDuplicateAssetShouldFail() public {

        IERC20 swellAsset = IERC20(chainAddresses.lsd.SWELL_ADDRESS);

        IStrategy swellStrategy = IStrategy(chainAddresses.lsdStrategies.SWELL_STRATEGY_ADDRESS);
        vm.prank(actors.admin.EIGEN_STRATEGY_ADMIN);
        eigenStrategyManager.setStrategy(swellAsset, swellStrategy);

        vm.prank(actors.admin.ASSET_MANAGER);
        assetRegistry.addAsset(swellAsset); // First addition should succeed

        vm.prank(actors.admin.ASSET_MANAGER);
        vm.expectRevert(abi.encodeWithSelector(AssetRegistry.AssetAlreadyAvailable.selector, address(swellAsset)));
        assetRegistry.addAsset(swellAsset); // Attempt to add the same asset again should fail
    }

    function testAddAssetWithNoPriceFeedShouldFail() public {
        IERC20 assetWithoutPriceFeed = IERC20(chainAddresses.lsd.CBETH_ADDRESS); // Assume SWELL has no price feed

        IStrategy strategyForAsset = IStrategy(chainAddresses.lsdStrategies.CBETH_STRATEGY_ADDRESS);
        vm.prank(actors.admin.EIGEN_STRATEGY_ADMIN);
        eigenStrategyManager.setStrategy(assetWithoutPriceFeed, strategyForAsset);

        vm.prank(actors.admin.ASSET_MANAGER);
        vm.expectRevert(abi.encodeWithSelector(AssetRegistry.RateNotAvailableForAsset.selector, assetWithoutPriceFeed));
        assetRegistry.addAsset(assetWithoutPriceFeed); // This should fail as there's no price feed for SWELL
    }

    function testAddDisabledAssetShouldFail() public {
        IERC20 swellAsset = IERC20(chainAddresses.lsd.SWELL_ADDRESS);
        IStrategy swellStrategy = IStrategy(chainAddresses.lsdStrategies.SWELL_STRATEGY_ADDRESS);

        // Add strategy and asset first
        vm.prank(actors.admin.EIGEN_STRATEGY_ADMIN);
        eigenStrategyManager.setStrategy(swellAsset, swellStrategy);
        vm.prank(actors.admin.ASSET_MANAGER);
        assetRegistry.addAsset(swellAsset);

        // Disable the asset
        vm.prank(actors.admin.ASSET_MANAGER);
        assetRegistry.disableAsset(swellAsset);

        // Attempt to add the disabled asset again should fail
        vm.prank(actors.admin.ASSET_MANAGER);
        vm.expectRevert(abi.encodeWithSelector(AssetRegistry.AssetAlreadyAvailable.selector, address(swellAsset)));
        assetRegistry.addAsset(swellAsset);
    }

    function testAddExistingAssetShouldFail() public {

        address sfrxETHAddress = address(chainAddresses.lsd.SFRXETH_ADDRESS);
        vm.prank(actors.admin.ASSET_MANAGER);
        vm.expectRevert(abi.encodeWithSelector(AssetRegistry.AssetAlreadyAvailable.selector, sfrxETHAddress));
        assetRegistry.addAsset(IERC20(sfrxETHAddress)); // Attempt to add the same asset again should fail
    }

    function testAddAssetWithoutStrategyShouldFail() public {
        IERC20 assetWithoutStrategy = IERC20(chainAddresses.lsd.SWELL_ADDRESS); // Assume OETH has no strategy set

        vm.prank(actors.admin.ASSET_MANAGER);
        vm.expectRevert(abi.encodeWithSelector(AssetRegistry.NoStrategyDefinedForAsset.selector, assetWithoutStrategy));
        assetRegistry.addAsset(assetWithoutStrategy); // This should fail as there's no strategy defined for OETH
    }


    // ============================================================================================
    // AssetRegistry.disableAsset
    // ============================================================================================

    function testDisableAsset() public {
        IERC20 swellAsset = IERC20(chainAddresses.lsd.SWELL_ADDRESS);
        IStrategy swellStrategy = IStrategy(chainAddresses.lsdStrategies.SWELL_STRATEGY_ADDRESS);

        // Add strategy and asset first
        vm.prank(actors.admin.EIGEN_STRATEGY_ADMIN);
        eigenStrategyManager.setStrategy(swellAsset, swellStrategy);
        vm.prank(actors.admin.ASSET_MANAGER);
        assetRegistry.addAsset(swellAsset);

        // Ensure the asset is active before disabling
        assertEq(
            uint256(assetRegistry.assetData(swellAsset).status),
            uint256(IAssetRegistry.AssetStatus.Active),
            "Asset should be active before disabling"
        );

        // Disable the asset
        vm.prank(actors.admin.ASSET_MANAGER);
        assetRegistry.disableAsset(swellAsset);

        // Check if the asset is now inactive
        assertEq(
            uint256(assetRegistry.assetData(swellAsset).status),
            uint256(IAssetRegistry.AssetStatus.Disabled),
            "Asset status should be Disabled after disabling"
        );
    }

    function testDisableNonexistentAssetShouldFail() public {
        IERC20 nonexistentAsset = IERC20(address(0xABCDEF)); // Assume this asset was never added

        vm.prank(actors.admin.ASSET_MANAGER);
        vm.expectRevert(abi.encodeWithSelector(AssetRegistry.AssetNotActive.selector, address(nonexistentAsset)));
        assetRegistry.disableAsset(nonexistentAsset); // This should fail as the asset does not exist
    }

    function testDisableAssetWithoutPermissionShouldFail() public {
        IERC20 swellAsset = IERC20(chainAddresses.lsd.SWELL_ADDRESS);
        IStrategy swellStrategy = IStrategy(chainAddresses.lsdStrategies.SWELL_STRATEGY_ADDRESS);

        // Add strategy and asset first
        vm.prank(actors.admin.EIGEN_STRATEGY_ADMIN);
        eigenStrategyManager.setStrategy(swellAsset, swellStrategy);
        vm.prank(actors.admin.ASSET_MANAGER);
        assetRegistry.addAsset(swellAsset);

        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), assetRegistry.ASSET_MANAGER_ROLE()));
        assetRegistry.disableAsset(swellAsset);
    }

    function testDisableAlreadyDisabledAssetShouldFail() public {
        IERC20 swellAsset = IERC20(chainAddresses.lsd.SWELL_ADDRESS);
        IStrategy swellStrategy = IStrategy(chainAddresses.lsdStrategies.SWELL_STRATEGY_ADDRESS);

        // Add strategy and asset first
        vm.prank(actors.admin.EIGEN_STRATEGY_ADMIN);
        eigenStrategyManager.setStrategy(swellAsset, swellStrategy);
        vm.prank(actors.admin.ASSET_MANAGER);
        assetRegistry.addAsset(swellAsset);

        // Disable the asset first time
        vm.prank(actors.admin.ASSET_MANAGER);
        assetRegistry.disableAsset(swellAsset);

        // Attempt to disable the already disabled asset
        vm.prank(actors.admin.ASSET_MANAGER);
        vm.expectRevert(abi.encodeWithSelector(AssetRegistry.AssetNotActive.selector, address(swellAsset)));
        assetRegistry.disableAsset(swellAsset); // This should fail as the asset is already disabled
    }

    function testDeleteAsset() public {
        IERC20 swellAsset = IERC20(chainAddresses.lsd.SWELL_ADDRESS);
        IStrategy swellStrategy = IStrategy(chainAddresses.lsdStrategies.SWELL_STRATEGY_ADDRESS);

        // Add strategy and asset first
        vm.prank(actors.admin.EIGEN_STRATEGY_ADMIN);
        eigenStrategyManager.setStrategy(swellAsset, swellStrategy);
        vm.prank(actors.admin.ASSET_MANAGER);
        assetRegistry.addAsset(swellAsset);

        // Disable before deleting
        vm.prank(actors.admin.ASSET_MANAGER);
        assetRegistry.disableAsset(swellAsset);

        // Ensure the asset is active before deleting
        assertEq(
            uint256(assetRegistry.assetData(swellAsset).status),
            uint256(IAssetRegistry.AssetStatus.Disabled),
        "Asset should be disabled before deleting");

        // Delete the asset
        vm.prank(actors.admin.ASSET_MANAGER);
        assetRegistry.deleteAsset(swellAsset);

        assertEq(
            uint256(assetRegistry.assetData(swellAsset).status),
            uint256(IAssetRegistry.AssetStatus.Unavailable),
        "Asset should be Unavailable after deletion");


        // Check if the asset is now deleted
        IERC20[] memory allAssets = assetRegistry.getAssets();
        bool assetFound = false;
        for (uint i = 0; i < allAssets.length; i++) {
            if (address(allAssets[i]) == address(swellAsset)) {
                assetFound = true;
                break;
            }
        }
        assertFalse(assetFound, "Asset should not be found after deletion");
    }

    function testDeleteAssetWithBalanceShouldFail() public {
        IERC20 swellAsset = IERC20(chainAddresses.lsd.SWELL_ADDRESS);
        IStrategy swellStrategy = IStrategy(chainAddresses.lsdStrategies.SWELL_STRATEGY_ADDRESS);

        // Add strategy and asset first
        vm.prank(actors.admin.EIGEN_STRATEGY_ADMIN);
        eigenStrategyManager.setStrategy(swellAsset, swellStrategy);
        vm.prank(actors.admin.ASSET_MANAGER);
        assetRegistry.addAsset(swellAsset);

        // Simulate balance in the asset
        vm.mockCall(address(ynEigenToken), abi.encodeWithSelector(IynEigen.assetBalance.selector, swellAsset), abi.encode(100));


        // Disable before deleting
        vm.prank(actors.admin.ASSET_MANAGER);
        assetRegistry.disableAsset(swellAsset);

        // Ensure the asset is active before deleting
        assertEq(
            uint256(assetRegistry.assetData(swellAsset).status),
            uint256(IAssetRegistry.AssetStatus.Disabled),
        "Asset should be disabled before deleting");

        // Attempt to delete the asset
        vm.prank(actors.admin.ASSET_MANAGER);
        vm.expectRevert(abi.encodeWithSelector(AssetRegistry.AssetBalanceNonZeroInPool.selector, 100));
        assetRegistry.deleteAsset(swellAsset);
    }

    function testDeleteAssetNotDisabledShouldFail() public {
        IERC20 swellAsset = IERC20(chainAddresses.lsd.SWELL_ADDRESS);
        IStrategy swellStrategy = IStrategy(chainAddresses.lsdStrategies.SWELL_STRATEGY_ADDRESS);

        // Add strategy and asset first
        vm.prank(actors.admin.EIGEN_STRATEGY_ADMIN);
        eigenStrategyManager.setStrategy(swellAsset, swellStrategy);
        vm.prank(actors.admin.ASSET_MANAGER);
        assetRegistry.addAsset(swellAsset);

        // Ensure the asset is active before attempting to delete
        assertEq(
            uint256(assetRegistry.assetData(swellAsset).status),
            uint256(IAssetRegistry.AssetStatus.Active),
        "Asset should be Active before deletion attempt");

        // Attempt to delete the asset without disabling it
        vm.prank(actors.admin.ASSET_MANAGER);
        vm.expectRevert(abi.encodeWithSelector(AssetRegistry.AssetNotDisabled.selector, address(swellAsset)));
        assetRegistry.deleteAsset(swellAsset);
    }

    function testDeleteExistingAsset_rETH() public {
        IERC20 rETHAsset = IERC20(chainAddresses.lsd.RETH_ADDRESS);

        depositAsset(chainAddresses.lsd.RETH_ADDRESS, 100, actors.admin.ASSET_MANAGER);

        vm.prank(actors.admin.ASSET_MANAGER);
        assetRegistry.disableAsset(rETHAsset);

        // Ensure the asset is disabled before deleting
        assertEq(
            uint256(assetRegistry.assetData(rETHAsset).status),
            uint256(IAssetRegistry.AssetStatus.Disabled),
        "Asset should be Disabled before deletion");


        // Delete the asset
        vm.prank(actors.admin.ASSET_MANAGER);
        vm.expectRevert(abi.encodeWithSelector(AssetRegistry.AssetBalanceNonZeroInPool.selector, 100));
        assetRegistry.deleteAsset(rETHAsset);
    }

    function testDeleteAssetWithoutPermissionShouldFail() public {
        IERC20 swellAsset = IERC20(chainAddresses.lsd.SWELL_ADDRESS);
        IStrategy swellStrategy = IStrategy(chainAddresses.lsdStrategies.SWELL_STRATEGY_ADDRESS);

        // Add strategy and asset first
        vm.prank(actors.admin.EIGEN_STRATEGY_ADMIN);
        eigenStrategyManager.setStrategy(swellAsset, swellStrategy);
        vm.prank(actors.admin.ASSET_MANAGER);
        assetRegistry.addAsset(swellAsset);

        // Try to delete the asset without proper permissions
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), assetRegistry.ASSET_MANAGER_ROLE()));
        assetRegistry.deleteAsset(swellAsset);
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