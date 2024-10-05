// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IStakingNodesManager} from "./interfaces/IStakingNodesManager.sol";
import {IDelegationManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStakingNodesManager, IStakingNodesManager as WithdrawalAction} from "./interfaces/IStakingNodesManager.sol";

/**
 * @title WithdrawalsBundler
 * @notice This contract bundles the completion of queued withdrawals and processing of principal withdrawals
 * into a single transaction for gas efficiency.
 */
import {Initializable} from "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";

interface IWithdrawalsProcessorEvents {
    event WithdrawalsCompletedAndProcessed(
        IStakingNodesManager.WithdrawalAction withdrawalAction,
        uint256 withdrawalsCount
    );
}

contract WithdrawalsProcessor is Initializable, AccessControlUpgradeable, IWithdrawalsProcessorEvents {

    IStakingNodesManager public stakingNodesManager;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }
    bytes32 public constant WITHDRAWAL_MANAGER_ROLE = keccak256("WITHDRAWAL_MANAGER_ROLE");

    function initialize(address _stakingNodesManager, address _withdrawalManager) public initializer {
        require(_stakingNodesManager != address(0), "Invalid StakingNodesManager address");
        require(_withdrawalManager != address(0), "Invalid withdrawal manager address");
        stakingNodesManager = IStakingNodesManager(_stakingNodesManager);
        _grantRole(WITHDRAWAL_MANAGER_ROLE, _withdrawalManager);
    }

    /**
     * @notice Bundles the completion of queued withdrawals and processing of principal withdrawals for a single node
     * @param withdrawalAction The withdrawal action containing node ID and withdrawal amounts
     * @param withdrawals Array of withdrawals to complete
     * @param middlewareTimesIndexes Array of middleware times indexes for the withdrawals
     */
    function completeAndProcessWithdrawalsForNode(
        IStakingNodesManager.WithdrawalAction memory withdrawalAction,
        IDelegationManager.Withdrawal[] memory withdrawals,
        uint256[] memory middlewareTimesIndexes
    ) external onlyRole(WITHDRAWAL_MANAGER_ROLE) {
        // Complete queued withdrawals
        stakingNodesManager.nodes(withdrawalAction.nodeId).completeQueuedWithdrawals(withdrawals, middlewareTimesIndexes);
        
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
}
