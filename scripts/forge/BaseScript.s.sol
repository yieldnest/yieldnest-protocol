// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "../../src/StakingNodesManager.sol";
import "../../src/RewardsReceiver.sol";
import "../../src/RewardsDistributor.sol";
import "../../src/external/tokens/WETH.sol";
import "../../src/ynETH.sol";
import "../../lib/forge-std/src/Script.sol";
import "../../lib/forge-std/src/StdJson.sol";
import "./Utils.sol";

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

    function getDeploymentFile() internal view returns (string memory) {
        string memory root = vm.projectRoot();
        return string.concat(root, "/deployments/", vm.toString(block.chainid), ".json");
    }

    function saveDeployment(Deployment memory deployment) public {
        string memory json = "deployment";

        vm.serializeAddress(json, "ynETH", address(deployment.ynETH)); // Assuming ynETH should be serialized as a boolean for simplicity
        vm.serializeAddress(json, "stakingNodesManager", address(deployment.stakingNodesManager));
        vm.serializeAddress(json, "executionLayerReceiver", address(deployment.executionLayerReceiver));
        vm.serializeAddress(json, "consensusLayerReceiver", address(deployment.consensusLayerReceiver));
        vm.serializeAddress(json, "rewardsDistributor", address(deployment.rewardsDistributor));
        vm.serializeAddress(json, "stakingNodeImplementation", address(deployment.stakingNodeImplementation));

        string memory finalJson = vm.serializeString(json, "object", "dummy");
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

}
