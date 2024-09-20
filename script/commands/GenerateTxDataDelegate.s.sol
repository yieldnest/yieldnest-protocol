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
        stakingNodes[0] = 0x7E312a16214ceDb43E3CD68BDc508c36CfD7c356;
        stakingNodes[1] = 0x2B055a6898C0518Ed35733B162eC4C7459e9ACda;
        stakingNodes[2] = 0xb7ae463C61366214a656c7B0365F462a6ed5D180;
        stakingNodes[3] = 0x692E4991fD98c5aFB8e48f339Eda3DDd4240f0d6;
        stakingNodes[4] = 0xDc9D9eff40BA2d4c8c0816f4982a5eaE52Df8863;

        ContractAddresses contractAddresses = new ContractAddresses();
        ContractAddresses.ChainAddresses memory chainAddresses = contractAddresses.getChainAddresses(block.chainid);
        IStakingNodesManager stakingNodesManager = IStakingNodesManager(0x6B566CB6cDdf7d140C59F84594756a151030a0C3);
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