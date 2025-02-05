// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IDelegationManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IAllocationManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";

interface IDelegationManagerWithAllocationManager is IDelegationManager {
    function allocationManager() external view returns (IAllocationManager);
}