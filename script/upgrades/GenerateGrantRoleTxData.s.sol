
// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {StakingNodesManager} from "src/StakingNodesManager.sol";
import {StakingNode} from "src/StakingNode.sol";
import {RewardsReceiver} from "src/RewardsReceiver.sol";
import {stdJson} from "lib/forge-std/src/StdJson.sol";
import {RewardsDistributor} from "src/RewardsDistributor.sol";
import {ynETH} from "src/ynETH.sol";
import {Script} from "lib/forge-std/src/Script.sol";
import {Utils} from "script/Utils.sol";
import {ActorAddresses} from "script/Actors.sol";
import {console} from "lib/forge-std/src/console.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ContractAddresses} from "script/ContractAddresses.sol";
import { IwstETH } from "src/external/lido/IwstETH.sol";
import { IynEigen } from "src/interfaces/IynEigen.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {BaseScript} from "script/BaseScript.s.sol";

import { BaseYnEigenScript } from "script/BaseYnEigenScript.s.sol";


contract GenerateGrantRoleTxData is BaseScript {

    function run() external {
        // Get role and account from command line arguments
        string memory roleString = vm.envString("ROLE");
        address account = vm.envAddress("ACCOUNT");

        // Convert role string to bytes32
        bytes32 role = keccak256(bytes(roleString));

        // Print role information
        console.log("Role Information:");
        console.log("----------------");
        console.log("Role (string):", roleString);
        console.log("Role (bytes32):", vm.toString(role));
        console.log("Account:", vm.toString(account));
        console.log("----------------");

        // Generate the calldata for grantRole
        bytes memory callData = abi.encodeWithSignature("grantRole(bytes32,address)", role, account);

        // Output the generated calldata
        console.log("\nGenerated Calldata:");
        console.log("--------------------");
        console.logBytes(callData);
        console.log("--------------------");
    }
}