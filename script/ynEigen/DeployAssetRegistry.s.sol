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
//   Deployer Public Key: 0x445b64828683ae4B6D5f0542f9E97707d631A847
//   Current Block Number: 22279812
//   Current Chain ID: 1
//   AssetRegistry Implementation: 0x031AE4a8a09b1779DBF69828356945fdf59D6879
