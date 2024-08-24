
// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import {IwstETH} from "../../src/external/lido/IwstETH.sol";
import {IynEigen} from "../../src/interfaces/IynEigen.sol";
import {ImETHStaking} from "../../src/external/mantle/ImETHStaking.sol";
import {IfrxMinter} from "../../src/external/frax/IfrxMinter.sol";

import {ContractAddresses} from "../ContractAddresses.sol";

import "../BaseYnEigenScript.s.sol";

interface IRocketPoolDepositPool {
    function deposit() external payable;
}

contract DepositToYnLSDe is BaseYnEigenScript {

    uint256 public privateKey; // dev: assigned in test setup

    bool public shouldInit = true;

    address public broadcaster;

    Deployment deployment;
    ActorAddresses.Actors actors;
    ContractAddresses.ChainAddresses chainAddresses;

    uint256 public constant AMOUNT = 0.1 ether;

    function tokenName() internal override pure returns (string memory) {
        return "YnLSDe";
    }

    function run() public {

        if (shouldInit) _init();

        address token = _getTokenAddress(vm.prompt("Token (`sfrxETH`, `wstETH`, `mETH` and `rETH` (holesky only))"));
        uint256 path = vm.parseUint(vm.prompt("Path (`0` for deposit or `1` for send"));
        run(path, token);
    }

    function run(uint256 path, address token) public {
        uint256 deployerPrivateKey = privateKey == 0 ? vm.envUint("PRIVATE_KEY") : privateKey;
        broadcaster = vm.addr(deployerPrivateKey);
        console.log("Default Signer Address:", broadcaster);
        console.log("Current Block Number:", block.number);
        console.log("Current Chain ID:", block.chainid);
        console.log("Token Address:", token);
        console.log("Path:", path);

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
        if (keccak256(abi.encodePacked(n)) == keccak256(abi.encodePacked("sfrxETH")) && block.chainid == 1) {
            return chainAddresses.lsd.SFRXETH_ADDRESS;
        } else if (keccak256(abi.encodePacked(n)) == keccak256(abi.encodePacked("wstETH"))) {
            return chainAddresses.lsd.WSTETH_ADDRESS;
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
        } else if (token == chainAddresses.lsd.WSTETH_ADDRESS) {
            _amount = _getWSTETH();
        } else if (token == chainAddresses.lsd.METH_ADDRESS) {
            _amount = _getMETH();
        } else if (token == chainAddresses.lsd.RETH_ADDRESS) {
            _amount = _getRETH();
        } else {
            revert("Invalid token address");
        }
    }

    // NOTE: not deployed on holesky
    function _getSFRXETH() internal returns (uint256) {
        return IfrxMinter(0xbAFA44EFE7901E04E39Dad13167D089C559c1138).submitAndDeposit{value: AMOUNT}(broadcaster);
    }

    function _getWSTETH() internal returns (uint256) {
        uint256 balanceBefore = IERC20(chainAddresses.lsd.STETH_ADDRESS).balanceOf(broadcaster);
        (bool sent, ) = chainAddresses.lsd.STETH_ADDRESS.call{value: AMOUNT}("");
        require(sent, "Failed to send Ether");

        uint256 amount = IERC20(chainAddresses.lsd.STETH_ADDRESS).balanceOf(broadcaster) - balanceBefore;
        IERC20(chainAddresses.lsd.STETH_ADDRESS).approve(chainAddresses.lsd.WSTETH_ADDRESS, amount);
        return IwstETH(chainAddresses.lsd.WSTETH_ADDRESS).wrap(amount);
    }

    // NOTE: fails if AMOUNT < 0.1 ether
    function _getMETH() internal returns (uint256) {
        ImETHStaking mETHStaking = block.chainid == 1
            ? ImETHStaking(0xe3cBd06D7dadB3F4e6557bAb7EdD924CD1489E8f)
            : ImETHStaking(0xbe16244EAe9837219147384c8A7560BA14946262);
        IERC20 mETH = IERC20(chainAddresses.lsd.METH_ADDRESS);
        uint256 _balanceBefore = mETH.balanceOf(broadcaster);
        mETHStaking.stake{value: AMOUNT}(mETHStaking.ethToMETH(AMOUNT));
        return mETH.balanceOf(broadcaster) - _balanceBefore;
    }

    function _getRETH() internal returns (uint256) { // NOTE: only holesky
        IRocketPoolDepositPool depositPool = IRocketPoolDepositPool(0x320f3aAB9405e38b955178BBe75c477dECBA0C27);
        uint256 _balanceBefore = IERC20(chainAddresses.lsd.RETH_ADDRESS).balanceOf(broadcaster);
        // NOTE: only works if pool is not at max capacity (it may be)
        depositPool.deposit{value: AMOUNT}();
        return IERC20(chainAddresses.lsd.RETH_ADDRESS).balanceOf(broadcaster) - _balanceBefore;
    }

    function _deposit(uint256 amount, address token) internal {
        IERC20(token).approve(chainAddresses.ynEigen.YNEIGEN_ADDRESS, amount);
        IynEigen(chainAddresses.ynEigen.YNEIGEN_ADDRESS).deposit(IERC20(token), amount, broadcaster);
    }

    function _send(uint256 amount, address token) internal {
        IERC20(token).transfer(actors.eoa.DEFAULT_SIGNER, amount);
    }

    function _init() internal {
        ContractAddresses contractAddresses = new ContractAddresses();
        chainAddresses = contractAddresses.getChainAddresses(block.chainid);
        deployment = loadDeployment();
        actors = getActors();
    }
}