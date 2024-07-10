// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {IynEigen} from "src/interfaces/IynEigen.sol";
import {IwstETH} from "src/external/lido/IWstETH.sol";

import {AccessControlUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {Initializable} from "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";

contract ynEigenDepositAdapter is Initializable, AccessControlUpgradeable {

    //--------------------------------------------------------------------------------------
    //----------------------------------  ERRORS  -------------------------------------------
    //--------------------------------------------------------------------------------------

    error ZeroAddress();

    //--------------------------------------------------------------------------------------
    //----------------------------------  VARIABLES  ---------------------------------------
    //--------------------------------------------------------------------------------------

    IynEigen public ynEigen;
    IwstETH public wstETH;
    IERC4626 public woETH;

    //--------------------------------------------------------------------------------------
    //----------------------------------  INITIALIZATION  ----------------------------------
    //--------------------------------------------------------------------------------------

    struct Init {
        address ynEigen;
        address wstETH;
        address woETH;
        address admin;
    }

    function initialize(Init memory init) 
        public 
        initializer 
        notZeroAddress(init.ynEigen) 
        notZeroAddress(init.wstETH) 
        notZeroAddress(init.woETH) 
        notZeroAddress(init.admin)
    {
        ynEigen = IynEigen(init.ynEigen);
        wstETH = IwstETH(init.wstETH);
        woETH = IERC4626(init.woETH);
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, init.admin);
    }

    function depositStETH(uint256 amount, address receiver) external {
        IERC20 stETH = IERC20(wstETH.stETH());
        stETH.transferFrom(msg.sender, address(this), amount);
        stETH.approve(address(wstETH), amount);
        uint256 wstETHAmount = wstETH.wrap(amount);
        wstETH.approve(address(ynEigen), wstETHAmount);
        ynEigen.deposit(IERC20(address(wstETH)), wstETHAmount, receiver);
    }

    function depositOETH(uint256 amount, address receiver) external {
        IERC20 oeth = IERC20(woETH.asset());
        oeth.transferFrom(msg.sender, address(this), amount);
        oeth.approve(address(woETH), amount);
        uint256 woETHShares = woETH.deposit(amount, address(this));
        woETH.approve(address(ynEigen), woETHShares);
        ynEigen.deposit(IERC20(address(oeth)), woETHShares, receiver);
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  MODIFIERS  ---------------------------------------
    //--------------------------------------------------------------------------------------

    /// @notice Ensure that the given address is not the zero address.
    /// @param _address The address to check.
    modifier notZeroAddress(address _address) {
        if (_address == address(0)) {
            revert ZeroAddress();
        }
        _;
    }
}
