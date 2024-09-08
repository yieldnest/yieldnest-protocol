// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity 0.8.24;

import {IERC20, IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {ITokenStakingNodesManager,ITokenStakingNode} from "../../../src/interfaces/ITokenStakingNodesManager.sol";

import {ynEigenViewer} from "../../../src/ynEIGEN/ynEigenViewer.sol";
import {console} from "forge-std/console.sol";
import "./ynEigenIntegrationBaseTest.sol";

interface IAssetRegistryView {
    function assets() external view returns (IERC20Metadata[] memory);
}

contract ynEigenViewerTest is ynEigenIntegrationBaseTest {

    ynEigenViewer private _ynEigenViewer;

    function setUp() public override {
        super.setUp();
        _ynEigenViewer = new ynEigenViewer(
            address(assetRegistry),
            address(ynEigenToken),
            address(tokenStakingNodesManager),
            address(rateProvider)
        );
    }

    function testGetAllStakingNodes() public {
        ITokenStakingNode[] memory _nodes = _ynEigenViewer.getAllStakingNodes();
        assertEq(_nodes.length, 0, "There should be no nodes");
    }

    function testGetYnEigenAssets() public {
        IERC20[] memory _assets = assetRegistry.getAssets();
        assertTrue(_assets.length > 0, "testGetYnEigenAssets: E0");

        ynEigenViewer.AssetInfo[] memory _assetsInfo = _ynEigenViewer.getYnEigenAssets();
        for (uint256 i = 0; i < _assets.length; ++i) {
            assertEq(_assetsInfo[i].asset, address(_assets[i]), "testGetYnEigenAssets: E1");
            assertEq(_assetsInfo[i].name, IERC20Metadata(address(_assets[i])).name(), "testGetYnEigenAssets: E2");
            assertEq(_assetsInfo[i].symbol, IERC20Metadata(address(_assets[i])).symbol(), "testGetYnEigenAssets: E3");
            assertEq(_assetsInfo[i].ratioOfTotalAssets, 0, "testGetYnEigenAssets: E4");
            assertEq(_assetsInfo[i].totalBalance, 0, "testGetYnEigenAssets: E5");
        }
    }

    function testPreviewDepositStETH() public {
        // Set up test amount
        uint256 testAmount = 1 ether;

        // Log STETH_ADDRESS
        console.log("STETH_ADDRESS:", address(chainAddresses.lsd.STETH_ADDRESS));

        // Call previewDeposit
        uint256 expectedShares = _ynEigenViewer.previewDeposit(IERC20(chainAddresses.lsd.STETH_ADDRESS), testAmount);

        // Verify the result
        assertTrue(expectedShares > 0, "Expected shares should be greater than 0");
    }

    function testGetRate() public {
        // Get rate
        uint256 rate = _ynEigenViewer.getRate();

        // Verify that the rate is not zero
        assertEq(rate, 1e18, "Rate is 1 with no deposits");
    }
}