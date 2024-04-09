// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "test/mocks/MockAggregatorV3.sol";

contract DeployMockAggregator is Script {
    function run() external {
        vm.startBroadcast();
        new MockAggregatorV3();
        vm.stopBroadcast();
    }
}

// holesky: 0x8d543b63C5bBAAaAbb9032773bd85F8EefC4c92a
