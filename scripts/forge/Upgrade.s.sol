// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
/* solhint-disable no-console */

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import "./BaseScript.s.sol";

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
        if (keccak256(bytes(contractName)) == keccak256("ynLSD")) {
            ynLSD impl = new ynLSD();
            return (address(deployment.ynLSD), address(impl));
        }
        if (keccak256(bytes(contractName)) == keccak256("YieldNestOracle")) {
            YieldNestOracle impl = new YieldNestOracle();
            return (address(deployment.yieldNestOracle), address(impl));
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
        address _broadcaster = vm.addr(deployerPrivateKey);
        vm.startBroadcast(deployerPrivateKey);

        (address proxyAddr, address implAddress) = _deployImplementation(contractName);
        vm.stopBroadcast();
        
        ITransparentUpgradeableProxy proxy = ITransparentUpgradeableProxy(proxyAddr);
        console.log(string.concat(contractName, " address (proxy):"));
        console.log(proxyAddr);
        console.log("New implementation address:");
        console.log(implAddress);

        vm.startBroadcast(deployerPrivateKey);
        deployment.proxyAdmin.upgradeAndCall(proxy, implAddress, "");
        vm.stopBroadcast();
 
    }
}
