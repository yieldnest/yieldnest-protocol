// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

interface IRedemptionAssetsVault {

    // Events
    event AssetsDeposited( address indexed asset, address indexed depositor, uint256 amount);
    event AssetTransferred(address indexed asset, address indexed redeemer, address indexed to, uint256 amount);
    event AssetWithdrawn(address indexed asset, address indexed redeemer, address indexed to, uint256 amount);

    function transferRedemptionAssets(address _asset, address _to, uint256 _amount, bytes calldata /* data */) external;

    function withdrawRedemptionAssets(IERC20 _asset, uint256 _amount) external;

    function redemptionRate(IERC20 asset) external view returns (uint256);

    function availableRedemptionAssets(address _asset) external view returns (uint256);
}
