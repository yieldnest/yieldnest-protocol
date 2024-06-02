// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;


interface IWithdrawalQueueManager {
    function requestWithdrawal(uint256 amount) external;
    function claimWithdrawal(uint256 tokenId) external;
    function setSecondsToFinalization(uint256 _secondsToFinalization) external;
}
