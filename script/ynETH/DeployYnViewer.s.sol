// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {BaseYnETHScript} from "script/ynETH/BaseYnETHScript.s.sol";
import {ynViewer} from "src/ynViewer.sol";
import {console} from "lib/forge-std/src/console.sol";

contract DeployYnViewer is BaseYnETHScript {

    function run() external {

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        // TODO: Get these from the deployment json file
        address ynETHProxy = 0x09db87A538BD693E9d08544577d5cCfAA6373A48;
        address stakingNodesManagerProxy = 0x8C33A1d6d062dB7b51f79702355771d44359cD7d;

        address publicKey = vm.addr(deployerPrivateKey);
        console.log("Deployer Public Key:", publicKey);

        vm.startBroadcast(deployerPrivateKey);

        console.log("Current Block Number:", block.number);
        console.log("Current Chain ID:", block.chainid);

        ynViewer ynViewerImplementation = new ynViewer(ynETHProxy, stakingNodesManagerProxy);

        console.log("YnViewer Implementation:", address(ynViewerImplementation));

        vm.stopBroadcast();
        
    }
}

// == Logs ==
//   Deployer Public Key: 0x445b64828683ae4B6D5f0542f9E97707d631A847
//   Current Block Number: 22279751
//   Current Chain ID: 1
//   YnViewer Implementation: 0xb088Fe2ec4DE9711390Da7ca5a4BfD664b08519d