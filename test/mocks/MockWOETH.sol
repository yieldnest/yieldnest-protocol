// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { ERC4626Upgradeable } from "lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/ERC4626Upgradeable.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MockWOETH is ERC4626Upgradeable {
    using SafeERC20 for IERC20;

    function initialize(
        ERC20 underlying_
    ) public initializer {
        __ERC20_init("Mock WOETH", "MWOETH");
        __ERC4626_init(underlying_);
    }
}
