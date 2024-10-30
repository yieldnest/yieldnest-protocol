// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;


interface IWithdrawalQueueManager {

    struct WithdrawalRequest {
        uint256 amount;
        uint256 feeAtRequestTime;
        uint256 redemptionRateAtRequestTime;
        uint256 creationTimestamp;
        bool processed;
        bytes data;
    }

    struct Finalization {
        uint64 startIndex;
        uint64 endIndex;
        uint96 redemptionRate;
    }

    struct WithdrawalClaim {
        uint256 tokenId;
        uint256 finalizationId;
        address receiver;
    }

    function requestWithdrawal(uint256 amount) external returns (uint256);
    function requestWithdrawal(uint256 amount, bytes calldata data) external returns (uint256);
    function claimWithdrawal(WithdrawalClaim memory claim) external;
    function finalizeRequestsUpToIndex(uint256 _lastFinalizedIndex) external returns (uint256);
    function pendingRequestedRedemptionAmount() external view returns (uint256);
}
