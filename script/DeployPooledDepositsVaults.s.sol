// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {TransparentUpgradeableProxy} from "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {BaseScript} from "script/BaseScript.s.sol";
import {PooledDepositsVault} from "src/PooledDepositsVault.sol"; // Renamed from PooledDeposits to PooledDepositsVault
import {ActorAddresses} from "script/Actors.sol";
import {console} from "lib/forge-std/src/console.sol";

contract Upgrade is BaseScript {

    function run() public {

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // ynETH.sol ROLES
        ActorAddresses.Actors memory actors = getActors();

        uint256 vaultCount = 1;

        PooledDepositsVault[] memory pooledDepositsVaults = new PooledDepositsVault[](vaultCount); // Renamed from PooledDeposits to PooledDepositsVault
        vm.startBroadcast(deployerPrivateKey);

        PooledDepositsVault pooledDepositsVaultImplementation = new PooledDepositsVault(); // Renamed from PooledDeposits to PooledDepositsVault
        for (uint i = 0; i < vaultCount; i++) {
            bytes memory initData = abi.encodeWithSelector(PooledDepositsVault.initialize.selector, actors.ops.POOLED_DEPOSITS_OWNER); // Renamed from PooledDeposits to PooledDepositsVault
            TransparentUpgradeableProxy pooledDepositsVaultProxy = new TransparentUpgradeableProxy(address(pooledDepositsVaultImplementation), actors.admin.PROXY_ADMIN_OWNER, initData);
            PooledDepositsVault pooledDepositsVault = PooledDepositsVault(payable(address(pooledDepositsVaultProxy))); // Renamed from PooledDeposits to PooledDepositsVault
            pooledDepositsVaults[i] = pooledDepositsVault;
        }
        savePooledDepositsDeployment(pooledDepositsVaults);
        vm.stopBroadcast();
    }

    function getVaultsDeploymentFile() internal view returns (string memory) {
        string memory root = vm.projectRoot();
        return string.concat(root, "/deployments/PooledDepositsVaults-", vm.toString(block.chainid), "-", ".json");
    }

    function savePooledDepositsDeployment(PooledDepositsVault[] memory pooledDepositsVaults) internal { // Renamed from PooledDeposits to PooledDepositsVault

        string memory json = "deployment";
        ActorAddresses.Actors memory actors = getActors();

        // actors
        vm.serializeAddress(json, "PROXY_ADMIN_OWNER", address(actors.admin.PROXY_ADMIN_OWNER));
        vm.serializeAddress(json, "ADMIN", address(actors.admin.ADMIN));
        vm.serializeAddress(json, "STAKING_ADMIN", address(actors.admin.STAKING_ADMIN));
        vm.serializeAddress(json, "STAKING_NODES_OPERATOR", address(actors.ops.STAKING_NODES_OPERATOR)); // Assuming STAKING_NODES_ADMIN is a typo and should be STAKING_NODES_OPERATOR or another existing role in the context provided
        vm.serializeAddress(json, "VALIDATOR_MANAGER", address(actors.ops.VALIDATOR_MANAGER));
        vm.serializeAddress(json, "FEE_RECEIVER", address(actors.admin.FEE_RECEIVER));
        vm.serializeAddress(json, "PAUSE_ADMIN", address(actors.admin.PAUSE_ADMIN));
        vm.serializeAddress(json, "LSD_RESTAKING_MANAGER", address(actors.ops.LSD_RESTAKING_MANAGER));
        vm.serializeAddress(json, "STAKING_NODE_CREATOR", address(actors.ops.STAKING_NODE_CREATOR));
        vm.serializeAddress(json, "ORACLE_ADMIN", address(actors.admin.ORACLE_ADMIN));
        vm.serializeAddress(json, "DEPOSIT_BOOTSTRAPPER", address(actors.eoa.DEPOSIT_BOOTSTRAPPER));
        vm.serializeAddress(json, "POOLED_DEPOSITS_OWNER", address(actors.ops.POOLED_DEPOSITS_OWNER));

        for (uint i = 0; i < pooledDepositsVaults.length; i++) {
            vm.serializeAddress(json, string.concat("Deposit-", vm.toString(i)), address(pooledDepositsVaults[i]));
        }
        string memory finalJson = vm.serializeAddress(json, "DEFAULT_SIGNER", address(actors.eoa.DEFAULT_SIGNER));
        

        vm.writeJson(finalJson, getVaultsDeploymentFile());
    }
}
