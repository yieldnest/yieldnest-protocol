// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity 0.8.24;

import {IERC20, IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {ITokenStakingNodesManager,ITokenStakingNode} from "../../../src/interfaces/ITokenStakingNodesManager.sol";

import {ynEigenViewer} from "../../../src/ynEIGEN/ynEigenViewer.sol";

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

    function testGetYnLSDeAssets() public {
        IERC20[] memory _assets = assetRegistry.getAssets();
        assertTrue(_assets.length > 0, "testGetYnLSDeAssets: E0");

        ynEigenViewer.AssetInfo[] memory _assetsInfo = _ynEigenViewer.getYnLSDeAssets();
        for (uint256 i = 0; i < _assets.length; ++i) {
            assertEq(_assetsInfo[i].asset, address(_assets[i]), "testGetYnLSDeAssets: E1");
            assertEq(_assetsInfo[i].name, IERC20Metadata(address(_assets[i])).name(), "testGetYnLSDeAssets: E2");
            assertEq(_assetsInfo[i].symbol, IERC20Metadata(address(_assets[i])).symbol(), "testGetYnLSDeAssets: E3");
            assertEq(_assetsInfo[i].ratioOfTotalAssets, 0, "testGetYnLSDeAssets: E4");
            assertEq(_assetsInfo[i].totalBalance, 0, "testGetYnLSDeAssets: E5");
        }
    }
}