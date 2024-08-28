// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";

interface IsfrxETH is IERC4626 {
    function pricePerShare() external view returns (uint256);
}