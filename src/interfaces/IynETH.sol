// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

interface IynETH is IERC20 {
    function withdrawETH(uint256 ethAmount) external;
    function processWithdrawnETH() external payable;
    function receiveRewards() external payable;
    function updateDepositsPaused(bool paused) external;

    /// @notice Allows depositing ETH into the contract in exchange for shares.
    /// @param receiver The address to receive the minted shares.
    /// @return shares The amount of shares minted for the deposited ETH.
    function depositETH(address receiver) external payable returns (uint256 shares);
}
