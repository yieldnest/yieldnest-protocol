// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {BaseYnETHScript} from "script/ynETH/BaseYnETHScript.s.sol";
import {ynViewer} from "src/ynViewer.sol";
import {console} from "lib/forge-std/src/console.sol";

contract DeployYnViewer is BaseYnETHScript {

    function run() external {

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        // TODO: Get these from the deployment json file
        address ynETHProxy = 0xd9029669BC74878BCB5BE58c259ed0A277C5c16E;
        address stakingNodesManagerProxy = 0xc2387EBb4Ea66627E3543a771e260Bd84218d6a1;

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
//   Deployer Public Key: 0x8bA7eF4EA0C986E729AB0d12462345eF53b0521d
//   Current Block Number: 3595197
//   Current Chain ID: 17000
//   YnViewer Implementation: 0xE0442dA2f5B5Ca3603B55274165cCA4226FbdE76