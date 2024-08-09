
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
import { MockOETH } from "test/mocks/MockOETH.sol";
import { IERC4626 } from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";


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

        require(_broadcaster == actors.eoa.MOCK_CONTROLLER, "Caller must be MOCK_CONTROLLER");

        // solhint-disable-next-line no-console
        console.log("Default Signer Address:", _broadcaster);
        // solhint-disable-next-line no-console
        console.log("Current Block Number:", block.number);
        // solhint-disable-next-line no-console
        console.log("Current Chain ID:", block.chainid);

        vm.startBroadcast(deployerPrivateKey);

        // Load OETH contract
        IERC20 oeth = IERC20(chainAddresses.lsd.OETH_ADDRESS);

        // Mint OETH to _broadcaster
        // Note: This assumes there's a way to mint OETH directly. In reality, you might need to interact with a specific contract or follow a different process to acquire OETH.
        uint256 oethAmount = 10 ether; // Adjust this amount as needed
        MockOETH mockOeth = MockOETH(address(oeth));
        mockOeth.mint(_broadcaster, oethAmount);

        console.log("Minted OETH amount:", oethAmount);

        // Load wOETH contract
        IERC4626 woeth = IERC4626(chainAddresses.lsd.WOETH_ADDRESS);

        // Approve wOETH to spend OETH
        oeth.approve(address(woeth), oethAmount);

        uint256 depositedOETHAmount = oethAmount / 2;
        uint256 sentOETHAmount = oethAmount - depositedOETHAmount;
        // Wrap OETH into wOETH
        uint256 woethAmount = woeth.deposit(depositedOETHAmount, _broadcaster);

        console.log("Wrapped OETH into wOETH amount:", woethAmount);

        // Define the recipient address (you may want to make this configurable)
        address recipient = _broadcaster; // or any other address you want to send to

        console.log("Sending wOETH to:", recipient);
        console.log("Amount to send:", woethAmount);
        
        woeth.transfer(recipient, woethAmount);
        
        console.log("wOETH transfer successful");

        // Transfer the remaining OETH to the recipient
        console.log("Sending OETH to:", recipient);
        console.log("Amount to send:", sentOETHAmount);
        
        oeth.transfer(recipient, sentOETHAmount);
        
        console.log("OETH transfer successful");

        vm.stopBroadcast();

        console.log("Deposit successful");
    }
}