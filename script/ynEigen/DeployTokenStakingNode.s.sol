// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {BaseYnEigenScript} from "script/ynEigen/BaseYnEigenScript.s.sol";
import {TokenStakingNode} from "src/ynEIGEN/TokenStakingNode.sol";
import {console} from "lib/forge-std/src/console.sol";

contract DeployTokenStakingNode is BaseYnEigenScript {

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        address publicKey = vm.addr(deployerPrivateKey);
        console.log("Deployer Public Key:", publicKey);

        address _broadcaster = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        console.log("Current Block Number:", block.number);
        console.log("Current Chain ID:", block.chainid);

        TokenStakingNode tokenStakingNodeImplementation = new TokenStakingNode();

        console.log("TokenStakingNode Implementation:", address(tokenStakingNodeImplementation));

        vm.stopBroadcast();
    }

}

// == Logs ==
//   Deployer Public Key: 0x445b64828683ae4B6D5f0542f9E97707d631A847
//   TokenStakingNode Implementation: 0x28fD4C04620D95c4BeC9397E2D303937779C41FD