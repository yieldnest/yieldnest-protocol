// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IERC20} from  "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

interface IstETH is IERC20 {
    function getPooledEthByShares(uint256 _shares) external view returns (uint256);
    function getCurrentStakeLimit() external view returns (uint256);
}
