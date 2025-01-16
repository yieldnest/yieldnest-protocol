// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IStrategy} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IwstETH} from "src/external/lido/IwstETH.sol";
import {IERC4626} from "@openzeppelin-v5/contracts/interfaces/IERC4626.sol";
import {IynEigen} from "src/interfaces/IynEigen.sol";
import {ITokenStakingNodesManager} from "src/interfaces/ITokenStakingNodesManager.sol";

interface IEigenStrategyManager {

    function getStakedAssetsBalances(
        IERC20[] calldata assets
    ) external view returns (uint256[] memory stakedBalances);

    function getStakedAssetBalance(IERC20 asset) external view returns (uint256 stakedBalance);

    function strategies(IERC20 asset) external view returns (IStrategy);

    function wstETH() external view returns (IwstETH);
    function woETH() external view returns (IERC4626);
    function oETH() external view returns (IERC20);
    function stETH() external view returns (IERC20);
    function ynEigen() external view returns (IynEigen);
    function tokenStakingNodesManager() external view returns (ITokenStakingNodesManager);
}