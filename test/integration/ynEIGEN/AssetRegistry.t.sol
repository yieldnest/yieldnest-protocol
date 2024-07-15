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
    function testTotalAssets() public {
        uint256 expectedTotalAssets = 1000000; // Example expected total assets
        uint256 totalAssets = assetRegistry.totalAssets();
        assertEq(totalAssets, expectedTotalAssets, "Total assets should match expected value");
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