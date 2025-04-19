// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {BaseYnEigenScript} from "script/ynEigen/BaseYnEigenScript.s.sol";
import {EigenStrategyManager} from "src/ynEIGEN/EigenStrategyManager.sol";
import {console} from "lib/forge-std/src/console.sol";

contract DeployYnEigenStrategyManager is BaseYnEigenScript {

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        address publicKey = vm.addr(deployerPrivateKey);
        console.log("Deployer Public Key:", publicKey);

        vm.startBroadcast(deployerPrivateKey);

        console.log("Current Block Number:", block.number);
        console.log("Current Chain ID:", block.chainid);

        EigenStrategyManager eigenStrategyManagerImplementation = new EigenStrategyManager();

        console.log("EigenStrategyManager Implementation:", address(eigenStrategyManagerImplementation));

        vm.stopBroadcast();
    }

}

// == Logs ==
//   Deployer Public Key: 0x445b64828683ae4B6D5f0542f9E97707d631A847
//   Current Block Number: 22279803
//   Current Chain ID: 1
//   EigenStrategyManager Implementation: 0xAB0153A53Db6e12c0A86D1404B509BC647333E79
