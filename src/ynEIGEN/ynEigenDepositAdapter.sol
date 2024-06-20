// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {IynEigen} from "src/interfaces/IynEigen.sol";
import {IWstETH} from "src/external/lido/IWstETH.sol";

import {AccessControlUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {Initializable} from "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";

contract ynEigenDepositAdapter is Initializable, AccessControlUpgradeable {
    IynEigen public ynEigen;
    IWstETH public wstETH;
    IERC4626 public woeth;
    struct Init {
        address ynEigen;
        address wstETH;
        address woeth;
        address admin;
    }

    function initialize(Init memory init) public initializer {
        ynEigen = IynEigen(init.ynEigen);
        wstETH = IWstETH(init.wstETH);
        woeth = IERC4626(init.woeth);
        _setupRole(DEFAULT_ADMIN_ROLE, init.admin);
    }

    function depositStETH(uint256 amount, address receiver) external {
        IERC20 stETH = IERC20(wstETH.stETH());
        stETH.transferFrom(msg.sender, address(this), amount);
        stETH.approve(address(wstETH), amount);
        uint256 wstETHAmount = wstETH.wrap(amount);
        wstETH.approve(address(ynEigen), wstETHAmount);
        ynEigen.deposit(address(wstETH), wstETHAmount, receiver);
    }

    function depositOETH(uint256 amount, address receiver) external {
        IERC20 oeth = IERC20(woeth.asset());
        oeth.transferFrom(msg.sender, address(this), amount);
        oeth.approve(address(woeth), amount);
        uint256 woethShares = woeth.deposit(amount, address(this));
        woeth.approve(address(ynEigen), woethShares);
        ynEigen.deposit(address(oeth), woethShares, receiver);
    }
}
