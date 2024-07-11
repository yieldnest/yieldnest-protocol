// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {ynViewer} from "../src/ynViewer.sol";

import {ContractAddresses} from "./ContractAddresses.sol";

import "./BaseScript.s.sol";

contract DeployYnViewer is BaseScript {

    uint256 public privateKey; // dev: assigned in test setup

    ynViewer public viewer;

    function run() public {

        ContractAddresses _contractAddresses = new ContractAddresses();
        ContractAddresses.ChainAddresses memory _chainAddresses = _contractAddresses.getChainAddresses(block.chainid);
        ActorAddresses.Actors memory _actors = getActors();

        privateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(privateKey);

        address _viewerImplementation = address(new ynViewer(_chainAddresses.yn.YNETH_ADDRESS, _chainAddresses.yn.STAKING_NODES_MANAGER_ADDRESS));
        viewer = ynViewer(address(new TransparentUpgradeableProxy(_viewerImplementation, _actors.admin.PROXY_ADMIN_OWNER, "")));

        vm.stopBroadcast();

        console.log("ynViewer proxy deployed at: ", address(viewer));
        console.log("ynViewer implementation deployed at: ", _viewerImplementation);
    }
}