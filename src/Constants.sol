// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IStrategy} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";

address constant ETH_ASSET = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
uint256 constant YNETH_UNIT = 1e18;
uint256 constant ONE_GWEI = 1e9;
IStrategy constant beaconChainETHStrategy = IStrategy(0xbeaC0eeEeeeeEEeEeEEEEeeEEeEeeeEeeEEBEaC0);
uint256 constant DEFAULT_VALIDATOR_STAKE = 32 ether;