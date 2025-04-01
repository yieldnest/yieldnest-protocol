// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {BaseYnETHScript} from "script/ynETH/BaseYnETHScript.s.sol";
import {WithdrawalsProcessor} from "src/WithdrawalsProcessor.sol";
import {console} from "lib/forge-std/src/console.sol";

contract DeployWithdrawalsProcessor is BaseYnETHScript {

    function run() external {

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        address publicKey = vm.addr(deployerPrivateKey);
        console.log("Deployer Public Key:", publicKey);

        vm.startBroadcast(deployerPrivateKey);

        console.log("Current Block Number:", block.number);
        console.log("Current Chain ID:", block.chainid);

        WithdrawalsProcessor withdrawalsProcessorImplementation = new WithdrawalsProcessor();

        console.log("Withdrawals Processor Implementation:", address(withdrawalsProcessorImplementation));

        vm.stopBroadcast();
        
    }
}

// HOLESKY DEPLOYMENT
//   Withdrawals Processor Implementation: 0xAbE3b5bF154d6441C63Dc34691E4F51Dbfac3bB0
