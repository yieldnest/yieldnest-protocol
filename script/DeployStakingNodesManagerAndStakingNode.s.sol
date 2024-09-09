// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;


import {TransparentUpgradeableProxy} from "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IEigenPodManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IEigenPodManager.sol";
import {IDelegationManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
// import {IDelayedWithdrawalRouter} from "lib/eigenlayer-contracts/src/contracts/interfaces/IDelayedWithdrawalRouter.sol";
import {IStrategyManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IDepositContract} from "src/external/ethereum/IDepositContract.sol";
import {IRewardsDistributor} from "src/interfaces/IRewardsDistributor.sol";
import {IynETH} from "src/interfaces/IynETH.sol";
import {IStakingNodesManager} from "src/interfaces/IStakingNodesManager.sol";
import {IWETH} from "src/external/tokens/IWETH.sol";

import {StakingNodesManager} from "src/StakingNodesManager.sol";
import {StakingNode} from "src/StakingNode.sol";
import {RewardsReceiver} from "src/RewardsReceiver.sol";
import {RewardsDistributor} from "src/RewardsDistributor.sol";
import {ynETH} from "src/ynETH.sol";
import {ContractAddresses} from "script/ContractAddresses.sol";
import {BaseScript} from "script/BaseScript.s.sol";
import {BaseYnETHScript} from "script/BaseYnETHScript.s.sol";
import {ActorAddresses} from "script/Actors.sol";

import {console} from "lib/forge-std/src/console.sol";

contract DeployNodes is BaseYnETHScript {

    ActorAddresses.Actors actors;

    function run() external {

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        address publicKey = vm.addr(deployerPrivateKey);
        console.log("Deployer Public Key:", publicKey);

        // ynETH.sol ROLES
        actors = getActors();

        address _broadcaster = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy StakingNodesManager implementation
        StakingNodesManager stakingNodesManagerImpl = new StakingNodesManager();
        console.log("StakingNodesManager implementation deployed at:", address(stakingNodesManagerImpl));

        // Deploy StakingNode implementation
        StakingNode stakingNodeImpl = new StakingNode();
        console.log("StakingNode implementation deployed at:", address(stakingNodeImpl));

        vm.stopBroadcast();

    }
}