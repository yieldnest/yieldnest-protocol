// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {StakingNodesManager} from "src/StakingNodesManager.sol";
import {StakingNode} from "src/StakingNode.sol";
import {RewardsReceiver} from "src/RewardsReceiver.sol";
import {ynLSD} from "src/ynLSD.sol";
import {stdJson} from "lib/forge-std/src/StdJson.sol";
import {YieldNestOracle} from "src/YieldNestOracle.sol";
import {LSDStakingNode} from "src/LSDStakingNode.sol";
import {RewardsDistributor} from "src/RewardsDistributor.sol";
import {ynETH} from "src/ynETH.sol";
import {Script} from "lib/forge-std/src/Script.sol";
import {Utils} from "script/Utils.sol";
import {ActorAddresses} from "script/Actors.sol";

abstract contract BaseScript is Script, Utils {
    using stdJson for string;
    

    struct Deployment {
        ynETH ynETH;
        StakingNodesManager stakingNodesManager;
        RewardsReceiver executionLayerReceiver;
        RewardsReceiver consensusLayerReceiver;
        RewardsDistributor rewardsDistributor;
        StakingNode stakingNodeImplementation;
    }

    struct ynLSDDeployment {
        ynLSD ynlsd;
        LSDStakingNode lsdStakingNodeImplementation;
        YieldNestOracle yieldNestOracle;
    }

    function getDeploymentFile() internal view returns (string memory) {
        string memory root = vm.projectRoot();
        return string.concat(root, "/deployments/ynETH-", vm.toString(block.chainid), "-", vm.toString(block.timestamp), ".json");
    }

    function saveDeployment(Deployment memory deployment) public {
        string memory json = "deployment";

        // contract addresses
        vm.serializeAddress(json, "ynETH", address(deployment.ynETH)); // Assuming ynETH should be serialized as a boolean for simplicity
        vm.serializeAddress(json, "stakingNodesManager", address(deployment.stakingNodesManager));
        vm.serializeAddress(json, "executionLayerReceiver", address(deployment.executionLayerReceiver));
        vm.serializeAddress(json, "consensusLayerReceiver", address(deployment.consensusLayerReceiver));
        vm.serializeAddress(json, "rewardsDistributor", address(deployment.rewardsDistributor));
        vm.serializeAddress(json, "stakingNodeImplementation", address(deployment.stakingNodeImplementation));

        ActorAddresses.Actors memory actors = getActors();
        // actors
        vm.serializeAddress(json, "PROXY_ADMIN_OWNER", address(actors.admin.PROXY_ADMIN_OWNER));
        vm.serializeAddress(json, "ADMIN", address(actors.admin.ADMIN));
        vm.serializeAddress(json, "STAKING_ADMIN", address(actors.admin.STAKING_ADMIN));
        vm.serializeAddress(json, "STAKING_NODES_OPERATOR", address(actors.ops.STAKING_NODES_OPERATOR));
        vm.serializeAddress(json, "VALIDATOR_MANAGER", address(actors.ops.VALIDATOR_MANAGER));
        vm.serializeAddress(json, "FEE_RECEIVER", address(actors.admin.FEE_RECEIVER));
        vm.serializeAddress(json, "PAUSE_ADMIN", address(actors.admin.PAUSE_ADMIN));
        vm.serializeAddress(json, "LSD_RESTAKING_MANAGER", address(actors.ops.LSD_RESTAKING_MANAGER));
        vm.serializeAddress(json, "STAKING_NODE_CREATOR", address(actors.ops.STAKING_NODE_CREATOR));
        vm.serializeAddress(json, "ORACLE_ADMIN", address(actors.admin.ORACLE_ADMIN));
        vm.serializeAddress(json, "DEPOSIT_BOOTSTRAPPER", address(actors.eoa.DEPOSIT_BOOTSTRAPPER));

        string memory finalJson = vm.serializeAddress(json, "DEFAULT_SIGNER", address((actors.eoa.DEFAULT_SIGNER)));
        vm.writeJson(finalJson, getDeploymentFile());
    }

    function loadDeployment() public view returns (Deployment memory) {
        string memory deploymentFile = getDeploymentFile();
        string memory jsonContent = vm.readFile(deploymentFile);
        Deployment memory deployment;
        deployment.ynETH = ynETH(payable(jsonContent.readAddress(".ynETH")));
        deployment.stakingNodesManager = StakingNodesManager(payable(jsonContent.readAddress(".stakingNodesManager")));
        deployment.executionLayerReceiver = RewardsReceiver(payable(jsonContent.readAddress(".executionLayerReceiver")));
        deployment.consensusLayerReceiver = RewardsReceiver(payable(jsonContent.readAddress(".consensusLayerReceiver")));
        deployment.rewardsDistributor = RewardsDistributor(payable(jsonContent.readAddress(".rewardsDistributor")));
        deployment.stakingNodeImplementation = StakingNode(payable(jsonContent.readAddress(".stakingNodeImplementation")));

        return deployment;
    }

    function saveynLSDDeployment(ynLSDDeployment memory deployment) public {
        string memory json = "ynLSDDeployment";
        ActorAddresses.Actors memory actors = getActors();
        string memory finalJson = vm.serializeAddress(json, "DEFAULT_SIGNER", address(actors.eoa.DEFAULT_SIGNER));
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
        vm.serializeAddress(json, "ynlsd", address(deployment.ynlsd));
        vm.serializeAddress(json, "lsdStakingNodeImplementation", address(deployment.lsdStakingNodeImplementation));
        vm.serializeAddress(json, "yieldNestOracle", address(deployment.yieldNestOracle));
        vm.writeJson(finalJson, getDeploymentFile());
    }

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
        vm.serializeAddress(json, "PAUSE_ADMIN", address(actors.admin.PAUSE_ADMIN));
        vm.serializeAddress(json, "LSD_RESTAKING_MANAGER", address(actors.ops.LSD_RESTAKING_MANAGER));
        vm.serializeAddress(json, "STAKING_NODE_CREATOR", address(actors.ops.STAKING_NODE_CREATOR));
        vm.serializeAddress(json, "ORACLE_ADMIN", address(actors.admin.ORACLE_ADMIN));
        vm.serializeAddress(json, "DEPOSIT_BOOTSTRAPPER", address(actors.eoa.DEPOSIT_BOOTSTRAPPER));
        vm.serializeAddress(json, "POOLED_DEPOSITS_OWNER", address(actors.ops.POOLED_DEPOSITS_OWNER));
    }

    function loadynLSDDeployment() public view returns (ynLSDDeployment memory) {
        string memory deploymentFile = getDeploymentFile();
        string memory jsonContent = vm.readFile(deploymentFile);
        ynLSDDeployment memory deployment;
        deployment.ynlsd = ynLSD(payable(jsonContent.readAddress(".ynlsd")));
        deployment.lsdStakingNodeImplementation = LSDStakingNode(payable(jsonContent.readAddress(".lsdStakingNodeImplementation")));
        deployment.yieldNestOracle = YieldNestOracle(payable(jsonContent.readAddress(".yieldNestOracle")));

        return deployment;
    }

    function getActors() public returns (ActorAddresses.Actors memory actors) {
        return (new ActorAddresses()).getActors(block.chainid);
    }

}
