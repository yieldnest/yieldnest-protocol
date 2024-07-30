// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;
import {stdJson} from "lib/forge-std/src/StdJson.sol";
import {ynEigen} from "src/ynEIGEN/ynEigen.sol";
import {AssetRegistry} from "src/ynEIGEN/AssetRegistry.sol";
import {EigenStrategyManager} from "src/ynEIGEN/EigenStrategyManager.sol";
import {TokenStakingNodesManager} from "src/ynEIGEN/TokenStakingNodesManager.sol";
import {TokenStakingNode} from "src/ynEIGEN/TokenStakingNode.sol";
import {ynEigenDepositAdapter} from "src/ynEIGEN/ynEigenDepositAdapter.sol";


import {Script} from "lib/forge-std/src/Script.sol";
import {Utils} from "script/Utils.sol";
import {ActorAddresses} from "script/Actors.sol";
import {BaseScript} from "script/BaseScript.s.sol";


import {console} from "lib/forge-std/src/console.sol";

abstract contract BaseYnEigenScript is BaseScript {
    using stdJson for string;
    
    struct Deployment {
        ynEigen ynEigen;
        AssetRegistry assetRegistry;
        EigenStrategyManager eigenStrategyManager;
        TokenStakingNodesManager tokenStakingNodesManager;
        TokenStakingNode tokenStakingNodeImplementation;
        ynEigenDepositAdapter ynEigenDepositAdapterInstance;
    }

    function tokenName() internal virtual pure returns (string memory);

    function getDeploymentFile() internal virtual view returns (string memory) {
        string memory root = vm.projectRoot();

        return string.concat(root, "/deployments/", tokenName(), "-", vm.toString(block.chainid), ".json");
    }

    function saveDeployment(Deployment memory deployment) public virtual {
        string memory json = "deployment";

        // contract addresses
        serializeProxyElements(json, tokenName(), address(deployment.ynEigen)); 
        serializeProxyElements(json, "assetRegistry", address(deployment.assetRegistry));
        serializeProxyElements(json, "eigenStrategyManager", address(deployment.eigenStrategyManager));
        serializeProxyElements(json, "tokenStakingNodesManager", address(deployment.tokenStakingNodesManager));
        vm.serializeAddress(json, "tokenStakingNodeImplementation", address(deployment.tokenStakingNodeImplementation));
        serializeProxyElements(json, "ynEigenDepositAdapter", address(deployment.ynEigenDepositAdapterInstance));

        ActorAddresses.Actors memory actors = getActors();
        // actors
        vm.serializeAddress(json, "PROXY_ADMIN_OWNER", address(actors.admin.PROXY_ADMIN_OWNER));
        vm.serializeAddress(json, "ADMIN", address(actors.admin.ADMIN));
        vm.serializeAddress(json, "STAKING_ADMIN", address(actors.admin.STAKING_ADMIN));
        vm.serializeAddress(json, "STAKING_NODES_OPERATOR", address(actors.ops.STAKING_NODES_OPERATOR));
        vm.serializeAddress(json, "PAUSE_ADMIN", address(actors.ops.PAUSE_ADMIN));
        vm.serializeAddress(json, "UNPAUSE_ADMIN", address(actors.admin.UNPAUSE_ADMIN));
        vm.serializeAddress(json, "TOKEN_STAKING_NODE_CREATOR", address(actors.ops.STAKING_NODE_CREATOR));
        vm.serializeAddress(json, "STRATEGY_CONTROLLER", address(actors.ops.STRATEGY_CONTROLLER));
        vm.serializeAddress(json, "EIGEN_STRATEGY_ADMIN", address(actors.admin.EIGEN_STRATEGY_ADMIN));
        string memory finalJson = vm.serializeAddress(json, "DEFAULT_SIGNER", address((actors.eoa.DEFAULT_SIGNER)));
        
        vm.writeJson(finalJson, getDeploymentFile());

        console.log("Deployment JSON file written successfully:", getDeploymentFile());
    }

    function loadDeployment() public view returns (Deployment memory) {
        string memory deploymentFile = getDeploymentFile();
        string memory jsonContent = vm.readFile(deploymentFile);
        Deployment memory deployment;
        deployment.ynEigen = ynEigen(payable(jsonContent.readAddress(string.concat(".proxy-",  tokenName()))));
        deployment.tokenStakingNodesManager = TokenStakingNodesManager(payable(jsonContent.readAddress(".proxy-tokenStakingNodesManager")));
        deployment.assetRegistry = AssetRegistry(payable(jsonContent.readAddress(".proxy-assetRegistry")));
        deployment.eigenStrategyManager = EigenStrategyManager(payable(jsonContent.readAddress(".proxy-eigenStrategyManager")));
        deployment.tokenStakingNodeImplementation = TokenStakingNode(payable(jsonContent.readAddress(".tokenStakingNodeImplementation")));
        deployment.ynEigenDepositAdapterInstance = ynEigenDepositAdapter(payable(jsonContent.readAddress(".proxy-ynEigenDepositAdapter")));

        return deployment;
    }
}

