// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {Initializable} from "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {IStrategyManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IDelegationManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategy} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IEigenStrategyManager} from "src/interfaces/IEigenStrategyManager.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract EigenStrategyManager is 
        IEigenStrategyManager,
        Initializable,
        AccessControlUpgradeable
    {

    //--------------------------------------------------------------------------------------
    //----------------------------------  ERRORS  ------------------------------------------
    //--------------------------------------------------------------------------------------


    error ZeroAddress();

    //--------------------------------------------------------------------------------------
    //----------------------------------  ROLES  -------------------------------------------
    //--------------------------------------------------------------------------------------

    /// @notice  Role is allowed to set the pause state
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /// @notice Role allowed to unset the pause state
    bytes32 public constant UNPAUSER_ROLE = keccak256("UNPAUSER_ROLE");

    /// @notice Controls the strategy actions
    bytes32 public constant STRATEGY_ADMIN_ROLE = keccak256("STRATEGY_ADMIN_ROLE");

    //--------------------------------------------------------------------------------------
    //----------------------------------  VARIABLES  ---------------------------------------
    //--------------------------------------------------------------------------------------
    

    // Mapping of asset to its corresponding strategy
    mapping(IERC20 => IStrategy) public strategies;

    IStrategyManager public strategyManager;
    IDelegationManager public delegationManager;

    //--------------------------------------------------------------------------------------
    //----------------------------------  INITIALIZATION  ----------------------------------
    //--------------------------------------------------------------------------------------

    struct Init {
        IERC20[] assets;
        IStrategy[] strategies;
        IStrategyManager strategyManager;
        IDelegationManager delegationManager;
        address admin;
        address strategyAdmin;
        address unpauser;
        address pauser;
    }

    function initialize(Init calldata init)
        public
        notZeroAddress(address(init.strategyManager))
        notZeroAddress(address(init.admin))
        notZeroAddress(address(init.lsdRestakingManager))
        notZeroAddress(init.lsdStakingNodeCreatorRole)
        initializer {
        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, init.admin);
        _grantRole(PAUSER_ROLE, init.pauser);
        _grantRole(UNPAUSER_ROLE, init.unpauser);

        for (uint256 i = 0; i < init.assets.length; i++) {
            if (address(init.assets[i]) == address(0) || address(init.strategies[i]) == address(0)) {
                revert ZeroAddress();
            }
            strategies[init.assets[i]] = init.strategies[i];
        }

        strategyManager = init.strategyManager;
        delegationManager = init.delegationManager;
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
