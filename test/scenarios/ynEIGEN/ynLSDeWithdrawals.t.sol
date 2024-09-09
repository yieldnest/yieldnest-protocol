// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import "./ynLSDeUpgradeScenario.sol";

contract ynLSDeWithdrawalsTest is ynLSDeUpgradeScenario {

    function testUpgradeImplementations() public {
        test_Upgrade_AllContracts_Batch();
    }
}