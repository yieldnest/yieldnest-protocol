// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {BaseYnEigenScript} from "script/ynEigen/BaseYnEigenScript.s.sol";
import {TokenStakingNodesManager} from "src/ynEIGEN/TokenStakingNodesManager.sol";
import {console} from "lib/forge-std/src/console.sol";

contract DeployTokenStakingNodesManager is BaseYnEigenScript {

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        address publicKey = vm.addr(deployerPrivateKey);
        console.log("Deployer Public Key:", publicKey);

        vm.startBroadcast(deployerPrivateKey);

        console.log("Current Block Number:", block.number);
        console.log("Current Chain ID:", block.chainid);

        TokenStakingNodesManager tokenStakingNodesManagerImplementation = new TokenStakingNodesManager();

        console.log("TokenStakingNodesManager Implementation:", address(tokenStakingNodesManagerImplementation));

        vm.stopBroadcast();
    }

}

// == Logs ==
//   Deployer Public Key: 0x445b64828683ae4B6D5f0542f9E97707d631A847
//   Current Block Number: 22279785
//   Current Chain ID: 1
//   TokenStakingNodesManager Implementation: 0x6Fbd79BbF9dA002c33F94D0a372F9756756adb2c