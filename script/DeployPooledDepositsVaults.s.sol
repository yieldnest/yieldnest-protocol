
// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {TransparentUpgradeableProxy} from "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {BaseScript} from "script/BaseScript.s.sol";
import {PooledDeposits} from "src/PooledDeposits.sol";
import {ActorAddresses} from "script/Actors.sol";
import {console} from "lib/forge-std/src/console.sol";

contract Upgrade is BaseScript {

    function run() public {

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // ynETH.sol ROLES
        ActorAddresses.Actors memory actors = getActors();

        PooledDeposits[] memory pooledDepositsVaults = new PooledDeposits[](5);
        vm.startBroadcast(deployerPrivateKey);

        PooledDeposits pooledDepositsVaultImplementation = new PooledDeposits();
        for (uint i = 0; i < 5; i++) {
            bytes memory initData = abi.encodeWithSelector(PooledDeposits.initialize.selector, actors.ops.POOLED_DEPOSITS_OWNER);
            TransparentUpgradeableProxy pooledDepositsVaultProxy = new TransparentUpgradeableProxy(address(pooledDepositsVaultImplementation), actors.PROXY_ADMIN_OWNER, initData);
            PooledDeposits pooledDepositsVault = PooledDeposits(payable(address(pooledDepositsVaultProxy)));
            pooledDepositsVaults[i] = pooledDepositsVault;
        }
        savePooledDepositsDeployment(pooledDepositsVaults);
        vm.stopBroadcast();
    }

    function savePooledDepositsDeployment(PooledDeposits[] memory pooledDepositsVaults) internal {
        string memory json = "pooledDepositsVaultsDeployment";
        for (uint i = 0; i < pooledDepositsVaults.length; i++) {
            vm.serializeAddress(json, vm.toString(i), address(pooledDepositsVaults[i]));
        }
        vm.writeJson(json, getDeploymentFile());
    }
}
