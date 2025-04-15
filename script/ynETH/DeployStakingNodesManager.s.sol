// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {BaseYnETHScript} from "script/ynETH/BaseYnETHScript.s.sol";
import {StakingNodesManager} from "src/StakingNodesManager.sol";
import {console} from "lib/forge-std/src/console.sol";
import {HoleskyStakingNodesManager} from "src/HoleskyStakingNodesManager.sol";

contract DeployStakingNodesManager is BaseYnETHScript {

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        address publicKey = vm.addr(deployerPrivateKey);
        console.log("Deployer Public Key:", publicKey);

        vm.startBroadcast(deployerPrivateKey);

        console.log("Current Block Number:", block.number);
        console.log("Current Chain ID:", block.chainid);

        HoleskyStakingNodesManager holeSkyStakingNodesManagerImplementation = new HoleskyStakingNodesManager();

        console.log("HoleskyStakingNodesManager Implementation:", address(holeSkyStakingNodesManagerImplementation));

        vm.stopBroadcast();
    }

}

// == Logs ==
// Deployer Public Key: 0x8bA7eF4EA0C986E729AB0d12462345eF53b0521d
//   Current Block Number: 3595151
//   Current Chain ID: 17000
//   HoleskyStakingNodesManager Implementation: 0x9b51f1b677F5670ED375b824f769a1db3ea783f5

