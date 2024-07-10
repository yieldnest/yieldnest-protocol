/// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {ContractAddresses} from "script/ContractAddresses.sol";
import {IwstETH} from "src/external/lido/IwstETH.sol";
import "forge-std/console.sol";




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

    function get_wstETH(address receiver, uint256 amount) public returns (uint256) {
        ContractAddresses contractAddresses = new ContractAddresses();
        ContractAddresses.ChainAddresses memory chainAddresses = contractAddresses.getChainAddresses(block.chainid);

        IwstETH wsteth = IwstETH(chainAddresses.lsd.WSTETH_ADDRESS);

        // add 1000 wei to guarantee there's always enough
        uint256 stETHToMint = amount * wsteth.stEthPerToken() / 1e18 + 1000;
        IERC20 stETH = IERC20(chainAddresses.lsd.STETH_ADDRESS);
        vm.deal(address(this), stETHToMint);
        (bool success, ) = address(stETH).call{value: stETHToMint}("");
        require(success, "ETH transfer failed");
        uint256 mintedStETH = stETH.balanceOf(address(this));
        stETH.approve(address(wsteth), mintedStETH);
        wsteth.wrap(mintedStETH);
        uint256 wstETHAmount = wsteth.balanceOf(address(this));
        require(wstETHAmount > amount, "Insufficient wstETH balance after wrapping");
        wsteth.transfer(receiver, amount);

        return amount;
    }

    function get_OETH(address receiver, uint256 amount) public returns (uint256) {
        ContractAddresses contractAddresses = new ContractAddresses();
        ContractAddresses.ChainAddresses memory chainAddresses = contractAddresses.getChainAddresses(block.chainid);

        IERC20 oeth = IERC20(chainAddresses.lsd.OETH_ADDRESS);

        // Simulate obtaining OETH by wrapping ETH
        uint256 ethToDeposit = amount; // Assuming 1 ETH = 1 OETH for simplicity
        vm.deal(address(this), ethToDeposit);
        (bool success, ) = address(chainAddresses.lsd.OETH_ZAPPER_ADDRESS).call{value: ethToDeposit}("");
        require(success, "ETH transfer failed");

        require(oeth.balanceOf(address(this)) >= amount, "Insufficient OETH balance after deposit");
        oeth.transfer(receiver, amount);

        return amount;
    }
}