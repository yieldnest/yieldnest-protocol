// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

struct WithdrawalRequest {
    uint64 blockNumber;
    address requester;
    uint128 id;
    uint128 ynETHLocked;
    uint128 ethRequested;
    uint128 cumulativeETHRequested;
    bool isFinalized;
}

/// @notice Events emitted by the withdrawal request queue.
interface IWithdrawalRequestQueueEvents {
    /// @notice Created emitted when a withdrawal request has been created.
    /// @param id The id of the withdrawal request.
    /// @param requester The address of the user who requested to withdraw.
    /// @param ynETHLocked The amount of ynETH that will be burned when the request is claimed.
    /// @param ethRequested The amount of ETH that will be returned to the requester.
    /// @param cumulativeETHRequested The cumulative amount of ETH requested at the time of the withdrawal request.
    /// @param blockNumber The block number at the point at which the request was created.
    event WithdrawalRequestCreated(
        uint256 indexed id,
        address indexed requester,
        uint256 ynETHLocked,
        uint256 ethRequested,
        uint256 cumulativeETHRequested,
        uint256 blockNumber
    );

    /// @notice Claimed emitted when a withdrawal request has been claimed.
    /// @param id The id of the withdrawal request.
    /// @param requester The address of the user who requested to withdraw.
    /// @param ynETHLocked The amount of ynETH that will be burned when the request is claimed.
    /// @param ethRequested The amount of ETH that will be returned to the requester.
    /// @param cumulativeETHRequested The cumulative amount of ETH requested at the time of the withdrawal request.
    /// @param blockNumber The block number at the point at which the request was created.
    event WithdrawalRequestClaimed(
        uint256 indexed id,
        address indexed requester,
        uint256 ynETHLocked,
        uint256 ethRequested,
        uint256 cumulativeETHRequested,
        uint256 blockNumber
    );
}

interface IWithdrawalRequestQueue {
    /// @notice Creates a new unstake request and adds it to the unstake requests array.
    /// @param requester The address of the entity making the unstake request.
    /// @param ynETHLocked The amount of ynETH tokens currently locked in the contract.
    /// @param ethRequested The amount of ETH being requested for unstake.
    /// @return The ID of the new unstake request.
    function create(address requester, uint128 ynETHLocked, uint128 ethRequested) external returns (uint256);

    /// @notice Allows the requester to claim their unstake request after it has been finalized.
    /// @param requestID The ID of the unstake request to claim.
    /// @param requester The address of the entity claiming the unstake request.
    function claim(uint256 requestID, address requester) external;


    /// @notice Allocate ether into the contract.
    function allocateETH() external payable;

    /// @notice Retrieves a specific unstake request based on its ID.
    /// @param requestID The ID of the unstake request to fetch.
    /// @return The UnstakeRequest struct corresponding to the given ID.
    function requestByID(uint256 requestID) external view returns (WithdrawalRequest memory);
}
