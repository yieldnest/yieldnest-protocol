// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {BaseYnETHScript} from "script/ynETH/BaseYnETHScript.s.sol";
import {StakingNode} from "src/StakingNode.sol";
import {console} from "lib/forge-std/src/console.sol";

contract DeployStakingNode is BaseYnETHScript {

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        address publicKey = vm.addr(deployerPrivateKey);
        console.log("Deployer Public Key:", publicKey);

        vm.startBroadcast(deployerPrivateKey);

        console.log("Current Block Number:", block.number);
        console.log("Current Chain ID:", block.chainid);

        StakingNode stakingNodeImplementation = new StakingNode();

        console.log("Staking Node Implementation:", address(stakingNodeImplementation));

        vm.stopBroadcast();
    }

}

// == Logs ==
//   Deployer Public Key: 0x8bA7eF4EA0C986E729AB0d12462345eF53b0521d
//   Current Block Number: 3571435
//   Current Chain ID: 17000
//   Staking Node Implementation: 0xAbE3b5bF154d6441C63Dc34691E4F51Dbfac3bB0
//   Deployment JSON file written successfully: /Users/parth/Desktop/coding/yieldnest/prod-code-repos/yieldnest-protocol-private/deployments/ynETH-1.json


