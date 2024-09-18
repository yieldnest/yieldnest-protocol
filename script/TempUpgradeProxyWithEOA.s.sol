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
import {ynETHRedemptionAssetsVault} from "src/ynETHRedemptionAssetsVault.sol";
import {WithdrawalQueueManager} from "src/WithdrawalQueueManager.sol";
import {IRedemptionAssetsVault} from "src/interfaces/IRedemptionAssetsVault.sol";
import {IRedeemableAsset} from "src/interfaces/IRedeemableAsset.sol";
import {ProxyAdmin} from "lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy} from "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";


import {console} from "lib/forge-std/src/console.sol";

contract TempUpgradeProxyWithEOA is BaseYnETHScript {

    function run() external {

    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    address DEFAULT_SIGNER = vm.addr(deployerPrivateKey);



    console.log("Default Signer Address:", DEFAULT_SIGNER);
    console.log("Current Block Number:", block.number);
    console.log("Current Chain ID:", block.chainid);

    // Get the ynETH contract address
    ContractAddresses contractAddresses = new ContractAddresses();
    IynETH yneth = IynETH(payable(0xe8A0fA11735b9C91F5F89340A2E2720e9c9d19fb));

    // Call previewRedeem with 1e18
    uint256 redeemAmount = 1e18; // 1 ynETH
    uint256 previewRedeemResult = yneth.previewRedeem(redeemAmount);

    console.log("Preview redeem result for 1 ynETH:", previewRedeemResult);
    return;

    vm.startBroadcast(deployerPrivateKey);

    // Upgrade StakingNodesManager
    address stakingNodesManagerAddress = 0x535b319b941A40bF117Bc5FBAdF31Fa4d08e01b9;
    address newStakingNodesManagerImplementation = 0x423137589b47B3940E494E0Cd834CE83b93294f8;
    ProxyAdmin(getTransparentUpgradeableProxyAdminAddress(stakingNodesManagerAddress)).upgradeAndCall(
        ITransparentUpgradeableProxy(stakingNodesManagerAddress),
        newStakingNodesManagerImplementation,
        ""
    );
    console.log("StakingNodesManager upgraded");

    vm.stopBroadcast();
    return;

    // Upgrade ynETH
    address ynETHAddress = 0xe8A0fA11735b9C91F5F89340A2E2720e9c9d19fb;
    address newYnETHImplementation = 0x0757477249732d8E9DE4a5B4695c9A8a6661D07C;
    ProxyAdmin(getTransparentUpgradeableProxyAdminAddress(ynETHAddress)).upgradeAndCall(
        ITransparentUpgradeableProxy(ynETHAddress),
        newYnETHImplementation,
        ""
    );
    console.log("ynETH upgraded");

    // Upgrade StakingNode for StakingNodesManager
    address newStakingNodeImplementation = 0xb0e3B0676520D469B39F18B00D772B908940192d;
    
    StakingNodesManager stakingNodesManager = StakingNodesManager(payable(stakingNodesManagerAddress));
    stakingNodesManager.upgradeStakingNodeImplementation(newStakingNodeImplementation);
    
    console.log("StakingNode implementation upgraded for StakingNodesManager");

    // Note: StakingNode is not a proxy, so we don't upgrade it here

    vm.stopBroadcast();

    }
}