// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import "../../../script/commands/DepositToYnLSDe.s.sol";

import "forge-std/Test.sol";
import "forge-std/console.sol";

contract DepositToYnLSDeScript is DepositToYnLSDe, Test {

    function testSfrxETHDeposit() public {
        // return;
        run();
    }

    // function testSfrxETHSend()
    // function testMETHDeposit
    // function testMETHSend
    // function testRETHDeposit
    // function testRETHSend
}