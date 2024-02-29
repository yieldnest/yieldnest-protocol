// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

// Third-party imports: OZ
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title ReturnsReceiver
/// @notice @note TODO 
///         Receives protocol level returns and manages who can withdraw the returns. Deployed as the
///         consensus layer withdrawal wallet and execution layer rewards wallet in the protocol.
contract RewardsReceiver is 
    Initializable, 
    AccessControlUpgradeable {

    /******************************\
    |                              |
    |             Errors           |
    |                              |
    \******************************/

    error RewardsReceiver_InsufficientBalance();
    error RewardsReceiver_TransferEthFailed();

    /******************************\
    |                              |
    |           Constants          |
    |                              |
    \******************************/

    /// @notice Role can withdraw ETH and ERC20 tokens from this contract.
    bytes32 private constant WITHDRAWER_ROLE = keccak256("WITHDRAWER_ROLE");

    /******************************\
    |                              |
    |            Structs           |
    |                              |
    \******************************/

    /// @notice Configuration for contract initialization.
    /// @param admin The initial admin of this contract.
    /// @param withdrawer The initial withdrawer of this contract.
    struct Init {
        address admin;
        address withdrawer;
    }

    /******************************\
    |                              |
    |          Constructor         |
    |                              |
    \******************************/

    /// @notice The constructor.
    /// @dev calling _disableInitializers() to prevent the implementation from
    ///      being initialized.
    constructor() {
       _disableInitializers();
    }

    /// @notice Inititalizes the contract.
    /// @param init The init params.
    function initialize(Init calldata _init)
        external 
        notZeroAddress(init.admin)
        notZeroAddress(init.withdrawer)
        initializer 
    {
        // Initialize all the parent contracts.
        __AccessControl_init();

        // Assign all the roles.
        _grantRole(DEFAULT_ADMIN_ROLE, _init.admin);
        _grantRole(WITHDRAWER_ROLE, _init.withdrawer);
    }

    /******************************\
    |                              |
    |         Core functions       |
    |                              |
    \******************************/

    /// @notice Transfers the given amount of ETH to an address.
    /// @dev Only callable by an account with the WITHDRAWER_ROLE.
    /// @param to The recipient of the ETH.
    /// @param amount The amount of ETH to transfer.
    function transferETH(address payable _to, uint256 _amount) 
        external 
        onlyRole(WITHDRAWER_ROLE) 
    {
        if (address(this).balance < _amount) {
            revert RewardsReceiver_InsufficientBalance();
        }

        (bool success, ) = _to.call{value: _amount}("");

        if (!success) {
            revert RewardsReceiver_TransferEthFailed();
        }
    }

    /// @notice Transfers the given amount of an ERC20 token to an address.
    /// @dev Only callable by an account with the WITHDRAWER_ROLE.
    /// @param to The recipient of the ERC20 tokens.
    /// @param amount The amount of ERC20 tokens to transfer.
    function transferERC20(IERC20 _token, address _to, uint256 _amount)   
        external 
        onlyRole(WITHDRAWER_ROLE) 
    {
        SafeERC20.safeTransfer(_token, _to, _amount);
    }

    /******************************\
    |                              |
    |      Fallback functions      |
    |                              |
    \******************************/

    //@audit who calls this?
    /// @notice Receive ETH.
    receive() 
        external payable 
    {}


    /******************************\
    |                              |
    |           Modifiers          |
    |                              |
    \******************************/

    /// @notice Ensure that the given address is not the zero address.
    /// @param addr The address to check.
    modifier notZeroAddress(address _address) {
        if (_address == address(0)) {
            revert RewardsReceiver_ZeroAddress();
        }
        _;
    }
}