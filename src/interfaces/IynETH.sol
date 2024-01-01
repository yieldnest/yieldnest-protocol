// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

interface IynETH is IERC20 {

    function withdrawETH(uint ethAmount) external;

    function processWithdrawnETH() external payable;
}
