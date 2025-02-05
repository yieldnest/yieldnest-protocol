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

        address _broadcaster = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        console.log("Current Block Number:", block.number);
        console.log("Current Chain ID:", block.chainid);

        StakingNode stakingNodeImplementation = new StakingNode();

        console.log("Staking Node Implementation:", address(stakingNodeImplementation));

        Deployment memory deployment = loadDeployment();

        deployment.stakingNodeImplementation = stakingNodeImplementation;

        saveDeployment(deployment);

        vm.stopBroadcast();
    }

}

// == Logs ==
//   Deployer Public Key: 0x445b64828683ae4B6D5f0542f9E97707d631A847
//   Staking Node Implementation: 0x79388c8cc46069c0e3f285f053692D7397e65e1e
//   Deployment JSON file written successfully: /Users/parth/Desktop/coding/yieldnest/prod-code-repos/yieldnest-protocol-private/deployments/ynETH-1.json
