
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



import { BaseYnEigenScript } from "script/BaseYnEigenScript.s.sol";


contract GenerateYnLSDeUpgradeTxData is BaseYnEigenScript {
    IERC20 public stETH;

    Deployment deployment;
    ActorAddresses.Actors actors;
    ContractAddresses.ChainAddresses chainAddresses;

    function tokenName() internal override pure returns (string memory) {
        return "YnLSDe";
    }

    function run() external {

        ContractAddresses contractAddresses = new ContractAddresses();
        chainAddresses = contractAddresses.getChainAddresses(block.chainid);

        deployment = loadDeployment();
        actors = getActors();

        // solhint-disable-next-line no-console
        console.log("Current Block Number:", block.number);
        // solhint-disable-next-line no-console
        console.log("Current Chain ID:", block.chainid);
         // Read which contract to upgrade
         string memory contractToUpgrade = vm.envString("CONTRACT_TO_UPGRADE");

        address newImplementation = vm.envAddress("NEW_IMPLEMENTATION");


        console.log(string.concat("Contract to upgrade: ", contractToUpgrade));
        console.log(string.concat("New implementation: ", vm.toString(newImplementation)));

         // Cast the contract from the deployment to the proxy
         address proxyAddress = getProxyAddress(contractToUpgrade);
         ITransparentUpgradeableProxy proxy = ITransparentUpgradeableProxy(proxyAddress);

        address proxyAdmin = getTransparentUpgradeableProxyAdminAddress(address(proxy));

         // Generate and print txData for upgradeAndCall

         bytes memory data = ""; // Empty data for now, can be customized if needed
         bytes memory txData = abi.encodeWithSelector(
             ITransparentUpgradeableProxy.upgradeToAndCall.selector,
             address(proxy),
             newImplementation,
             data
         );

         console.log("Target ProxyAdmin:", vm.toString(proxyAdmin));

         console.log("Upgrade transaction data:");
         console.logBytes(txData);
    }

}