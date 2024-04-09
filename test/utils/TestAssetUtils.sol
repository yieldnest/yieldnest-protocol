/// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {ContractAddresses} from "script/ContractAddresses.sol";

contract TestAssetUtils is Test {
    function get_stETH(address receiver, uint256 amount) public returns (uint256 balance) {
        ContractAddresses contractAddresses = new ContractAddresses();
        ContractAddresses.ChainAddresses memory chainAddresses = contractAddresses.getChainAddresses(block.chainid);

        address stETH_Whale = block.chainid == 1 
            ? 0x93c4b944D05dfe6df7645A86cd2206016c51564D 
            : 0x66b25CFe6B9F0e61Bd80c4847225Baf4EE6Ba0A2;


        vm.startPrank(stETH_Whale);
        IERC20 steth = IERC20(chainAddresses.lsd.STETH_ADDRESS);
        steth.approve(receiver, amount);
        steth.transfer(receiver, amount);
        vm.stopPrank();
        return steth.balanceOf(receiver);
        

    }
}