// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {BaseScript} from "script/BaseScript.s.sol";

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {TransparentUpgradeableProxy} from
    "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IDelegationManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategyManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IStrategy} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IDepositContract} from "src/external/ethereum/IDepositContract.sol";
import {IWETH} from "src/external/tokens/IWETH.sol";

import {ITokenStakingNodesManager} from "src/interfaces/ITokenStakingNodesManager.sol";

import {IynEigen} from "src/interfaces/IynEigen.sol";
import {IRateProvider} from "src/interfaces/IRateProvider.sol";
import {IAssetRegistry} from "src/interfaces/IAssetRegistry.sol";
import {IEigenStrategyManager} from "src/interfaces/IEigenStrategyManager.sol";
import {IYieldNestStrategyManager} from "src/interfaces/IYieldNestStrategyManager.sol";
import {IYieldNestStrategyManager} from "src/interfaces/IYieldNestStrategyManager.sol";
import {ynEigen} from "src/ynEIGEN/ynEigen.sol";
import {TokenStakingNode} from "src/ynEIGEN/TokenStakingNode.sol";
import {LSDRateProvider} from "src/ynEIGEN/LSDRateProvider.sol";
import {HoleskyLSDRateProvider} from "src/testnet/HoleksyLSDRateProvider.sol";
import {EigenStrategyManager} from "src/ynEIGEN/EigenStrategyManager.sol";
import {AssetRegistry} from "src/ynEIGEN/AssetRegistry.sol";
import {TokenStakingNodesManager} from "src/ynEIGEN/TokenStakingNodesManager.sol";
import {ynEigenDepositAdapter} from "src/ynEIGEN/ynEigenDepositAdapter.sol";
import {ynEigenViewer} from "src/ynEIGEN/ynEigenViewer.sol";

import {ContractAddresses} from "script/ContractAddresses.sol";
import {ActorAddresses} from "script/Actors.sol";
import {BaseDeployer, InputStruct, Asset} from "script/ynEigenDeployer/BaseDeployer.s.sol";

import {IwstETH} from "src/external/lido/IwstETH.sol";
import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";

import {console} from "lib/forge-std/src/console.sol";

contract YnEigenDeployer is BaseDeployer {
    function run(string memory _filePath) public {
        _loadState();
        _loadJson(_filePath);
        _loadJsonData();
        _checkNetworkParams();
        // verifyData();
        vm.broadcast(_privateKey);
        _deployBasket();
        vm.startBroadcast();
    }

    function _deployBasket() internal {
        console.log(inputs.assets[0].name);
    }
}
