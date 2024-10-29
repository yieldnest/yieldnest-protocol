// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {console} from "lib/forge-std/src/console.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import {BaseYnEigenScript} from "script/ynEigen/BaseYnEigenScript.s.sol";

/**
 * @title GenerateYnLSDeUpgradeTxData
 * @dev This script generates the transaction data needed to upgrade a specific contract in the YnLSDe system.
 *
 * USAGE:
* --------
 * To run this script, use the following command in your terminal:
 * 
 * TOKEN=[token name] CONTRACT_TO_UPGRADE=[contract identifier] NEW_IMPLEMENTATION=[implementation address] forge script script/upgrades/GenerateYnLSDeUpgradeTxData.s.sol --legacy  --rpc-url   [rpc url]
 * 
 * 
 * Where:
 * - TOKEN: The name of the token (e.g., ynLSDe)
 * - CONTRACT_TO_UPGRADE: The name of the contract to be upgraded (e.g., rateProvider)
 * - NEW_IMPLEMENTATION: The address of the new implementation contract
 * 
 *
 *
 * EXAMPLE:
 * --------
 * # Upgrade rateProvider of ynLSDe on Holesky to the given implementation
 * TOKEN=ynLSDe CONTRACT_TO_UPGRADE=rateProvider NEW_IMPLEMENTATION=0x48c3dfd4d14e7899c4adbf8e2d5aef6af585d305 forge script script/upgrades/GenerateYnLSDeUpgradeTxData.s.sol --legacy --rpc-url https://rpc.ankr.com/eth_holesky
 *
 * This command will:
 * 1. Set the token name to 'ynLSDe'
 * 2. Specify 'rateProvider' as the contract to upgrade
 * 3. Set the new implementation address to 0x48c3dfd4d14e7899c4adbf8e2d5aef6af585d305
 * 4. Use the Holesky testnet RPC URL for execution
 *
 * The script will then generate and display the necessary transaction data for the upgrade process.
 * --------
 */

contract GenerateYnLSDeUpgradeTxData is BaseYnEigenScript {
    Deployment deployment;

    string internal _tokenName;

    function tokenName() internal view override returns (string memory) {
        return _tokenName;
    }

    function run() external {

        console.log("=== Upgrade Information ===");
        console.log("Current Block Number: %s", block.number);
        console.log("Current Chain ID: %s", block.chainid);

        _tokenName = vm.envString("TOKEN");
        string memory contractToUpgrade = vm.envString("CONTRACT_TO_UPGRADE");
        address newImplementation = vm.envAddress("NEW_IMPLEMENTATION");

        console.log("Token Name: %s", _tokenName);

        deployment = loadDeployment();

        console.log("=== Contract Upgrade Details ===");
        console.log("Contract to upgrade: %s", contractToUpgrade);
        console.log("Contract address: %s", vm.toString(getProxyAddress(contractToUpgrade)));

        console.log("New implementation: %s", vm.toString(newImplementation));

        address proxyAddress = getProxyAddress(contractToUpgrade);
        ITransparentUpgradeableProxy proxy = ITransparentUpgradeableProxy(proxyAddress);
        address proxyAdmin = getTransparentUpgradeableProxyAdminAddress(address(proxy));

        bytes memory data = ""; // Empty data for now, can be customized if needed
        bytes memory txData =
            abi.encodeWithSelector(ProxyAdmin.upgradeAndCall.selector, address(proxy), newImplementation, data);

        console.log("=== Upgrade Transaction Details ===");
        console.log("Upgrade timelock: %s", vm.toString(address(deployment.upgradeTimelock)));
        console.log("Target ProxyAdmin: %s", vm.toString(proxyAdmin));
        console.log("Upgrade transaction data:");
        console.logBytes(txData);
    }
}
