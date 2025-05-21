// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {BaseYnEigenScript} from "script/ynEigen/BaseYnEigenScript.s.sol";
import {RedemptionAssetsVault} from "src/ynEIGEN/RedemptionAssetsVault.sol";
import {console} from "lib/forge-std/src/console.sol";

contract DeployTokenStakingNode is BaseYnEigenScript {

    function run() external {

        vm.startBroadcast();

        console.log("Current Block Number:", block.number);
        console.log("Current Chain ID:", block.chainid);

        RedemptionAssetsVault redemptionAssetsVaultImplementation = new RedemptionAssetsVault();

        console.log("RedemptionAssetsVault Implementation:", address(redemptionAssetsVaultImplementation));

        vm.stopBroadcast();
    }

}