/// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {ContractAddresses} from "script/ContractAddresses.sol";
import {IwstETH} from "src/external/lido/IwstETH.sol";
import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";

import "forge-std/console.sol";

interface IRocketPoolDepositPool {
    function deposit() external payable;
}

interface RETHToken {
    function getExchangeRate() external view returns (uint256);
}

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

    function get_wOETH(address receiver, uint256 amount) public returns (uint256) {
        ContractAddresses contractAddresses = new ContractAddresses();
        ContractAddresses.ChainAddresses memory chainAddresses = contractAddresses.getChainAddresses(block.chainid);

        IERC4626 woeth = IERC4626(chainAddresses.lsd.WOETH_ADDRESS);
        IERC20 oeth = IERC20(chainAddresses.lsd.OETH_ADDRESS);
        // Calculate the amount of OETH to mint using convertToAssets from the wOETH contract
        uint256 oethToMint = woeth.convertToAssets(amount) + 1 ether; // add some extra
        uint256 obtainedOETH = get_OETH(address(this), oethToMint);

        // Approve the wOETH contract to take the OETH
        oeth.approve(address(woeth), obtainedOETH);

        // Wrap the OETH into wOETH
        woeth.deposit(obtainedOETH, address(this));

        // Transfer the wrapped OETH (wOETH) to the receiver
        uint256 wOETHBalance = woeth.balanceOf(address(this));
        require(wOETHBalance >= amount, "Insufficient wOETH balance after wrapping");
        woeth.transfer(receiver, amount);

        return amount;
    }

    function get_rETHByDeposit(address receiver, uint256 amount) public returns (uint256) {
        ContractAddresses contractAddresses = new ContractAddresses();
        ContractAddresses.ChainAddresses memory chainAddresses = contractAddresses.getChainAddresses(block.chainid);

        address rocketPoolDepositPool = 0xDD3f50F8A6CafbE9b31a427582963f465E745AF8;
        IRocketPoolDepositPool depositPool = IRocketPoolDepositPool(rocketPoolDepositPool);

        IERC20 rETH = IERC20(chainAddresses.lsd.RETH_ADDRESS);

        uint256 rETHExchangeRate = RETHToken(chainAddresses.lsd.RETH_ADDRESS).getExchangeRate();
        uint256 ethRequired = amount * 1e18 / rETHExchangeRate + 1 ether;
        vm.deal(address(this), ethRequired);
        // NOTE: only works if pool is not at max capacity (it may be)
        depositPool.deposit{value: ethRequired}();

        require(rETH.balanceOf(address(this)) >= amount, "Insufficient rETH balance after deposit");
        rETH.transfer(receiver, amount);

        return amount;
    }

    function get_rETH(address receiver, uint256 amount) public returns (uint256) {

        ContractAddresses contractAddresses = new ContractAddresses();
        ContractAddresses.ChainAddresses memory chainAddresses = contractAddresses.getChainAddresses(block.chainid);

        IERC20 rETH = IERC20(chainAddresses.lsd.RETH_ADDRESS);
        address rethWhale = 0xCc9EE9483f662091a1de4795249E24aC0aC2630f;
        vm.prank(rethWhale);
        rETH.transfer(receiver, amount);

        return amount;
    }
}