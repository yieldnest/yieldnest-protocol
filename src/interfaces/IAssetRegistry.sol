// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

interface IAssetRegistry {
    struct AssetData {
        bool active;
    }

    function assetData(IERC20 asset) external view returns (AssetData memory);
    function addAsset(IERC20 asset, uint256 initialBalance) external;
    function disableAsset(IERC20 asset) external;
    function deleteAsset(IERC20 asset) external;
    function totalAssets() external view returns (uint256);
    function convertToUnitOfAccount(IERC20 asset, uint256 amount) external view returns (uint256);
    function assetIsSupported(IERC20 asset) external returns (bool);
}
