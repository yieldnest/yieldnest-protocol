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

    //
    // state variables
    //
    function totalQueuedWithdrawals() external view returns (uint256);
    function minPendingWithdrawalRequestAmount() external view returns (uint256);
    function batch(
        uint256 _fromId
    ) external view returns (uint256 _toId);
    function bufferFactor() external view returns (uint256);

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
    function getQueueWithdrawalsArgs()
        external
        view
        returns (IERC20 _asset, ITokenStakingNode[] memory _nodes, uint256[] memory _shares);

    //
    // mutative functions
    //
    function queueWithdrawals(
        IERC20 _asset,
        ITokenStakingNode[] memory _nodes,
        uint256[] memory _amounts
    ) external returns (bool);
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

    //
    // Events
    //
    event MinPendingWithdrawalRequestAmountUpdated(uint256 minPendingWithdrawalRequestAmount);
    event BufferFactorUpdated(uint256 bufferFactor);
}
