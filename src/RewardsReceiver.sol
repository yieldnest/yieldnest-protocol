// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";


/// @title ReturnsReceiver
/// @notice Receives protocol level returns and manages who can withdraw the returns. Deployed as the
/// consensus layer withdrawal wallet and execution layer rewards wallet in the protocol.
contract RewardsReceiver is Initializable, AccessControlUpgradeable {
    /// @notice The withdrawer role can withdraw ETH and ERC20 tokens from this contract.
    bytes32 public constant WITHDRAWER_ROLE = keccak256("WITHDRAWER_ROLE");

    /// @notice Configuration for contract initialization.
    struct Init {
        address admin;
        address manager;
        address withdrawer;
    }

    constructor() {
       // _disableInitializers();
    }

    /// @notice Inititalizes the contract.
    /// @dev MUST be called during the contract upgrade to set up the proxies state.
    function initialize(Init memory init) external initializer {
        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, init.admin);
        _setRoleAdmin(WITHDRAWER_ROLE, DEFAULT_ADMIN_ROLE);
        _grantRole(WITHDRAWER_ROLE, init.withdrawer);
    }

    /// @notice Transfers the given amount of ETH to an address.
    /// @dev Only called by the withdrawer.
    function transfer(address payable to, uint256 amount) external onlyRole(WITHDRAWER_ROLE) {
        require(address(this).balance >= amount, "Insufficient balance");
        (bool success, ) = to.call{value: amount}("");
        require(success, "Transfer failed");
    }

    /// @notice Transfers the given amount of an ERC20 token to an address.
    /// @dev Only called by the withdrawer.
    function transferERC20(IERC20 token, address to, uint256 amount) external onlyRole(WITHDRAWER_ROLE) {
        SafeERC20.safeTransfer(token, to, amount);
    }

    receive() external payable {}
}