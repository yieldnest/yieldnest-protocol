// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {ynEigenViewer} from "../src/ynEIGEN/ynEigenViewer.sol";

import "./BaseYnEigenScript.s.sol";

contract DeployYnEigenViewer is BaseScript {

    ynEigenViewer public viewer;

    address public constant ASSET_REGISTRY = 0xc92b41c727AC4bB5D64D9a3CC5541Ef7113578b0;
    address public constant YNEIGEN = 0x36594E4127F9335A1877A510c6F20D2F95138Fcd;
    address public constant TOKEN_STAKING_NODES_MANAGER = 0xc87e63553fCd94A833cb512AF9244DE9001f8eB3;
    address public constant RATE_PROVIDER = 0xCA4c0f3C573cC3Ae09C312aBd1dC0Be0A12913bA;

    function run() public {

        ActorAddresses.Actors memory _actors = getActors();

        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        address _viewerImplementation = address(new ynEigenViewer(ASSET_REGISTRY, YNEIGEN, TOKEN_STAKING_NODES_MANAGER, RATE_PROVIDER));
        viewer = ynEigenViewer(address(new TransparentUpgradeableProxy(_viewerImplementation, _actors.admin.PROXY_ADMIN_OWNER, "")));

        vm.stopBroadcast();

        console.log("ynEigenViewer proxy deployed at: ", address(viewer));
        console.log("ynEigenViewer implementation deployed at: ", _viewerImplementation);
    }
}