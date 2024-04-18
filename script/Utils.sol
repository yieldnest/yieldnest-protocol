// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {Vm} from "lib/forge-std/src/Vm.sol";
import {ERC1967Utils} from "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Utils.sol";

contract Utils {
    /**
     * @dev Returns the admin address of a TransparentUpgradeableProxy contract.
     * @param proxy The address of the TransparentUpgradeableProxy.
     * @return The admin address of the proxy contract.
     */
    function getTransparentUpgradeableProxyAdminAddress(address proxy) public view returns (address) {
        address CHEATCODE_ADDRESS = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D;
        Vm vm = Vm(CHEATCODE_ADDRESS);

        bytes32 adminSlot = vm.load(proxy, ERC1967Utils.ADMIN_SLOT);
        return address(uint160(uint256(adminSlot)));
    }

    /**
     * @dev Returns the implementation address of a TransparentUpgradeableProxy contract.
     * @param proxy The address of the TransparentUpgradeableProxy.
     * @return The implementation address of the proxy contract.
     */
    function getTransparentUpgradeableProxyImplementationAddress(address proxy) public view returns (address) {
        address CHEATCODE_ADDRESS = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D;
        Vm vm = Vm(CHEATCODE_ADDRESS);

        bytes32 implementationSlot = vm.load(proxy, ERC1967Utils.IMPLEMENTATION_SLOT);
        return address(uint160(uint256(implementationSlot)));
    }

    /**
     * @dev Compares two uint256 values and checks if their difference is within a specified threshold.
     * @param value1 The first uint256 value.
     * @param value2 The second uint256 value.
     * @param threshold The threshold for the difference between value1 and value2.
     * @return bool Returns true if the difference between value1 and value2 is less than or equal to the threshold.
     */
    function compareWithThreshold(uint256 value1, uint256 value2, uint256 threshold) public pure returns (bool) {
        if(value1 > value2) {
            return (value1 - value2) <= threshold;
        } else {
            return (value2 - value1) <= threshold;
        }
    }

    /**
     * @dev Compares two uint256 values (representing rebasing token balances) and checks if their difference is within an implicit threshold of 1-2 wei, allowing for a slight decrease only.
     * @param value1 The first uint256 value, typically the lower or equal value in the context of rebasing tokens.
     * @param value2 The second uint256 value, typically the higher or equal value in the context of rebasing tokens.
     * @return bool Returns true if value1 is less than or equal to value2 and the difference between value2 and value1 is 1 or 2 wei.
     */
    function compareRebasingTokenBalances(uint256 value1, uint256 value2) public pure returns (bool) {
        if(value1 > value2) {
            return false; // value1 should not be greater than value2
        } else {
            uint256 difference = value2 - value1;
            return difference <= 2; // Allow for a 1-2 wei difference only
        }
    }
}