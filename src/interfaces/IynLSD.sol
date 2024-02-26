// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

interface IynLSDEvents {
    event Deposit(address indexed sender, address indexed receiver, uint256 amount, uint256 shares, uint256 eigenShares);
}