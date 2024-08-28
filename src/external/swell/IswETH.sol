// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IERC20} from  "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/**
    @notice interface for Swell Staked ETH swETH
 */
interface IswETH is IERC20 {
    function swETHToETHRate() external view returns (uint256);
}