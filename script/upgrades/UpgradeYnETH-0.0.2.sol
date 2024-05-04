pragma solidity ^0.8.24;

import "../../src/ynETH.sol";
import "../../src/StakingNodesManager.sol";
import "../../src/StakingNode.sol";
import "../../src/RewardsDistributor.sol";
import "../../src/RewardsReceiver.sol";
import "script/BaseScript.s.sol";
import {ContractAddresses} from "script/ContractAddresses.sol";


contract UpgradeYnETH_0_0_2 is BaseScript {
    ynETH public newynETH;
    StakingNodesManager public newStakingNodesManager;
    StakingNode public newStakingNode;
    RewardsDistributor rewardsDistributor;
    RewardsReceiver rewardsReceiver;
    ActorAddresses.Actors actors;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        address publicKey = vm.addr(deployerPrivateKey);
        console.log("Deployer Public Key:", publicKey);

        // ynETH.sol ROLES
        actors = getActors();

        address _broadcaster = vm.addr(deployerPrivateKey);

        ContractAddresses contractAddresses = new ContractAddresses();

        vm.startBroadcast(deployerPrivateKey);

        console.log("Default Signer Address:", _broadcaster);
        console.log("Current Block Number:", block.number);
        console.log("Current Chain ID:", block.chainid);

        newynETH = new ynETH();
        newStakingNodesManager = new StakingNodesManager();
        newStakingNode = new StakingNode();
        rewardsDistributor = new RewardsDistributor();
        rewardsReceiver = new RewardsReceiver();

        vm.stopBroadcast();

        saveDeployment();
    }

    function saveDeployment() public {
        string memory json = "deployment";

        // contract addresses
        vm.serializeAddress(json, "ynETHImplementation", address(newynETH)); 
        vm.serializeAddress(json, "stakingNodesManagerImplementation", address(newStakingNodesManager));
        vm.serializeAddress(json, "rewardsReceiverImplementation", address(rewardsReceiver));
        vm.serializeAddress(json, "rewardsDistributorImplementation", address(rewardsDistributor));
        string memory finalJson = vm.serializeAddress(json, "stakingNodeImplementation", address(newStakingNode));

        vm.writeJson(finalJson, getDeploymentFile());

        console.log("Deployment JSON file written successfully:", getDeploymentFile());
    }

    function getDeploymentFile() internal view override returns (string memory) {
        string memory root = vm.projectRoot();
        return string.concat(root, "/deployments/ynETH-upgrade-0.0.2", vm.toString(block.chainid), ".json");
    }
}
