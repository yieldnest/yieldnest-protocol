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
//   Deployer Public Key: 0x8bA7eF4EA0C986E729AB0d12462345eF53b0521d
//   Current Block Number: 3595484
//   Current Chain ID: 17000
//   EigenStrategyManager Implementation: 0x22f84aDBDafd2EA54f73bd8E049CBaBcb8a301CF
