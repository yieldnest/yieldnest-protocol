// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

import {ContractAddresses} from "script/ContractAddresses.sol";
import {BaseScript} from "script/BaseScript.s.sol";
import {ActorAddresses} from "script/Actors.sol";
import {console} from "lib/forge-std/src/console.sol";

contract DeployTimelock is BaseScript {

    uint256 public privateKey; // dev: assigned in test setup

    TimelockController public timelock;

    function run() public {

        ActorAddresses.Actors memory _actors = getActors();

        privateKey == 0 ? vm.envUint("PRIVATE_KEY") : privateKey;
        vm.startBroadcast(privateKey);

        address[] memory _proposers = new address[](2);
        _proposers[0] = _actors.admin.ADMIN;
        _proposers[1] = _actors.eoa.DEFAULT_SIGNER;
        address[] memory _executors = new address[](1);
        _executors[0] = _actors.admin.ADMIN;
        timelock = new TimelockController(
            3 days, // delay
            _proposers,
            _executors,
            _actors.admin.ADMIN // admin
        );

        vm.stopBroadcast();
    }
}