# Staking Architecture

The following document provides a general comparison of the key features and functionalities of the YieldNest, Renzo, Kelp, and Ether.Fi staking contracts.


### General Comparison Table
Here's a product comparison table for YieldNest (ynETH and ynLSD), Renzo, Kelp (LRTDepositPool), and EtherFi (EarlyAdopterPool):

| Feature                           | YieldNest                          | Renzo                              | Kelp (LRTDepositPool)              | EtherFi (EarlyAdopterPool)         |
|-----------------------------------|------------------------------------|------------------------------------|------------------------------------|------------------------------------|
| Supported Assets                  | Ethereum, LSD tokens               | Multiple collateral tokens         | ETH, other assets                  | Ethereum, selected ERC20 tokens    |
| Staking Rewards                   | Yes (through RewardsDistributor)   | Yes (based on staked assets)       | Not explicitly mentioned           | Yes (based on deposit duration and amount) |
| Rewards Distribution Mechanism    | RewardsDistributor contract        | Dynamic token TVL limits and OperatorDelegator allocations | Not explicitly mentioned           | Claiming process based on time and amount |
| External Dependencies             | StakingNodesManager, oracle        | StrategyManager, DelegationManager, DepositQueue, oracle | LRTOracle, RSETH, LRTManager, LRTAdmin | None mentioned                     |
| Pause Deposits                    | Yes                                | Yes                                | Not mentioned                      | Not mentioned                      |
| Exchange Rate Adjustment          | Yes                                | Not mentioned                      | Not mentioned                      | Not mentioned                      |
| Asset Swapping                    | Not mentioned                      | Not mentioned                      | Yes                                | Not mentioned                      |
| Operator Delegators               | Not mentioned                      | Yes                                | Yes                                | Not mentioned                      |
| TVL Limits                        | Not mentioned                      | Yes (per token)                    | Yes (max node delegator limit)     | Not mentioned                      |
| Centralization Concerns           | Dependency on external oracle      | Dependency on multiple external contracts and oracle | Dependency on LRTManager and LRTAdmin | Dependency on contract owner       |
| Claiming Process                  | Not mentioned                      | Not mentioned                      | Not mentioned                      | Time-sensitive with manual management |


# Staking Contract Comparison

## YieldNest
- Provides a decentralized staking solution for Ethereum and LSD tokens, allowing users to earn staking rewards.
- Implements a rewards distribution mechanism to incentivize users to stake their assets.
- Offers a way to pause deposits and adjust the exchange rate to manage the system's stability.
- Limited to Ethereum and specific LSD tokens, which may restrict the diversity of assets users can stake.
- The system's security and efficiency depend on the proper functioning of the StakingNodesManager and RewardsDistributor contracts.
- Relies on an external oracle for pricing information, which introduces a potential point of failure.

`ynETH.sol`

```mermaid
sequenceDiagram
    participant A as Admin
    participant y as ynETH
    participant SNM as StakingNodesManager
    participant RD as RewardsDistributor
    participant SN as StakingNode

    %% Initialization %%
    A->>y: initialize()
    y->>y: Set stakingNodesManager, rewardsDistributor, exchangeAdjustmentRate

    %% Deposit ETH %%
    user->>y: depositETH(receiver)
    y->>y: Calculate shares
    y->>y: Mint ynETH
    y->>y: Update totalDepositedInPool

    %% Receive Rewards %%
    RD->>y: receiveRewards()
    y->>y: Update totalDepositedInPool

    %% Withdraw ETH %%
    SNM->>y: withdrawETH(ethAmount)
    y->>y: Transfer ETH to StakingNodesManager
    y->>y: Update totalDepositedInPool

    %% Process Withdrawn ETH %%
    SNM->>y: processWithdrawnETH()
    y->>y: Update totalDepositedInPool

    %% Set Deposit ETH Paused %%
    A->>y: setIsDepositETHPaused(isPaused)
    y->>y: Update isDepositETHPaused

    %% Set Exchange Adjustment Rate %%
    SNM->>y: setExchangeAdjustmentRate(newRate)
    y->>y: Update exchangeAdjustmentRate
```

`ynLSD.sol`

```mermaid
sequenceDiagram
    participant Admin as Admin
    participant User as User
    participant yLSD as yLSD
    participant Token as IERC20
    participant StrategyMgr as IStrategyManager
    participant Oracle as YieldNestOracle
    participant Strategy as IStrategy

    %% Initialization %%
    Admin->>yLSD: initialize(init)
    yLSD->>yLSD: Set tokens, strategies, strategyManager, oracle, exchangeAdjustmentRate

    %% Deposit %%
    User->>yLSD: deposit(token, amount, receiver)
    yLSD->>yLSD: Check if token is supported
    yLSD->>Token: safeTransferFrom(User, yLSD, amount)
    yLSD->>Token: approve(StrategyMgr, amount)
    yLSD->>StrategyMgr: depositIntoStrategy(Strategy, Token, amount)
    yLSD->>yLSD: Update depositedBalances
    yLSD->>Oracle: getLatestPrice(token)
    yLSD->>yLSD: Calculate shares
    yLSD->>yLSD: _mint(receiver, shares)
    yLSD->>User: emit Deposit(msg.sender, receiver, amount, shares)

    %% Total Assets %%
    User->>yLSD: totalAssets()
    loop For each token
        yLSD->>Oracle: getLatestPrice(token)
        yLSD->>yLSD: Calculate total assets
    end
```

## Renzo
- Provides a comprehensive staking solution with support for multiple collateral tokens.
- Includes a mechanism for distributing rewards to users based on their staked assets.
- Allows for dynamic adjustment of token TVL limits and OperatorDelegator allocations to manage the system's liquidity.
- Complexity of the contract increases the risk of bugs and vulnerabilities.
- Dependency on multiple external contracts (e.g., StrategyManager, DelegationManager, DepositQueue) can lead to potential integration issues.
- Relies on an external oracle for pricing information, similar to YieldNest.

`RestakeManager.sol`

```mermaid
sequenceDiagram
    participant Admin as RestakeManagerAdmin
    participant RM as RestakeManager
    participant OD as OperatorDelegator
    participant SM as StrategyManager
    participant DM as DelegationManager
    participant DQ as DepositQueue
    participant RO as RenzoOracle
    participant Ez as EzEthToken

    %% Initialization %%
    Admin->>RM: initialize(roleManager, ezETH, renzoOracle, strategyManager, delegationManager, depositQueue)
    RM->>RM: Set roleManager, ezETH, renzoOracle, strategyManager, delegationManager, depositQueue, paused

    %% Add Operator Delegator %%
    Admin->>RM: addOperatorDelegator(newOperatorDelegator, allocationBasisPoints)
    RM->>RM: Add newOperatorDelegator to operatorDelegators, set allocation

    %% Remove Operator Delegator %%
    Admin->>RM: removeOperatorDelegator(operatorDelegatorToRemove)
    RM->>RM: Remove operatorDelegatorToRemove from operatorDelegators, clear allocation

    %% Set Operator Delegator Allocation %%
    Admin->>RM: setOperatorDelegatorAllocation(operatorDelegator, allocationBasisPoints)
    RM->>RM: Set allocation for operatorDelegator

    %% Set Max Deposit TVL %%
    Admin->>RM: setMaxDepositTVL(maxDepositTVL)
    RM->>RM: Set maxDepositTVL

    %% Add Collateral Token %%
    Admin->>RM: addCollateralToken(newCollateralToken)
    RM->>RM: Add newCollateralToken to collateralTokens

    %% Remove Collateral Token %%
    Admin->>RM: removeCollateralToken(collateralTokenToRemove)
    RM->>RM: Remove collateralTokenToRemove from collateralTokens

    %% Deposit ERC20 Token %%
    user->>RM: deposit(collateralToken, amount, referralId)
    RM->>RM: Choose OperatorDelegator, transfer token, deposit in EigenLayer, mint ezETH

    %% Deposit ETH %%
    user->>RM: depositETH(referralId)
    RM->>DQ: depositETHFromProtocol(value: msg.value)
    RM->>RM: Calculate ezETH to mint, mint ezETH

    %% Stake Eth in Operator Delegator %%
    DQ->>RM: stakeEthInOperatorDelegator(operatorDelegator, pubkey, signature, depositDataRoot)
    RM->>OD: stakeEth{value: msg.value}(pubkey, signature, depositDataRoot)

    %% Deposit Token Rewards from Protocol %%
    DQ->>RM: depositTokenRewardsFromProtocol(token, amount)
    RM->>RM: Transfer token, approve to OperatorDelegator, deposit in EigenLayer

    %% Get Total Rewards Earned %%
    user->>RM: getTotalRewardsEarned()
    RM->>RM: Calculate total rewards from DepositQueue and OperatorDelegators

    %% Set Token TVL Limit %%
    Admin->>RM: setTokenTvlLimit(token, limit)
    RM->>RM: Set TVL limit for token

    %% Set Paused State %%
    Admin->>RM: setPaused(paused)
    RM->>RM: Set paused state
```

## Kelp
- Supports deposits of both ETH and other assets, providing flexibility for users.
- Includes a mechanism for swapping ETH for other assets within the deposit pool.
- Allows for the addition and removal of NodeDelegator contracts to manage the staking process.
- Limited to the LRT ecosystem, which may restrict its adoption compared to more general-purpose staking solutions.
- The system's stability depends on the proper functioning of the LRTOracle and RSETH contracts.
- The contract's functionality is heavily reliant on the LRTManager and LRTAdmin roles, which could introduce centralization concerns.

`LRTDepositPool.sol`

```mermaid
sequenceDiagram
    participant LRTM as LRTManager
    participant LRTA as LRTAdmin
    participant LP as LRTDepositPool
    participant ND as NodeDelegator
    participant LRO as LRTOracle
    participant RS as RSETH

    %% Initialization %%
    LRTM->>LP: initialize(lrtConfigAddr)
    LP->>LP: Set lrtConfig, maxNodeDelegatorLimit

    %% Deposit ETH %%
    user->>LP: depositETH(minRSETHAmountExpected, referralId)
    LP->>LP: Calculate rsethAmountToMint
    LP->>RS: _mintRsETH(rsethAmountToMint)

    %% Deposit Asset %%
    user->>LP: depositAsset(asset, depositAmount, minRSETHAmountExpected, referralId)
    LP->>LP: Calculate rsethAmountToMint
    LP->>LP: Transfer asset to LRTDepositPool
    LP->>RS: _mintRsETH(rsethAmountToMint)

    %% Add Node Delegator Contract %%
    LRTA->>LP: addNodeDelegatorContractToQueue(nodeDelegatorContracts)
    LP->>LP: Add node delegator contracts to queue

    %% Remove Node Delegator Contract %%
    LRTA->>LP: removeNodeDelegatorContractFromQueue(nodeDelegatorAddress)
    LP->>LP: Remove node delegator contract from queue

    %% Transfer Asset To Node Delegator %%
    LRTM->>LP: transferAssetToNodeDelegator(ndcIndex, asset, amount)
    LP->>ND: Transfer asset to NodeDelegator

    %% Transfer ETH To Node Delegator %%
    LRTM->>LP: transferETHToNodeDelegator(ndcIndex, amount)
    LP->>ND: Transfer ETH to NodeDelegator

    %% Swap ETH For Asset %%
    LRTM->>LP: swapETHForAssetWithinDepositPool(toAsset, minToAssetAmount)
    LP->>LRO: getSwapETHToAssetReturnAmount(toAsset, ethAmountSent)
    LP->>LP: Transfer asset to LRTManager

    %% Update Max Node Delegator Limit %%
    LRTA->>LP: updateMaxNodeDelegatorLimit(maxNodeDelegatorLimit_)
    LP->>LP: Update maxNodeDelegatorLimit

    %% Set Min Amount To Deposit %%
    LRTA->>LP: setMinAmountToDeposit(minAmountToDeposit_)
    LP->>LP: Update minAmountToDeposit

    %% Pause %%
    LRTM->>LP: pause()
    LP->>LP: Pause contract

    %% Unpause %%
    LRTA->>LP: unpause()
    LP->>LP: Unpause contract
```

## EtherFi
- Provides a simple and straightforward staking solution for Ethereum and selected ERC20 tokens.
- Allows users to claim rewards based on their deposit duration and amount, incentivizing long-term participation.
- Offers a mechanism for users to withdraw their funds or claim rewards to a designated contract.
- Limited to a predefined set of ERC20 tokens, which may restrict user participation.
- The claiming process is time-sensitive, which may disadvantage users who miss the claim deadline.
- Relies on manual management by the contract owner to set claim deadlines and receiver contracts, introducing potential centralization issues.

`EarlyAdopterPool.sol`

```mermaid
sequenceDiagram
    participant Admin as Owner
    participant User as User
    participant EAP as EarlyAdopterPool
    participant rETHInst as rETHInstance
    participant wstETHInst as wstETHInstance
    participant sfrxETHInst as sfrxETHInstance
    participant cbETHInst as cbETHInstance

    %% Initialization %%
    Admin->>EAP: constructor(rETH, wstETH, sfrxETH, cbETH)
    EAP->>EAP: Set rETH, wstETH, sfrxETH, cbETH instances

    %% Deposit ERC20 Token %%
    User->>EAP: deposit(_erc20Contract, _amount)
    EAP->>EAP: Update depositInfo, userToErc20Balance
    EAP->>rETHInst: transferFrom(User, EAP, _amount) [if _erc20Contract == rETH]
    EAP->>wstETHInst: transferFrom(User, EAP, _amount) [if _erc20Contract == wstETH]
    EAP->>sfrxETHInst: transferFrom(User, EAP, _amount) [if _erc20Contract == sfrxETH]
    EAP->>cbETHInst: transferFrom(User, EAP, _amount) [if _erc20Contract == cbETH]

    %% Deposit Ether %%
    User->>EAP: depositEther() [msg.value]
    EAP->>EAP: Update depositInfo

    %% Withdraw Funds %%
    User->>EAP: withdraw()
    EAP->>EAP: transferFunds(0)

    %% Claim Funds %%
    User->>EAP: claim()
    EAP->>EAP: transferFunds(1)

    %% Set Claiming Open %%
    Admin->>EAP: setClaimingOpen(_claimDeadline)
    EAP->>EAP: Set claimDeadline, claimingOpen, endTime

    %% Set Claim Receiver Contract %%
    Admin->>EAP: setClaimReceiverContract(_receiverContract)
    EAP->>EAP: Set claimReceiverContract

    %% Pause Contract %%
    Admin->>EAP: pauseContract()
    EAP->>EAP: Pause contract

    %% Unpause Contract %%
    Admin->>EAP: unPauseContract()
    EAP->>EAP: Unpause contract

    %% Internal: Transfer Funds %%
    EAP->>EAP: transferFunds(_identifier)
    EAP->>rETHInst: transfer(receiver, rETHbal)
    EAP->>wstETHInst: transfer(receiver, wstETHbal)
    EAP->>sfrxETHInst: transfer(receiver, sfrxEthbal)
    EAP->>cbETHInst: transfer(receiver, cbEthBal)
    EAP->>User: send(ethBalance) [if receiver == User]
    EAP->>claimReceiverContract: send(ethBalance) [if receiver == claimReceiverContract]
```
