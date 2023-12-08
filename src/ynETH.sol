// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from
    "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {
    ERC20PermitUpgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";

import {IynETH} from "./interfaces/IynETH.sol";
import {IDepositPool} from "./interfaces/IDepositPool.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

/// @title ynETH
/// @notice ynETH is the ERC20 LSD token for the protocol.
contract ynETH is Initializable, AccessControlUpgradeable, ERC20PermitUpgradeable, IynETH {
    // Errors.
    error NotDepositPoolContract();

    /// @notice The deposit pool contract which has permissions to mint and burn tokens.
    IDepositPool public depositPoolContract;

    /// @notice Configuration for contract initialization.
    struct Init {
        address admin;
        IDepositPool depositPool;
    }

    constructor() {
        // TODO: re-enable tihs
        // _disableInitializers();
    }

    /// @notice Inititalizes the contract.
    /// @dev MUST be called during the contract upgrade to set up the proxies state.
    function initialize(Init memory init) external initializer {
        __AccessControl_init();
        __ERC20_init("ynETH", "ynETH");
        __ERC20Permit_init("ynETH");

        _grantRole(DEFAULT_ADMIN_ROLE, init.admin);
        depositPoolContract = init.depositPool;
    }

    /// @inheritdoc IynETH
    /// @dev Expected to be called during the deposit operation.
    function mint(address depositor, uint256 amount) external {
        if (msg.sender != address(depositPoolContract)) {
            revert NotDepositPoolContract();
        }

        _mint(depositor, amount);
    }

    /// @inheritdoc IynETH
    /// @dev Expected to be called when a user has claimed their unstake request.
    function burn(uint256 amount) external {
        if (msg.sender != address(depositPoolContract)) {
            revert NotDepositPoolContract();
        }

        _burn(msg.sender, amount);
    }

    /// @dev See {IERC20Permit-nonces}.
    function nonces(address owner)
        public
        view
        virtual
        override(ERC20PermitUpgradeable, IERC20Permit)
        returns (uint256)
    {
        return ERC20PermitUpgradeable.nonces(owner);
    }
}
