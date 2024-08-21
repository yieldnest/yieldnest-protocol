
// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import {IwstETH} from "../../src/external/lido/IwstETH.sol";
import {IynEigen} from "../../src/interfaces/IynEigen.sol";

import {ContractAddresses} from "../ContractAddresses.sol";

import "../BaseYnEigenScript.s.sol";

contract DepositStETHToYnLSDe is BaseYnEigenScript {

    address public broadcaster;

    Deployment deployment;
    ActorAddresses.Actors actors;
    ContractAddresses.ChainAddresses chainAddresses;

    uint256 public constant AMOUNT = 0.01 ether;

    function tokenName() internal override pure returns (string memory) {
        return "YnLSDe";
    }

    function run() external {

        ContractAddresses contractAddresses = new ContractAddresses();
        chainAddresses = contractAddresses.getChainAddresses(block.chainid);
        deployment = loadDeployment();
        actors = getActors();

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        broadcaster = vm.addr(deployerPrivateKey);
        console.log("Default Signer Address:", broadcaster);
        console.log("Current Block Number:", block.number);
        console.log("Current Chain ID:", block.chainid);

        address token = _getTokenAddress(vm.prompt("Token (`sfrxETH`, `wstETH`, `mETH` and `rETH` (holesky only))"));
        uint256 path = vm.parseUint(vm.prompt("Path (`0` for deposit or `1` for send"));

        vm.startBroadcast(deployerPrivateKey);

        uint256 _amount = _getToken(token);
        if (path == 0) {
            _deposit(_amount, token); // deposit to ynEIGEN
        } else if (path == 1) {
            _send(_amount, token); // send to broadcaster
        } else {
            revert("Invalid path");
        }

        vm.stopBroadcast();

        console.log("Deposit successful");
    }

    function _getTokenAddress(string memory n) internal returns (address) {
        if (keccak256(abi.encodePacked(n)) == keccak256(abi.encodePacked("sfrxETH"))) {
            return chainAddresses.lsd.SFRXETH_ADDRESS;
        } else if (keccak256(abi.encodePacked(n)) == keccak256(abi.encodePacked("wstETH"))) {
            return chainAddresses.lsd.STETH_ADDRESS;
        } else if (keccak256(abi.encodePacked(n)) == keccak256(abi.encodePacked("mETH"))) {
            return chainAddresses.lsd.METH_ADDRESS;
        } else if (keccak256(abi.encodePacked(n)) == keccak256(abi.encodePacked("rETH")) && block.chainid == 17000) {
            return chainAddresses.lsd.RETH_ADDRESS;
        } else {
            revert("Invalid token name");
        }
    }

    function _getToken(address token) internal returns (uint256 _amount) {
        if (token == chainAddresses.lsd.SFRXETH_ADDRESS) {
            _amount = _getSFRXETH();
        } else if (token == chainAddresses.lsd.STETH_ADDRESS) {
            _amount = _getWSTETH();
        } else if (token == chainAddresses.lsd.METH_ADDRESS) {
            _amount = _getMETH();
        } else if (token == chainAddresses.lsd.RETH_ADDRESS) {
            _amount = _getRETH();
        } else {
            revert("Invalid token address");
        }
    }

    function _getSFRXETH() internal returns (uint256) {
        IfrxMinter frxMinter = IfrxMinter(0xbAFA44EFE7901E04E39Dad13167D089C559c1138); // @todo - holesky?
        frxMinter.submitAndDeposit{value: AMOUNT}(broadcaster);
        IERC4626 sfrxETH = IERC4626(chainAddresses.lsd.SFRXETH_ADDRESS);
        IERC20 frxETH = IERC4626(chainAddresses.lsd.FRXETH_ADDRESS); // @todo
        frxETH.approve(address(sfrxETH), AMOUNT);
        return sfrxETH.deposit(AMOUNT, broadcaster);
    }

    function _getWSTETH() internal returns (uint256) {
        (bool sent, ) = chainAddresses.lsd.STETH_ADDRESS.call{value: AMOUNT}("");
        require(sent, "Failed to send Ether");

        uint256 _stETHBalance = IERC20(chainAddresses.lsd.STETH_ADDRESS).balanceOf(broadcaster);
        IERC20(chainAddresses.lsd.STETH_ADDRESS).approve(chainAddresses.lsd.WSTETH_ADDRESS, _stETHBalance);
        return IwstETH(chainAddresses.lsd.WSTETH_ADDRESS).wrap(_stETHBalance);
    }

    // function _getMETH() internal returns (uint256) { // @todo
    //     ImETHStaking mETHStaking = ImETHStaking(0xe3cBd06D7dadB3F4e6557bAb7EdD924CD1489E8f);
    //     IERC20 mETH = IERC20(chainAddresses.lsd.METH_ADDRESS);

    //     uint256 ethRequired = mETHStaking.mETHToETH(amount) + 1 ether;
    //     vm.deal(address(this), ethRequired);
    //     mETHStaking.stake{value: ethRequired}(amount);

    //     require(mETH.balanceOf(address(this)) >= amount, "Insufficient mETH balance after staking");
    //     mETH.transfer(receiver, amount);

    //     return amount;
    // }

    // function _getRETH() internal returns (uint256) { // @todo
    //     uint256 ethRequired = AMOUNT * 1e18 / IrETH(chainAddresses.lsd.RETH_ADDRESS).getExchangeRate();
    //     // NOTE: only works if pool is not at max capacity (it may be)
    //     IRocketPoolDepositPool(0xDD3f50F8A6CafbE9b31a427582963f465E745AF8).deposit{value: ethRequired}(); // @todo - holesky?

    //     require(IERC20(chainAddresses.lsd.RETH_ADDRESS).balanceOf(address(this)) >= amount, "Insufficient rETH balance after deposit");
    //     IERC20(chainAddresses.lsd.RETH_ADDRESS).transfer(receiver, amount);
    // }

    function _deposit(uint256 amount, address token) internal { // @todo - if token is wsteth/oeth use deposit adapter
        IERC20(token).approve(chainAddresses.ynEigen.YNEIGEN_ADDRESS, amount);
        IynEigen(chainAddresses.ynEigen.YNEIGEN_ADDRESS).deposit(IERC20(token), amount, user);
    }

    // function _send(uint256 amount, address token) internal { // @todo

    // }
}