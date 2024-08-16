// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IERC20} from  "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

interface IynEigen {

    function deposit(
        IERC20 asset,
        uint256 amount,
        address receiver
    ) external returns (uint256 shares);

    function totalAssets() external view returns (uint256);

    function convertToShares(IERC20 asset, uint256 amount) external view returns(uint256 shares);

    function previewDeposit(IERC20 asset, uint256 amount) external view returns (uint256);

    function retrieveAssets(
        IERC20[] calldata assetsToRetrieve,
        uint256[] calldata amounts
    ) external;

    function assetBalances(IERC20[] calldata assetsArray) external view returns (uint256[] memory balances);
    function assetBalance(IERC20 asset) external view returns (uint256 balance);

    function yieldNestStrategyManager() external view returns (address);
}