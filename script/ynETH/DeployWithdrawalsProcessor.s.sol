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

        address _broadcaster = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        console.log("Current Block Number:", block.number);
        console.log("Current Chain ID:", block.chainid);

        WithdrawalsProcessor withdrawalsProcessorImplementation = new WithdrawalsProcessor();

        console.log("Withdrawals Processor Implementation:", address(withdrawalsProcessorImplementation));

        vm.stopBroadcast();
        
    }
}

// HOLESKY DEPLOYMENT
// == Logs ==
//   Deployer Public Key: 0x445b64828683ae4B6D5f0542f9E97707d631A847
//   Current Block Number: 3375332
//   Current Chain ID: 17000
//   Withdrawals Processor Implementation: 0x9904c5D441947dB77cee7F401Ed76C9fb3754f2C