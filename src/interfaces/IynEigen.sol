// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IERC20} from  "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IAssetRegistry} from "src/interfaces/IAssetRegistry.sol";

interface IynEigen is IERC20 {

    function deposit(
        IERC20 asset,
        uint256 amount,
        address receiver
    ) external returns (uint256 shares);

    function totalAssets() external view returns (uint256);

    function convertToShares(IERC20 asset, uint256 amount) external view returns(uint256 shares);

    function previewDeposit(IERC20 asset, uint256 amount) external view returns (uint256);

    function burn(uint256 amount) external;

    function previewRedeem(IERC20 asset, uint256 shares) external view returns (uint256 assets);
    function previewRedeem(uint256 shares) external view returns (uint256);

    function convertToAssets(IERC20 asset, uint256 shares) external view returns (uint256);

    function retrieveAssets(
        IERC20[] calldata assetsToRetrieve,
        uint256[] calldata amounts
    ) external;

    function processWithdrawn(uint256 _amount, address _asset) external;

    function assetBalances(IERC20[] calldata assetsArray) external view returns (uint256[] memory balances);
    function assetBalance(IERC20 asset) external view returns (uint256 balance);

    function yieldNestStrategyManager() external view returns (address);

    function assetRegistry() external view returns (IAssetRegistry);
}