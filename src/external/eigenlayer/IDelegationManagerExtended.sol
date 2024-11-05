// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;
import {IDelegationManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";


interface IDelegationManagerExtended is IDelegationManager {
    /// @notice Mapping: hash of withdrawal inputs, aka 'withdrawalRoot' => whether the withdrawal is pending
    function pendingWithdrawals(bytes32) external view returns (bool);
}
