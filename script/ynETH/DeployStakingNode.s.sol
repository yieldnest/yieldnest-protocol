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
//   Current Block Number: 3595158
//   Current Chain ID: 17000
//   Staking Node Implementation: 0x5139ad0AcA1B303ed488f2715d4B6ADA4ce69d2C


