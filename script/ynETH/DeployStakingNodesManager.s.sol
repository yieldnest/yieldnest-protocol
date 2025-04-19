// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {BaseYnETHScript} from "script/ynETH/BaseYnETHScript.s.sol";
import {StakingNodesManager} from "src/StakingNodesManager.sol";
import {console} from "lib/forge-std/src/console.sol";

contract DeployStakingNodesManager is BaseYnETHScript {

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        address publicKey = vm.addr(deployerPrivateKey);
        console.log("Deployer Public Key:", publicKey);

        vm.startBroadcast(deployerPrivateKey);

        console.log("Current Block Number:", block.number);
        console.log("Current Chain ID:", block.chainid);

        StakingNodesManager stakingNodesManagerImplementation = new StakingNodesManager();

        console.log("StakingNodesManager Implementation:", address(stakingNodesManagerImplementation));

        vm.stopBroadcast();
    }

}

// == Logs ==
//   Deployer Public Key: 0x445b64828683ae4B6D5f0542f9E97707d631A847
//   Current Block Number: 22279717
//   Current Chain ID: 1
//   StakingNodesManager Implementation: 0xf1EB27d5800f16be1B48D7f35c731554e055a7Ce

