// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {IynEigen} from "src/interfaces/IynEigen.sol";
import {IwstETH} from "src/external/lido/IwstETH.sol";
import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import {AccessControlUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {Initializable} from "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";

import {IWrapper} from "src/interfaces/IWrapper.sol";

interface IynEigenDepositAdapterEvents {
    event ReferralDepositProcessed(
        address sender, 
        address indexed receiver, 
        address indexed asset, 
        uint256 amount, 
        uint256 shares, 
        address indexed referrer, 
        uint256 timestamp
    );

    event DepositWrappedAsset(
        address indexed sender,
        address indexed receiver,
        address indexed asset,
        uint256 amount,
        uint256 wrappedAmount,
        uint256 shares
    );
}


contract ynEigenDepositAdapter is IynEigenDepositAdapterEvents, Initializable, AccessControlUpgradeable {

    using SafeERC20 for IERC20;
    using SafeERC20 for IwstETH;
    using SafeERC20 for IERC4626;

    //--------------------------------------------------------------------------------------
    //----------------------------------  ERRORS  -------------------------------------------
    //--------------------------------------------------------------------------------------

    error ZeroAddress();
    error SelfReferral();

    //--------------------------------------------------------------------------------------
    //----------------------------------  VARIABLES  ---------------------------------------
    //--------------------------------------------------------------------------------------

    IynEigen public ynEigen;
    IwstETH public wstETH;
    IERC4626 public woETH;
    IERC20 public stETH;
    IERC20 public oETH;
    IWrapper public wrapper;

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
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, init.admin);
        ynEigen = IynEigen(init.ynEigen);
        wstETH = IwstETH(init.wstETH);
        woETH = IERC4626(init.woETH);

        stETH = IERC20(wstETH.stETH());
        oETH = IERC20(woETH.asset());
    }

    function initializeV2(address _wrapper) external reinitializer(2) notZeroAddress(_wrapper) {
        wrapper = IWrapper(_wrapper);
    }

    /**
     * @notice Handles the deposit of assets into the ynEigen system.
               It supports all assets supported by ynEigen
            + oETH and and stETH which are wrapped prior to deposit.
     * @dev This function routes the deposit based on the type of asset provided. 
     * @param asset The asset to be deposited.
     * @param amount The amount of the asset to be deposited.
     * @param receiver The address that will receive the ynEigen tokens.
     * @return The number of ynEigen tokens received by the receiver.
     */
    function deposit(IERC20 asset, uint256 amount, address receiver) public returns (uint256) {
        if (address(asset) == address(stETH)) {
            return depositStETH(amount, receiver);
        } else if (address(asset) == address(oETH)) {
            return depositOETH(amount, receiver);
        } else {
            asset.safeTransferFrom(msg.sender, address(this), amount);
            asset.forceApprove(address(ynEigen), amount);
            return ynEigen.deposit(asset, amount, receiver);
        }
    }


    /// @notice Simulates the deposit of assets into the ynEigen system and returns the expected number of shares.
    /// @dev This function handles the conversion for oETH and stETH before simulating the deposit since
    ///      they are not natively supported by ynEigen.
    /// @param asset The asset to be deposited.
    /// @param amount The amount of the asset to be deposited.
    /// @return shares The expected number of ynEigen tokens (shares) to be received.
    function previewDeposit(IERC20 asset, uint256 amount) external view returns (uint256 shares) {
        if (address(asset) == address(oETH)) {
            // Convert oETH to woETH
            uint256 woETHAmount = IERC4626(woETH).convertToShares(amount);
            return ynEigen.previewDeposit(IERC20(woETH), woETHAmount);
        } else if (address(asset) == address(stETH)) {
            // Convert stETH to wstETH
            uint256 wstETHAmount = IwstETH(wstETH).getWstETHByStETH(amount);
            return ynEigen.previewDeposit(IERC20(wstETH), wstETHAmount);
        } else {
            // For all other assets, use the standard previewDeposit function
            return ynEigen.previewDeposit(IERC20(asset), amount);
        }
    }

    /**
     * @notice Deposits an asset with referral information.
     *          IMPORTANT: The referred or referree is the receiver, NOT msg.sender
     * @dev This function extends the basic deposit functionality with referral tracking.
     * @param asset The ERC20 asset to be deposited.
     * @param amount The amount of the asset to be deposited.
     * @param receiver The address that will receive the ynEigen tokens.
     * @param referrer The address of the referrer.
     * @return shares The number of ynEigen tokens received by the receiver.
     */
    function depositWithReferral(
        IERC20 asset,
        uint256 amount,
        address receiver,
        address referrer
    ) external returns (uint256 shares) {
        if (receiver == address(0)) {
            revert ZeroAddress();
        }
        if (referrer == address(0)) {
            revert ZeroAddress();
        }
        if (referrer == receiver) {
            revert SelfReferral();
        }
        shares = deposit(asset, amount, receiver);
        emit ReferralDepositProcessed(msg.sender, receiver, address(asset), amount, shares, referrer, block.timestamp);
    }

    function depositStETH(uint256 amount, address receiver) internal returns (uint256 shares) {
        stETH.safeTransferFrom(msg.sender, address(this), amount);
        stETH.forceApprove(address(wrapper), amount);
        (uint256 wstETHAmount,) = wrapper.wrap(amount, stETH);
        wstETH.forceApprove(address(ynEigen), wstETHAmount);

        shares = ynEigen.deposit(IERC20(address(wstETH)), wstETHAmount, receiver);

        emit DepositWrappedAsset(msg.sender, receiver, address(stETH), amount, wstETHAmount, shares);
    }

    function depositOETH(uint256 amount, address receiver) internal returns (uint256 shares) {
        oETH.safeTransferFrom(msg.sender, address(this), amount);
        oETH.forceApprove(address(wrapper), amount);
        (uint256 woETHShares,) = wrapper.wrap(amount, oETH);
        woETH.forceApprove(address(ynEigen), woETHShares);

        shares = ynEigen.deposit(IERC20(address(woETH)), woETHShares, receiver);

        emit DepositWrappedAsset(msg.sender, receiver, address(oETH), amount, woETHShares, shares);
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  MODIFIERS  ---------------------------------------
    //--------------------------------------------------------------------------------------

    /**
     * @notice Ensure that the given address is not the zero address.
     * @param _address The address to check.
     */
    modifier notZeroAddress(address _address) {
        if (_address == address(0)) {
            revert ZeroAddress();
        }
        _;
    }
}
