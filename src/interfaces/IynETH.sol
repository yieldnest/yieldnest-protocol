// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

interface IynETH is IERC20 {

    function withdrawETH(uint ethAmount) external;

    function processWithdrawnETH() external payable;

    function receiveRewards() external payable;

    function setIsDepositETHPaused(bool paused) external;
}
