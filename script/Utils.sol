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
}