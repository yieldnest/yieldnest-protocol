// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {BaseYnEigenScript} from "script/ynEigen/BaseYnEigenScript.s.sol";
import {AssetRegistry} from "src/ynEIGEN/AssetRegistry.sol";
import {console} from "lib/forge-std/src/console.sol";

contract DeployAssetRegistry is BaseYnEigenScript {

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        address publicKey = vm.addr(deployerPrivateKey);
        console.log("Deployer Public Key:", publicKey);

        vm.startBroadcast(deployerPrivateKey);

        console.log("Current Block Number:", block.number);
        console.log("Current Chain ID:", block.chainid);

        AssetRegistry assetRegistryImplementation = new AssetRegistry();

        console.log("AssetRegistry Implementation:", address(assetRegistryImplementation));

        vm.stopBroadcast();
    }

}

// == Logs ==
//  Deployer Public Key: 0x8bA7eF4EA0C986E729AB0d12462345eF53b0521d
//   Current Block Number: 3595504
//   Current Chain ID: 17000
//   AssetRegistry Implementation: 0x655CE6CE176B7B6341397292D93198AC4F0833aA