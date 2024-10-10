// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {YnEigenDeployer} from "./YnEigenDeployer.s.sol";
import {YnEigenVerifier} from "./YnEigenVerifier.s.sol";
import {console} from "lib/forge-std/src/console.sol";

contract YnEigenScript is YnEigenDeployer, YnEigenVerifier {
    function run(string memory _filePath) public {
    // function run(string memory _filePath) public {
    //     string memory _filePath = "script/ynEigen/input/lsd-holesky.json";
        _initDeployer();
        _loadJson(_filePath);
        _validateNetwork();

        console.log("\n");
        console.log("Deployer Address:", _deployer);
        console.log("Deployer Balance:", _deployer.balance);
        console.log("Block Number:", block.number);
        console.log("ChainId:", inputs.chainId);
        console.log("Name:", inputs.name);
        console.log("Symbol:", inputs.symbol);

        console.log("Assets:");
        for (uint256 i = 0; i < inputs.assets.length; i++) {
            Asset memory asset = inputs.assets[i];
            console.log(asset.name);
            console.log(asset.token);
            console.log(asset.strategy);
        }
        console.log("\n");

        _deploy();
        _verify();
    }

    function verify(string memory _filePath) public {
        console.log("Verifying deployment in ", _filePath);
        _initDeployer();
        _loadJson(_filePath);
        _validateNetwork();
        console.log("Block Number:", block.number);
        console.log("ChainId:", inputs.chainId);
        console.log("Name:", inputs.name);
        console.log("Symbol:", inputs.symbol);
        _verify();
    }
}
