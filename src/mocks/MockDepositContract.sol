// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IDepositContract} from "../interfaces/IDepositContract.sol";

contract MockDepositContract is IDepositContract {
    function deposit(
        bytes calldata pubkey,
        bytes calldata withdrawal_credentials,
        bytes calldata signature,
        bytes32 deposit_data_root
    ) external payable override {
        // Mock implementation, does nothing
    }


    /// @notice Query the current deposit root hash.
    /// @return The deposit root hash.
    function get_deposit_root() external view returns (bytes32) {
      revert("Not Callable");
    }

    /// @notice Query the current deposit count.
    /// @return The deposit count encoded as a little endian 64-bit number.
    function get_deposit_count() external view returns (bytes memory) {
      revert("Not Callable");
    }
}
