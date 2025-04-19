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
//   Deployer Public Key: 0x445b64828683ae4B6D5f0542f9E97707d631A847
//   Current Block Number: 22279725
//   Current Chain ID: 1
//   Staking Node Implementation: 0x56D43f8C6c3891d081AD93B27419c37394857117

