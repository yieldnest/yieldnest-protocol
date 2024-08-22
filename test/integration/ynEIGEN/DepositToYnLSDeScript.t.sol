// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import "../../../script/commands/DepositToYnLSDe.s.sol";

import "forge-std/Test.sol";
import "forge-std/console.sol";

contract DepositToYnLSDeScript is DepositToYnLSDe, Test {

    function setUp() public {
        shouldInit = false;
        _init();
    }

    function testSfrxETHDeposit() public {
        if (block.chainid != 1) return;
        run(0, chainAddresses.lsd.SFRXETH_ADDRESS);
    }

    function testSfrxETHSend() public {
        if (block.chainid != 1) return;
        run(1, chainAddresses.lsd.SFRXETH_ADDRESS);
    }

    function testMETHDeposit() public {
        run(0, chainAddresses.lsd.METH_ADDRESS);
    }

    function testMETHSend() public {
        run(1, chainAddresses.lsd.METH_ADDRESS);
    }

    function testRETHDeposit() public {
        if (block.chainid != 17000) return;
        run(0, chainAddresses.lsd.RETH_ADDRESS);
    }

    function testRETHSend() public {
        if (block.chainid != 17000) return;
        run(1, chainAddresses.lsd.RETH_ADDRESS);
    }
}