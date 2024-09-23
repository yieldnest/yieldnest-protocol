// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

interface IWrapper {

    /// @notice Wraps the given amount of the given token.
    /// @param _amount The amount to wrap.
    /// @param _token The token to wrap.
    /// @return The amount of wrapped tokens and the wrapped token.
    function wrap(uint256 _amount, IERC20 _token) external returns (uint256, IERC20);

    /// @notice Unwraps the given amount of the given token.
    /// @param _amount The amount to unwrap.
    /// @param _token The token to unwrap.
    /// @return The amount of unwrapped tokens and the unwrapped token.
    function unwrap(uint256 _amount, IERC20 _token) external returns (uint256, IERC20);
}