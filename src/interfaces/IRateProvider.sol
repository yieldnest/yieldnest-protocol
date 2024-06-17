// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

interface IRateProvider {
    function rate(address _asset) external view returns (uint256);
}
