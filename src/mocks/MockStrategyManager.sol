// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import "../interfaces/eigenlayer/IStrategy.sol";
import "../interfaces/eigenlayer/ISlasher.sol";
import "../interfaces/eigenlayer/IDelegationManager.sol";
import "../interfaces/eigenlayer/IEigenPodManager.sol";

contract MockStrategyManager is IStrategyManager {

    function depositIntoStrategy(IStrategy strategy, IERC20 token, uint256 amount) external pure override returns (uint256 shares) {
        revert("MockStrategyManager: depositIntoStrategy not implemented");
    }

    function depositIntoStrategyWithSignature(
        IStrategy strategy,
        IERC20 token,
        uint256 amount,
        address staker,
        uint256 expiry,
        bytes memory signature
    ) external pure override returns (uint256 shares) {
        revert("MockStrategyManager: depositIntoStrategyWithSignature not implemented");
    }

    function removeShares(address staker, IStrategy strategy, uint256 shares) external pure override {
        revert("MockStrategyManager: removeShares not implemented");
    }

    function addShares(address staker, IStrategy strategy, uint256 shares) external pure override {
        revert("MockStrategyManager: addShares not implemented");
    }

    function withdrawSharesAsTokens(address recipient, IStrategy strategy, uint256 shares, IERC20 token) external pure override {
        revert("MockStrategyManager: withdrawSharesAsTokens not implemented");
    }

    function stakerStrategyShares(address user, IStrategy strategy) external pure override returns (uint256 shares) {
        return 0;
    }

    function getDeposits(address staker) external pure override returns (IStrategy[] memory, uint256[] memory) {
        revert("MockStrategyManager: getDeposits not implemented");
    }

    function stakerStrategyListLength(address staker) external pure override returns (uint256) {
        revert("MockStrategyManager: stakerStrategyListLength not implemented");
    }

    function addStrategiesToDepositWhitelist(IStrategy[] calldata strategiesToWhitelist) external pure override {
        revert("MockStrategyManager: addStrategiesToDepositWhitelist not implemented");
    }

    function removeStrategiesFromDepositWhitelist(IStrategy[] calldata strategiesToRemoveFromWhitelist) external pure override {
        revert("MockStrategyManager: removeStrategiesFromDepositWhitelist not implemented");
    }

    function delegation() external pure override returns (IDelegationManager) {
        revert("MockStrategyManager: delegation not implemented");
    }

    function slasher() external pure override returns (ISlasher) {
        revert("MockStrategyManager: slasher not implemented");
    }

    function eigenPodManager() external pure override returns (IEigenPodManager) {
        revert("MockStrategyManager: eigenPodManager not implemented");
    }

    function strategyWhitelister() external pure override returns (address) {
        revert("MockStrategyManager: strategyWhitelister not implemented");
    }

    function migrateQueuedWithdrawal(DeprecatedStruct_QueuedWithdrawal memory queuedWithdrawal) external pure override returns (bool, bytes32) {
        revert("MockStrategyManager: migrateQueuedWithdrawal not implemented");
    }

    function calculateWithdrawalRoot(DeprecatedStruct_QueuedWithdrawal memory queuedWithdrawal) external pure override returns (bytes32) {
        revert("MockStrategyManager: calculateWithdrawalRoot not implemented");
    }
}

