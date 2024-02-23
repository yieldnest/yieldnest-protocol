// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import "../interfaces/eigenlayer-init-mainnet/IStrategyManager.sol";
import "../interfaces/eigenlayer-init-mainnet/IEigenPodManager.sol";

contract MockStrategyManager {

    constructor () {}

    function depositIntoStrategy(
        IStrategy strategy, 
        IERC20 token, 
        uint256 amount
        ) external returns (uint256 shares) {

        // transfer tokens from the sender to the strategy
        token.transferFrom(msg.sender, address(strategy), amount);

        // deposit the assets into the specified strategy and get the equivalent amount of shares in that strategy
        shares = strategy.deposit(token, amount);

        // add the returned shares to the depositor's existing shares for this strategy
        // _addShares(depositor, strategy, shares);

        emit Deposit(msg.sender, token, strategy, shares);
        return shares;
    }

    event Deposit(
        address depositor, IERC20 token, IStrategy strategy, uint256 shares
    );

    function depositIntoStrategyWithSignature(
        IStrategy strategy,
        IERC20 token,
        uint256 amount,
        address staker,
        uint256 expiry,
        bytes memory signature
    ) external pure returns (uint256 shares) {
        revert("MockStrategyManager: depositIntoStrategyWithSignature not implemented");
    }

    // function removeShares(address staker, IStrategy strategy, uint256 shares) external pure override {
    //     revert("MockStrategyManager: removeShares not implemented");
    // }

    // function addShares(address staker, IStrategy strategy, uint256 shares) external pure override {
    //     revert("MockStrategyManager: addShares not implemented");
    // }

    // function withdrawSharesAsTokens(address recipient, IStrategy strategy, uint256 shares, IERC20 token) external pure override {
    //     revert("MockStrategyManager: withdrawSharesAsTokens not implemented");
    // }

    // function stakerStrategyShares(address user, IStrategy strategy) external pure override returns (uint256 shares) {
    //     return 0;
    // }

    // function getDeposits(address staker) external pure override returns (IStrategy[] memory, uint256[] memory) {
    //     revert("MockStrategyManager: getDeposits not implemented");
    // }

    // function stakerStrategyListLength(address staker) external pure override returns (uint256) {
    //     revert("MockStrategyManager: stakerStrategyListLength not implemented");
    // }

    // function addStrategiesToDepositWhitelist(IStrategy[] calldata strategiesToWhitelist) external pure override {
    //     revert("MockStrategyManager: addStrategiesToDepositWhitelist not implemented");
    // }

    // function removeStrategiesFromDepositWhitelist(IStrategy[] calldata strategiesToRemoveFromWhitelist) external pure override {
    //     revert("MockStrategyManager: removeStrategiesFromDepositWhitelist not implemented");
    // }

    // function delegation() external pure override returns (IDelegationManager) {
    //     revert("MockStrategyManager: delegation not implemented");
    // }

    // function slasher() external pure override returns (ISlasher) {
    //     revert("MockStrategyManager: slasher not implemented");
    // }

    // function eigenPodManager() external pure override returns (IEigenPodManager) {
    //     revert("MockStrategyManager: eigenPodManager not implemented");
    // }

    // function strategyWhitelister() external pure override returns (address) {
    //     revert("MockStrategyManager: strategyWhitelister not implemented");
    // }

}

