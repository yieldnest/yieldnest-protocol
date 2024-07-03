// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {TransparentUpgradeableProxy} from "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {BaseScript} from "script/BaseScript.s.sol";
import {stdJson} from "lib/forge-std/src/StdJson.sol";
import {PooledDepositsVault} from "src/PooledDepositsVault.sol"; // Renamed from PooledDeposits to PooledDepositsVault
import {ActorAddresses} from "script/Actors.sol";
import {console} from "lib/forge-std/src/console.sol";
import {IStakingNode} from "src/interfaces/IStakingNode.sol";
import {ISignatureUtils} from "lib/eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";
import {IStakingNodesManager} from "src/interfaces/IStakingNodesManager.sol";
import {ContractAddresses} from "script/ContractAddresses.sol";

contract DelegateTransactionBuilder is BaseScript {


    function run() external {

        address[] memory stakingNodes = new address[](5);
        stakingNodes[0] = 0x412946D1c4F7e55E3F4B9dD1bA6D619E29Af9bA2;
        stakingNodes[1] = 0xAc4B7CA94c004A6D7cE9B62fb9d86DF8f6CcFc26;
        stakingNodes[2] = 0xAEBDCD5285988009C1C4cC05a8DDdd29E42304C7;
        stakingNodes[3] = 0x77F7d153Bd9e25293a95AEDFE8087F3e24D73c9e;
        stakingNodes[4] = 0xc9170a5C286a6D8C80b07d20E087e20f273A36A1;

        ContractAddresses contractAddresses = new ContractAddresses();
        ContractAddresses.ChainAddresses memory chainAddresses = contractAddresses.getChainAddresses(block.chainid);
        IStakingNodesManager stakingNodesManager = IStakingNodesManager(chainAddresses.yn.STAKING_NODES_MANAGER_ADDRESS);
        IStakingNode[] memory allNodes = stakingNodesManager.getAllNodes();
        require(allNodes.length == stakingNodes.length, "Node count mismatch.");

        for (uint i = 0; i < stakingNodes.length; i++) {
            require(address(allNodes[i]) == stakingNodes[i], "Node address mismatch.");
        }

        // https://app.eigenlayer.xyz/operator/0xa83e07353a9ed2af88e7281a2fa7719c01356d8e
        address OPERATOR_A41 = 0xa83e07353A9ED2aF88e7281a2fA7719c01356D8e;

        // https://app.eigenlayer.xyz/operator/0xDbEd88D83176316fc46797B43aDeE927Dc2ff2F5
        address OPERATOR_P2P = 0xDbEd88D83176316fc46797B43aDeE927Dc2ff2F5;


        address[] memory operators = new address[](5);
        operators[0] = OPERATOR_A41;
        operators[1] = OPERATOR_A41;
        operators[2] = OPERATOR_A41;
        operators[3] = OPERATOR_A41;
        operators[4] = OPERATOR_P2P;

        for (uint i = 0; i < stakingNodes.length; i++) {
            address currentOperator = operators[i];

            // Generate tx data for delegating to an operator
            bytes memory delegateTxData = abi.encodeWithSelector(
                IStakingNode.delegate.selector,
                currentOperator,
                ISignatureUtils.SignatureWithExpiry({signature: "", expiry: 0}),
                bytes32(0)
            );
            console.log("Node address:", stakingNodes[i]);
            console.log("Node Index:", i);
            console.log("Delegating to operator:", currentOperator);
            console.log("Delegate transaction data:", vm.toString(abi.encodePacked(delegateTxData)));
        }
    }

}