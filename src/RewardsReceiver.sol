// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";


interface IRewardsReceiverEvents {
    event AssetWithdrawn(address indexed asset, address indexed to, uint256 amount);
    event EthWithdrawn(address indexed to, uint256 amount);
}

/// @title ReturnsReceiver
/// @notice Receives protocol level returns and manages who can withdraw the returns. Deployed as the
/// consensus layer withdrawal wallet and execution layer rewards wallet in the protocol.
contract RewardsReceiver is Initializable, AccessControlUpgradeable, IRewardsReceiverEvents {

    //--------------------------------------------------------------------------------------
    //----------------------------------  ERRORS  ------------------------------------------
    //--------------------------------------------------------------------------------------
    
    error ZeroAddress();
    error InsufficientBalance();
    error TransferFailed();

    //--------------------------------------------------------------------------------------
    //----------------------------------  ROLES  -------------------------------------------
    //--------------------------------------------------------------------------------------

    /// @notice The withdrawer role can withdraw ETH and ERC20 assets from this contract.
    bytes32 public constant WITHDRAWER_ROLE = keccak256("WITHDRAWER_ROLE");

    //--------------------------------------------------------------------------------------
    //----------------------------------  INITIALIZATION  ----------------------------------
    //--------------------------------------------------------------------------------------

    constructor() {
        _disableInitializers();
    }

    /// @notice Configuration for contract initialization.
    struct Init {
        address admin;
        address withdrawer;
    }

    /// @notice Inititalizes the contract.
    function initialize(Init memory init)
        external
        notZeroAddress(init.admin)
        notZeroAddress(init.withdrawer)
        initializer {
        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, init.admin);
        _setRoleAdmin(WITHDRAWER_ROLE, DEFAULT_ADMIN_ROLE);
        _grantRole(WITHDRAWER_ROLE, init.withdrawer);
    }

    receive() external payable {}

    //--------------------------------------------------------------------------------------
    //----------------------------------  TRANSFERS  ---------------------------------------
    //--------------------------------------------------------------------------------------

    /// @notice Transfers the given amount of ETH to an address.
    /// @dev Only called by the withdrawer.
    function transferETH(address payable to, uint256 amount) external onlyRole(WITHDRAWER_ROLE) {
        if (address(this).balance < amount) {
            revert InsufficientBalance();
        }
        (bool success, ) = to.call{value: amount}("");
        if (!success) {
            revert TransferFailed();
        }

        emit EthWithdrawn(to, amount);
    }

    /// @notice Transfers the given amount of an ERC20 asset to an address.
    /// @dev Only called by the withdrawer.
    function transferERC20(IERC20 asset, address to, uint256 amount) external onlyRole(WITHDRAWER_ROLE) {
        SafeERC20.safeTransfer(asset, to, amount);
        emit AssetWithdrawn(address(asset), to, amount);
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