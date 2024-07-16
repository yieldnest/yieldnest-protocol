// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IERC20} from  "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

interface IwstETH is IERC20 {
    function unwrap(uint256 _wstETHAmount) external returns (uint256);

    function wrap(uint256 _stETHAmount) external returns (uint256);

    function getWstETHByStETH(
        uint256 _stETHAmount
    ) external view returns (uint256);

    function getStETHByWstETH(
        uint256 _wstETHAmount
    ) external view returns (uint256);

    function stEthPerToken() external view returns (uint256);

    function stETH() external view returns (address);

    function getPooledEthByShares(uint256 _shares) external view returns (uint256);
}