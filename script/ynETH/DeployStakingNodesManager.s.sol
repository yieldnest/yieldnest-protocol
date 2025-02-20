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

        address _broadcaster = vm.addr(deployerPrivateKey);

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
//   StakingNodesManager Implementation: 0x8E0b49B4A4384D812Bc6F55fA6412547524D41Ab
//   Deployment JSON file written successfully: /Users/parth/Desktop/coding/yieldnest/prod-code-repos/yieldnest-protocol-private/deployments/ynETH-1.json

// HOLESKY DEPLOYMENT
//   StakingNodesManager Implementation: 0x99a108a79419c62F2Ff384cE2441b435b918a252
