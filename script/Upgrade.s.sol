// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {ITransparentUpgradeableProxy} from "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {BaseScript} from "script/BaseScript.s.sol";
import {ynETH} from "src/ynETH.sol";
import {StakingNodesManager} from "src/StakingNodesManager.sol";
import {RewardsDistributor} from "src/RewardsDistributor.sol";
import {StakingNode} from "src/StakingNode.sol";
import {console} from "lib/forge-std/src/console.sol";

contract Upgrade is BaseScript {
    function _deployImplementation(string memory contractName) internal returns (address, address) {
        Deployment memory deployment = loadDeployment();
        if (keccak256(bytes(contractName)) == keccak256("ynETH")) {
            ynETH impl = new ynETH();
            return (address(deployment.ynETH), address(impl));
        }
        if (keccak256(bytes(contractName)) == keccak256("StakingNodesManager")) {
            StakingNodesManager impl = new StakingNodesManager();
            return (address(deployment.stakingNodesManager), address(impl));
        }
        if (keccak256(bytes(contractName)) == keccak256("RewardsDistributor")) {
            RewardsDistributor impl = new RewardsDistributor();
            return (address(deployment.rewardsDistributor), address(impl));
        }
        // if (keccak256(bytes(contractName)) == keccak256("RewardsReceiver")) {
        //     RewardsReceiver impl = new RewardsReceiver();
        //     return (address(deployment.rewardsReceiver), address(impl));
        // }
        revert("Uknown contract");
    }

    function run(string memory contractName) public {
        Deployment memory deployment = loadDeployment();
        
        console.log("Upgrading contract with name:", contractName);

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        if (keccak256(bytes(contractName)) == keccak256("StakingNode")) {
            StakingNode impl = new StakingNode();
            StakingNodesManager stakingNodesManager = deployment.stakingNodesManager;
            
            stakingNodesManager.upgradeStakingNodeImplementation(address(impl));
        }

        (address proxyAddr, address implAddress) = _deployImplementation(contractName);
        vm.stopBroadcast();
        
        console.log(string.concat(contractName, " address (proxy):"));
        console.log(proxyAddr);
        console.log("New implementation address:");
        console.log(implAddress);

        vm.startBroadcast(deployerPrivateKey);
        ProxyAdmin(getTransparentUpgradeableProxyAdminAddress(proxyAddr)).upgradeAndCall(ITransparentUpgradeableProxy(proxyAddr), implAddress, "");
        vm.stopBroadcast();
 
    }
}
