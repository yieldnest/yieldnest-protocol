/// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {ContractAddresses} from "script/ContractAddresses.sol";
import {BaseScript} from "script/BaseScript.s.sol";
import { IEigenPodManager } from "lib/eigenlayer-contracts/src/contracts/interfaces/IEigenPodManager.sol";
import {IStakingNode} from "src/interfaces/IStakingNode.sol";
import {DeployPooledDepositsVaults} from "script/DeployPooledDepositsVaults.s.sol";
import {Utils} from "script/Utils.sol";
import {ProxyAdmin} from "lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {console} from "lib/forge-std/src/console.sol";
import {ActorAddresses} from "script/Actors.sol";

contract VerifyPooledDepositsVaults is DeployPooledDepositsVaults {

    PooledDepositsVaultsDeployment deployment;
    ActorAddresses.Actors actors;
    ContractAddresses.ChainAddresses chainAddresses;

    function run() external override {

        ContractAddresses contractAddresses = new ContractAddresses();
        chainAddresses = contractAddresses.getChainAddresses(block.chainid);

        deployment = loadPooledDepositsDeployment();
        actors = getActors();

        verifyProxyAdminOwners();
        verifyVaultOwners();
    }

    function verifyProxyAdminOwners() public view {
        for (uint i = 0; i < deployment.vaults.length; i++) {
            require(
                ProxyAdmin(Utils.getTransparentUpgradeableProxyAdminAddress(address(deployment.vaults[i]))).owner()
                == actors.admin.PROXY_ADMIN_OWNER,
                "PooledDepositsVault: PROXY_ADMIN_OWNER INVALID"
            );
            console.log("\u2705 Verified proxy admin owner for vault at index", i);
        }
    }

    function verifyVaultOwners() public view {
        for (uint i = 0; i < deployment.vaults.length; i++) {
            require(
                deployment.vaults[i].owner() == actors.ops.POOLED_DEPOSITS_OWNER,
                "PooledDepositsVault: OWNER INVALID"
            );
            console.log("\u2705 Verified owner for vault at index", i);
        }
    }
}

