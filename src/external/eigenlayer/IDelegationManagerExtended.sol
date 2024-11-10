// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;
import {IDelegationManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategy} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";


interface IDelegationManagerExtended is IDelegationManager {
    /// @notice Mapping: hash of withdrawal inputs, aka 'withdrawalRoot' => whether the withdrawal is pending
    function pendingWithdrawals(bytes32) external view returns (bool);

    /**
     * @notice Returns the number of actively-delegatable shares a staker has across all strategies.
     * @dev Returns two empty arrays in the case that the Staker has no actively-delegateable shares.
     */
    function getDelegatableShares(address staker) external view returns (IStrategy[] memory, uint256[] memory);
}
