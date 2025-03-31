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

        vm.startBroadcast(deployerPrivateKey);

        console.log("Current Block Number:", block.number);
        console.log("Current Chain ID:", block.chainid);

        TokenStakingNode tokenStakingNodeImplementation = new TokenStakingNode();

        console.log("TokenStakingNode Implementation:", address(tokenStakingNodeImplementation));

        vm.stopBroadcast();
    }

}

// == Logs ==
// Deployer Public Key: 0x8bA7eF4EA0C986E729AB0d12462345eF53b0521d
//   Current Block Number: 3571474
//   Current Chain ID: 17000
//   TokenStakingNode Implementation: 0x8b5fa9e9275ded825aBE52f8EC016569d10796b2