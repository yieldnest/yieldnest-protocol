
## Usage Scenario Tests

These tests are designed to verify the correct behavior of the ynETH contract in various usage scenarios.

**Scenario 1:** Successful ETH Deposit and Share Minting

Objective: Test that a user can deposit ETH and receive the correct amount of shares in return.

**Scenario 2:** Deposit Paused

Objective: Ensure that deposits are correctly paused and resumed, preventing or allowing ETH deposits accordingly.

**Scenario 3:** Deposit and Withdraw ETH to Staking Nodes Manager

Objective: Test the end-to-end flow of depositing ETH to an eigenpod, and withdrawing ETH to the staking nodes manager.

**Scenario 4:** Share Accounting and Yield Accrual

Objective: Verify that the share price correctly increases after the contract earns yield from consensus and execution rewards.

**Scenario 5:** Emergency Withdrawal of ETH

Objective: Test ability to withdraw all assets from eigenpods.

**Scenario 6:** Validator and Staking Node Administration

Objective: Test the ynETH's ability to update the address of the Staking Nodes Manager.

**Scenario 7:** Accrual and Distribution of Fees

Objective: Ensure that ynETH correctly accrues and distributes fees from yield earnings from execution and consensus rewards.

**Scenario 8:** Staking Rewards Distribution

Objective: Test the distribution of staking rewards to a multisig.

**Scenario 9:** EigenLayer Accounting and Distribution

Objective: Verify that ynETH correctly accounts for fund balances and withdrawals from EigenLayer.

**Scenario 10:** Self-Destruct Attack

Objective: Ensure the system is not vulnerable to a self-destruct attack.

