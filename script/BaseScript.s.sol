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
import {ContractAddresses} from "script/ContractAddresses.sol";
import {TransparentUpgradeableProxy} from "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {console} from "lib/forge-std/src/console.sol";


abstract contract BaseScript is Script, Utils {
    using stdJson for string;

    struct ProxyAddresses {
        TransparentUpgradeableProxy proxy;
        ProxyAdmin proxyAdmin;
        address implementation;
    }

    ActorAddresses private _actorAddresses = new ActorAddresses();
    ContractAddresses private _contractAddresses = new ContractAddresses();

    function serializeActors(string memory json) public {
        ActorAddresses.Actors memory actors = getActors();
        vm.serializeAddress(json, "DEFAULT_SIGNER", address(actors.eoa.DEFAULT_SIGNER));
        // actors
        vm.serializeAddress(json, "PROXY_ADMIN_OWNER", address(actors.admin.PROXY_ADMIN_OWNER));
        vm.serializeAddress(json, "ADMIN", address(actors.admin.ADMIN));
        vm.serializeAddress(json, "STAKING_ADMIN", address(actors.admin.STAKING_ADMIN));
        vm.serializeAddress(json, "STAKING_NODES_OPERATOR", address(actors.ops.STAKING_NODES_OPERATOR)); // Assuming STAKING_NODES_ADMIN is a typo and should be STAKING_NODES_OPERATOR or another existing role in the context provided
        vm.serializeAddress(json, "VALIDATOR_MANAGER", address(actors.ops.VALIDATOR_MANAGER));
        vm.serializeAddress(json, "FEE_RECEIVER", address(actors.admin.FEE_RECEIVER));
        vm.serializeAddress(json, "PAUSE_ADMIN", address(actors.ops.PAUSE_ADMIN));
        vm.serializeAddress(json, "UNPAUSE_ADMIN", address(actors.admin.UNPAUSE_ADMIN));
        vm.serializeAddress(json, "STAKING_NODE_CREATOR", address(actors.ops.STAKING_NODE_CREATOR));
        vm.serializeAddress(json, "ORACLE_ADMIN", address(actors.admin.ORACLE_ADMIN));
        vm.serializeAddress(json, "DEPOSIT_BOOTSTRAPPER", address(actors.eoa.DEPOSIT_BOOTSTRAPPER));
        vm.serializeAddress(json, "POOLED_DEPOSITS_OWNER", address(actors.ops.POOLED_DEPOSITS_OWNER));
    }

    function serializeProxyElements(string memory json, string memory name, address proxy) public {
        address proxyAdmin = getTransparentUpgradeableProxyAdminAddress(proxy);
        address implementation = getTransparentUpgradeableProxyImplementationAddress(proxy);
        vm.serializeAddress(json, string.concat("proxy-", name), proxy);
        vm.serializeAddress(json, string.concat("proxyAdmin-", name), proxyAdmin);
        vm.serializeAddress(json, string.concat("implementation-", name), implementation);
    }

    function loadProxyAddresses(string memory jsonContent, string memory contractName) internal pure returns (ProxyAddresses memory) {
        ProxyAddresses memory proxyAddresses;
        proxyAddresses.proxy = TransparentUpgradeableProxy(payable(jsonContent.readAddress(string.concat(".proxy-", contractName))));
        proxyAddresses.proxyAdmin = ProxyAdmin(jsonContent.readAddress(string.concat(".proxyAdmin-", contractName)));
        proxyAddresses.implementation = jsonContent.readAddress(string.concat(".implementation-", contractName));
        return proxyAddresses;
    }

    function getActors() public returns (ActorAddresses.Actors memory actors) {
        return _actorAddresses.getActors(block.chainid);
    }

    function getChainAddresses() public returns (ContractAddresses.ChainAddresses memory chainAddresses) {
        return _contractAddresses.getChainAddresses(block.chainid);
    }

    function isSupportedChainId(uint256 chainId) public returns (bool) {
        return _contractAddresses.isSupportedChainId(chainId);
    }
}
