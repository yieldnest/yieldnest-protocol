// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

interface IAssetRegistry {
    function addAsset(address asset, uint256 initialBalance) external;
    function disableAsset(address asset) external;
    function deleteAsset(address asset) external;
    function assetIsSupported(address asset) external view returns (bool);
    function totalAssets() external view returns (uint256);
    function convertToUnitOfAccount(address asset, uint256 amount) external view returns (uint256);
}
