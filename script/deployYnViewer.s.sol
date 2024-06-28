// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {ynViewer} from "../src/ynViewer.sol";

import {ContractAddresses} from "./ContractAddresses.sol";

import "./BaseScript.s.sol";

contract DeployYnViewer is BaseScript {

    uint256 public privateKey; // dev: assigned in test setup

    ynViewer public viewer;

    function run() public {

        ContractAddresses _contractAddresses = new ContractAddresses();
        ContractAddresses.ChainAddresses memory _chainAddresses = _contractAddresses.getChainAddresses(block.chainid);

        privateKey == 0 ? vm.envUint("PRIVATE_KEY") : privateKey;
        vm.startBroadcast(privateKey);

        viewer = new ynViewer(_chainAddresses.yn.YNETH_ADDRESS, _chainAddresses.yn.STAKING_NODES_MANAGER_ADDRESS);

        vm.stopBroadcast();
    }
}