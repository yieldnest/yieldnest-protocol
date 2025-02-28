// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IStakingNodesManager} from "./interfaces/IStakingNodesManager.sol";
import {IDelegationManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStakingNodesManager} from "./interfaces/IStakingNodesManager.sol";
import {Initializable} from "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";

interface IWithdrawalsProcessorEvents {
    event WithdrawalsCompletedAndProcessed(
        IStakingNodesManager.WithdrawalAction withdrawalAction,
        uint256 withdrawalsCount
    );
}

contract WithdrawalsProcessor is Initializable, AccessControlUpgradeable, IWithdrawalsProcessorEvents {

    //--------------------------------------------------------------------------------------
    //----------------------------------  ERRORS  ------------------------------------------
    //--------------------------------------------------------------------------------------

    error ZeroAddress();

    //--------------------------------------------------------------------------------------
    //----------------------------------  ROLES  -------------------------------------------
    //--------------------------------------------------------------------------------------

    bytes32 public constant WITHDRAWAL_MANAGER_ROLE = keccak256("WITHDRAWAL_MANAGER_ROLE");

    //--------------------------------------------------------------------------------------
    //----------------------------------  VARIABLES  ---------------------------------------
    //--------------------------------------------------------------------------------------

    IStakingNodesManager public stakingNodesManager;

    //--------------------------------------------------------------------------------------
    //----------------------------------  INITIALIZATION  ----------------------------------
    //--------------------------------------------------------------------------------------


    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        IStakingNodesManager _stakingNodesManager,
        address _admin,
        address _withdrawalManager
    ) public initializer 
      notZeroAddress(address(_stakingNodesManager)) 
      notZeroAddress(_withdrawalManager) 
    {
        __AccessControl_init();
        
        stakingNodesManager = _stakingNodesManager;
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(WITHDRAWAL_MANAGER_ROLE, _withdrawalManager);
    }

    /**
     * @notice Bundles the completion of queued withdrawals and processing of principal withdrawals for a single node
     * @param withdrawalAction The withdrawal action containing node ID and withdrawal amounts
     * @param withdrawals Array of withdrawals to complete
     */
    function completeAndProcessWithdrawalsForNode(
        IStakingNodesManager.WithdrawalAction memory withdrawalAction,
        IDelegationManager.Withdrawal[] memory withdrawals
    ) external onlyRole(WITHDRAWAL_MANAGER_ROLE) {
        // Complete queued withdrawals
        stakingNodesManager.nodes(withdrawalAction.nodeId).completeQueuedWithdrawals(withdrawals);
        
        // Process principal withdrawal
        IStakingNodesManager.WithdrawalAction[] memory actions = new IStakingNodesManager.WithdrawalAction[](1);
        actions[0] = withdrawalAction;
        stakingNodesManager.processPrincipalWithdrawals(actions);

        // Emit an event for the completed and processed withdrawals
        emit WithdrawalsCompletedAndProcessed(
            withdrawalAction,
            withdrawals.length
        );
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
