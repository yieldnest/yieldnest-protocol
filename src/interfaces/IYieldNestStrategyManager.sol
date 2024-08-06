// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

interface IYieldNestStrategyManager {

    function getStakedAssetsBalances(
        IERC20[] calldata assets
    ) external view returns (uint256[] memory stakedBalances);

    function getStakedAssetBalance(IERC20 asset) external view returns (uint256 stakedBalance);

    function supportsAsset(IERC20 asset) external view returns (bool);

}