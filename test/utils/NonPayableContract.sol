/// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

contract NonPayableContract {
    // This contract does not accept direct payments
    receive() external payable {
        revert("NonPayableContract: cannot receive ETH");
    }

    fallback() external payable {
        revert("NonPayableContract: fallback cannot receive ETH");
    }
}
