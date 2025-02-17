// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IAllocationManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";

interface IAllocationManagerExtended is IAllocationManager {
    function ALLOCATION_CONFIGURATION_DELAY() external view returns (uint32);
    function DEALLOCATION_DELAY() external view returns (uint32);
}
