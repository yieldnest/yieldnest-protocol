// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;


interface IWithdrawalQueueManager {

    struct WithdrawalRequest {
        uint256 amount;
        uint256 feeAtRequestTime;
        uint256 redemptionRateAtRequestTime;
        uint256 creationTimestamp;
        uint256 creationBlock;
        bool processed;
    }

    function requestWithdrawal(uint256 amount) external;
    function claimWithdrawal(uint256 tokenId, address receiver) external;
    function setSecondsToFinalization(uint256 _secondsToFinalization) external;
}
