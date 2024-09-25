// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {Initializable} from "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {IERC20, SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import {IwstETH} from "src/external/lido/IwstETH.sol";
import {IWrapper} from "src/interfaces/IWrapper.sol";

contract LSDWrapper is IWrapper, Initializable {

    using SafeERC20 for IERC20;

    IERC20 public immutable wstETH;
    IERC20 public immutable woETH;
    IERC20 public immutable oETH;
    IERC20 public immutable stETH;

    // ============================================================================================
    // Constructor
    // ============================================================================================

    constructor(address _wstETH, address _woETH, address _oETH, address _stETH) {
        if (_wstETH == address(0) || _woETH == address(0) || _oETH == address(0) || _stETH == address(0)) {
            revert ZeroAddress();
        }

        wstETH = IERC20(_wstETH);
        woETH = IERC20(_woETH);
        oETH = IERC20(_oETH);
        stETH = IERC20(_stETH);
    }

    function initialize() external initializer {
        stETH.forceApprove(address(wstETH), type(uint256).max);
        oETH.forceApprove(address(woETH), type(uint256).max);
    }

    // ============================================================================================
    // External functions
    // ============================================================================================

    /// @inheritdoc IWrapper
    function wrap(uint256 _amount, IERC20 _token) external returns (uint256, IERC20) {
        if (_token == stETH) {
            stETH.safeTransferFrom(msg.sender, address(this), _amount);
            _amount = IwstETH(address(wstETH)).wrap(_amount);
            wstETH.safeTransfer(msg.sender, _amount);
            return (_amount, wstETH);
        } else if (_token == oETH) {
            oETH.safeTransferFrom(msg.sender, address(this), _amount);
            return (IERC4626(address(woETH)).deposit(_amount, msg.sender), woETH);
        } else {
            return (_amount, _token);
        }
    }

    /// @inheritdoc IWrapper
    function unwrap(uint256 _amount, IERC20 _token) external returns (uint256, IERC20) {
        if (_token == wstETH) {
            wstETH.safeTransferFrom(msg.sender, address(this), _amount);
            _amount = IwstETH(address(wstETH)).unwrap(_amount);
            stETH.safeTransfer(msg.sender, _amount);
            return (_amount, stETH);
        } else if (_token == woETH) {
            return (IERC4626(address(woETH)).redeem(_amount, msg.sender, msg.sender), oETH);
        } else {
            return (_amount, _token);
        }
    }

    /// @notice Unwraps wstETH to stETH and redeems woETH to oETH without transferring tokens
    /// @param _amount The amount of tokens to unwrap/redeem
    /// @param _token The token to unwrap/redeem (wstETH or woETH)
    /// @return The amount of unwrapped/redeemed tokens and the resulting token
    function unwrapWithoutTransfer(uint256 _amount, IERC20 _token) external returns (uint256, IERC20) {
        if (_token == wstETH) {
            uint256 unwrappedAmount = IwstETH(address(wstETH)).unwrap(_amount);
            return (unwrappedAmount, stETH);
        } else if (_token == woETH) {
            uint256 redeemedAmount = IERC4626(address(woETH)).redeem(_amount, address(this), address(this));
            return (redeemedAmount, oETH);
        } else {
            return (_amount, _token);
        }
    }

    /// @notice Wraps stETH to wstETH and deposits oETH to woETH without transferring tokens
    /// @param _amount The amount of tokens to wrap/deposit
    /// @param _token The token to wrap/deposit (stETH or oETH)
    /// @return The amount of wrapped/deposited tokens and the resulting token
    function wrapWithoutTransfer(uint256 _amount, IERC20 _token) external returns (uint256, IERC20) {
        if (_token == stETH) {
            stETH.approve(address(wstETH), _amount);
            uint256 wrappedAmount = IwstETH(address(wstETH)).wrap(_amount);
            return (wrappedAmount, wstETH);
        } else if (_token == oETH) {
        
            uint256 depositedAmount = IERC4626(address(woETH)).deposit(_amount, address(this));
            return (depositedAmount, woETH);
        } else {
            return (_amount, _token);
        }
    }

    // ============================================================================================
    // Errors
    // ============================================================================================

    error ZeroAddress();
}