// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {ITokenStakingNode} from "./ITokenStakingNode.sol";

interface IWithdrawalsProcessor {

    struct QueuedWithdrawal {
        address node;
        address strategy;
        uint256 nonce;
        uint256 shares;
        uint256 tokenIdToFinalize;
        uint32 startBlock;
        bool completed;
        address delegatedTo;
    }

    struct IDs {
        uint256 queued;
        uint256 completed;
        uint256 processed;
    }

    /// @param _asset The asset to withdraw
    /// @param _nodes The list of nodes to withdraw from
    /// @param _shares The withdrawable share amounts to withdraw from each node
    /// @param _totalQueuedWithdrawals The current total queued withdrawals in unit account obtained from `getTotalQueuedWithdrawals()`
    /// @param _pendingWithdrawalRequestsIgnored The amount of pending withdrawal requests that were left out due to asset balance in the node.
    struct QueueWithdrawalsArgs {
        IERC20 asset;
        ITokenStakingNode[] nodes;
        uint256[] shares;
        uint256 totalQueuedWithdrawals;
        uint256 pendingWithdrawalRequestsIgnored;
    }

    //
    // state variables
    //
    function totalQueuedWithdrawals() external view returns (uint256);
    function getTotalQueuedWithdrawals() external view returns (uint256);
    function minPendingWithdrawalRequestAmount() external view returns (uint256);
    function batch(
        uint256 _fromId
    ) external view returns (uint256 _toId);

    //
    // view functions
    //
    function ids() external view returns (IDs memory);
    function queuedWithdrawals(
        uint256 _id
    ) external view returns (QueuedWithdrawal memory);
    function shouldQueueWithdrawals() external view returns (bool);
    function shouldCompleteQueuedWithdrawals() external view returns (bool);
    function shouldProcessPrincipalWithdrawals() external returns (bool);
    function getPendingWithdrawalRequests() external view returns (uint256 _pendingWithdrawalRequests);
    function getQueueWithdrawalsArgs() external view returns (QueueWithdrawalsArgs memory _args);

    //
    // mutative functions
    //
    function queueWithdrawals(QueueWithdrawalsArgs memory _args) external returns (bool);
    function completeQueuedWithdrawals() external;
    function processPrincipalWithdrawals() external;

    //
    // management functions
    //
    function updateMinPendingWithdrawalRequestAmount(
        uint256 _minPendingWithdrawalRequestAmount
    ) external;

    //
    // Errors
    //
    error InvalidInput();
    error PendingWithdrawalRequestsTooLow();
    error NoQueuedWithdrawals();
    error NothingToProcess();
    error SanityCheck();
    error CurrentAvailableAmountIsSufficient();
    error InvalidBuffer();
    error BufferNotSet();

    //
    // Events
    //
    event MinPendingWithdrawalRequestAmountUpdated(uint256 minPendingWithdrawalRequestAmount);
    event BufferSet(uint256 buffer);
}
