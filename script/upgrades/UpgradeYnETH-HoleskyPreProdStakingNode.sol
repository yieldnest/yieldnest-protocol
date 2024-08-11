pragma solidity ^0.8.24;

import "../../src/ynETH.sol";
import "../../src/StakingNodesManager.sol";
import "../../src/StakingNode.sol";
import "../../src/RewardsDistributor.sol";
import "../../src/RewardsReceiver.sol";
import "script/BaseScript.s.sol";
import {ContractAddresses} from "script/ContractAddresses.sol";
import "../../src/PreProdHoleskyStakingNodesManager.sol";
import {ProxyAdmin} from "lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy} from "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";



contract UpgradeYnETH_HoleskyPreProd is BaseScript {

    function run() external {

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        address publicKey = vm.addr(deployerPrivateKey);
        console.log("Deployer Public Key:", publicKey);

        // // ynETH.sol ROLES
        // ActorAddresses.Actors memory actors = getActors();

        address _broadcaster = vm.addr(deployerPrivateKey);

        ContractAddresses contractAddresses = new ContractAddresses();
        ContractAddresses.ChainAddresses memory chainAddresses = contractAddresses.getChainAddresses(block.chainid);
        
        StakingNodesManager stakingNodesManager = StakingNodesManager(payable(chainAddresses.yn.STAKING_NODES_MANAGER_ADDRESS));
        console.log("StakingNodesManager loaded from address:", address(stakingNodesManager));
        ynETH yneth = ynETH(payable(chainAddresses.yn.YNETH_ADDRESS));
        console.log("ynETH loaded from address:", address(yneth));

        // Print ynETH totalAssets
        uint256 totalAssets = yneth.totalAssets();
        console.log("ynETH total assets:", totalAssets);

        // Print balance for each StakingNode
        uint256 nodesLength = stakingNodesManager.nodesLength();
        for (uint256 i = 0; i < nodesLength; i++) {
            IStakingNode stakingNode = stakingNodesManager.nodes(i);
            uint256 nodeBalance = stakingNode.getETHBalance();
            console.log("Staking Node", i, "ETH balance:", nodeBalance);
        }
        vm.startBroadcast(deployerPrivateKey);

        console.log("Default Signer Address:", _broadcaster);
        console.log("Current Block Number:", block.number);
        console.log("Current Chain ID:", block.chainid);

        // Assumes _broadcaster is GLOBAL ADMIN FOR EVERYTHING


        address newStakingNodesManagerImpl = address(new PreProdHoleskyStakingNodesManager());

        // Print the number of staking nodes
        uint256 nodesLengthBefore = stakingNodesManager.nodesLength();
        console.log("Number of staking nodes before upgrade:", nodesLengthBefore);

        
        ProxyAdmin(getTransparentUpgradeableProxyAdminAddress(address(stakingNodesManager))).upgradeAndCall(ITransparentUpgradeableProxy(address(stakingNodesManager)), newStakingNodesManagerImpl, "");


        // Deploy new StakingNode implementation
        StakingNode newStakingNodeImplementation = new StakingNode();
        console.log("New StakingNode implementation deployed at:", address(newStakingNodeImplementation));

        stakingNodesManager.upgradeStakingNodeImplementation(address(newStakingNodeImplementation));

        uint256 nodesLengthAfter = stakingNodesManager.nodesLength();
        console.log("Number of staking nodes before upgrade:", nodesLengthAfter);
        // Assert that the number of staking nodes remains the same after the upgrade
        require(nodesLengthBefore == nodesLengthAfter, "Number of staking nodes changed unexpectedly");
        // Verify that totalAssets remains unchanged after the upgrade
        uint256 totalAssetsAfterUpgrade = yneth.totalAssets();
        console.log("ynETH total assets after upgrade:", totalAssetsAfterUpgrade);
        require(totalAssets + 32 ether == totalAssetsAfterUpgrade, "Total assets changed unexpectedly after upgrade");

        vm.stopBroadcast();
        console.log("Done");
    }
}