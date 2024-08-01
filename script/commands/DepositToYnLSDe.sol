
// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {StakingNodesManager} from "src/StakingNodesManager.sol";
import {StakingNode} from "src/StakingNode.sol";
import {RewardsReceiver} from "src/RewardsReceiver.sol";
import {stdJson} from "lib/forge-std/src/StdJson.sol";
import {RewardsDistributor} from "src/RewardsDistributor.sol";
import {ynETH} from "src/ynETH.sol";
import {Script} from "lib/forge-std/src/Script.sol";
import {Utils} from "script/Utils.sol";
import {ActorAddresses} from "script/Actors.sol";
import {console} from "lib/forge-std/src/console.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ContractAddresses} from "script/ContractAddresses.sol";
import { IwstETH } from "src/external/lido/IwstETH.sol";
import { IynEigen } from "src/interfaces/IynEigen.sol";


import { BaseYnEigenScript } from "script/BaseYnEigenScript.s.sol";


contract DepositStETHToYnLSDe is BaseYnEigenScript {
    IERC20 public stETH;

    Deployment deployment;
    ActorAddresses.Actors actors;
    ContractAddresses.ChainAddresses chainAddresses;

    function tokenName() internal override pure returns (string memory) {
        return "YnLSDe";
    }

    function run() external {

        ContractAddresses contractAddresses = new ContractAddresses();
        chainAddresses = contractAddresses.getChainAddresses(block.chainid);

        deployment = loadDeployment();
        actors = getActors();

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        address _broadcaster = vm.addr(deployerPrivateKey);

        // solhint-disable-next-line no-console
        console.log("Default Signer Address:", _broadcaster);
        // solhint-disable-next-line no-console
        console.log("Current Block Number:", block.number);
        // solhint-disable-next-line no-console
        console.log("Current Chain ID:", block.chainid);

        vm.startBroadcast(deployerPrivateKey);

        stETH = IERC20(chainAddresses.lsd.STETH_ADDRESS);
        console.log("stETH contract loaded:", address(stETH));

        uint256 amount = 0.001 ether;
        console.log("Allocating ether to contract:", amount);
        vm.deal(address(this), amount);
        console.log("Depositing ether to stETH contract");
        (bool sent, ) = address(stETH).call{value: amount}("");
        require(sent, "Failed to send Ether");
        IwstETH wstETH = IwstETH(chainAddresses.lsd.WSTETH_ADDRESS);
        console.log("Approving wstETH contract to spend stETH");
        stETH.approve(address(wstETH), amount);
        console.log("Wrapping stETH to wstETH");
        wstETH.wrap(amount);
        uint256 wstETHBalance = wstETH.balanceOf(_broadcaster);
        console.log("Balance of wstETH:", wstETHBalance);

        console.log("Depositing wstETH into ynEigen");
        IynEigen ynEigen = IynEigen(deployment.ynEigen);
        wstETH.approve(address(deployment.ynEigen), wstETHBalance);

        // deposit half of it.
        ynEigen.deposit(IERC20(address(wstETH)), wstETHBalance / 2, _broadcaster);


        vm.stopBroadcast();

        console.log("Deposit successful");
    }
}

