// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;


struct WithdrawalRequest {
    uint64 blockNumber;
    address requester;
    uint128 id;
    uint128 ynETHLocked;
    uint128 ethRequested;
    uint128 cumulativeETHRequested;
    bool isFinalized;
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
