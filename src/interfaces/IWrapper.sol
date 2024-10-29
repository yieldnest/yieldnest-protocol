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

    /// @notice Converts the user's underlying asset amount to the equivalent user asset amount.
    /// @dev This function handles the conversion for wrapped staked ETH (wstETH) and wrapped other ETH (woETH),
    ///      returning the equivalent amount in the respective wrapped token.
    /// @param _asset The ERC20 token for which the conversion is being made.
    /// @param _userUnderlyingView The amount of the underlying asset.
    /// @return The equivalent amount in the user asset denomination.
    function toUserAssetAmount(IERC20 _asset, uint256 _userUnderlyingView) external view returns (uint256);
}