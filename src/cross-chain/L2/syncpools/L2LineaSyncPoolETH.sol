// SPDX-License-Identifier: LZBL-1.2
pragma solidity ^0.8.20;

import {L2LineaSyncPoolETHUpgradeable} from "@layerzero/contracts/L2/syncPools/L2LineaSyncPoolETHUpgradeable.sol";

contract L2LineaSyncPoolETH is L2LineaSyncPoolETHUpgradeable {
    constructor(address endpoint) L2LineaSyncPoolETHUpgradeable(endpoint) {}
}
