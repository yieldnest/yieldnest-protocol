// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0;

import "../interfaces/eigenlayer/IDelayedWithdrawalRouter.sol";

contract MockDelayedWithdrawalRouter is IDelayedWithdrawalRouter {
    function createDelayedWithdrawal(address podOwner, address recipient) external payable override {
        revert("createDelayedWithdrawal not supported");
    }

    function claimDelayedWithdrawals(address recipient, uint256 maxNumberOfWithdrawalsToClaim) external pure override {
        revert("claimDelayedWithdrawals not supported");
    }

    function claimDelayedWithdrawals(uint256 maxNumberOfWithdrawalsToClaim) external pure override {
        revert("claimDelayedWithdrawals not supported");
    }

    function setWithdrawalDelayBlocks(uint256 newValue) external pure override {
        revert("setWithdrawalDelayBlocks not supported");
    }

    function userWithdrawals(address user) external pure override returns (UserDelayedWithdrawals memory) {
        revert("userWithdrawals not supported");
    }

    function getUserDelayedWithdrawals(address user) external pure override returns (DelayedWithdrawal[] memory) {
        revert("getUserDelayedWithdrawals not supported");
    }

    function getClaimableUserDelayedWithdrawals(address user) external pure override returns (DelayedWithdrawal[] memory) {
        revert("getClaimableUserDelayedWithdrawals not supported");
    }

    function userDelayedWithdrawalByIndex(address user, uint256 index) external pure override returns (DelayedWithdrawal memory) {
        revert("userDelayedWithdrawalByIndex not supported");
    }

    function userWithdrawalsLength(address user) external pure override returns (uint256) {
        revert("userWithdrawalsLength not supported");
    }

    function canClaimDelayedWithdrawal(address user, uint256 index) external pure override returns (bool) {
        revert("canClaimDelayedWithdrawal not supported");
    }

    function withdrawalDelayBlocks() external pure override returns (uint256) {
        revert("withdrawalDelayBlocks not supported");
    }
}
