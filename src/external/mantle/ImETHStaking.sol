// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IERC20} from  "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

interface ImETHStaking is IERC20 {
    function mETHToETH(uint256 mETHAmount) external view returns (uint256);
    function stake(uint256 minMETHAmount) external payable;
}