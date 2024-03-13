
### Usage Scenario Tests

These tests are designed to verify the correct behavior of the ynETH contract in various usage scenarios.

**Scenario 1:** Successful ETH Deposit and Share Minting
Objective: Test that a user can deposit ETH and receive the correct amount of shares in return

**Scenario 2:** Deposit Paused
Objective: Ensure that deposits are correctly paused and resumed, preventing or allowing ETH deposits accordingly.

**Scenario 3:** Withdraw ETH to Staking Nodes Manager
Objective: Test that only the Staking Nodes Manager can withdraw ETH from the contract.

**Scenario 4:** Share Accouting and Yield Accrual
Objective: Verify that the share price correctly increases after the contract earns yield.

**Scenario 5:** Emergency Withdrawal of ETH
Objective: Ensure that users can withdraw their ETH in case of an emergency, bypassing the normal withdrawal restrictions.

**Scenario 6:** Validator and Staking Node Administration
Objective: Test the ynETH's ability to update the address of the Staking Nodes Manager.

**Scenario 7:** Accrual and Distribution of Fees
Objective: Ensure that ynETH correctly accrues and distributes fees from yield earnings or other sources.

**Scenario 8:** Staking Rewards Distribution
Objective: Test the distribution of staking rewards to share holders.

**Scenario 9:** EigenLayer Accounting and Distribution
Objective: Verify that ynETH correctly accounts for and withdrawals from EigenLayer.


### Invariant Scenarios

The following invariant scenarios are designed to verify the correct behavior of the ynETH contract in various usage scenarios. These scenarios should never fail, and if they do, it indicates there is an implementation issue somewhere in the protocol.

**Total Assets Consistency**

```solidity
assert(totalDepositedInPool + totalDepositedInValidators() == totalAssets());
```

**Exchange Rate Integrity**

```solidity
assert(exchangeAdjustmentRate >= 0 && exchangeAdjustmentRate <= BASIS_POINTS_DENOMINATOR);
```
**Share Minting Consistency**
```solidity
assert(totalSupply() == previousTotalSupply + mintedShares)
```

**Deposit and Withdrawal Symmetry**

```solidity
uint256 sharesMinted = depositETH(amount);
assert(sharesMinted == previewDeposit(amount));
```

**Rewards Increase Total Assets**

```solidity
uint256 previousTotalAssets = totalAssets();
// Simulate receiving rewards
receiveRewards{value: rewardAmount}();
assert(totalAssets() == previousTotalAssets + rewardAmount);
```

**Authorized Access Control**

```solidity
// For any role-restricted operation
assert(msg.sender == authorizedRoleAddress);
```