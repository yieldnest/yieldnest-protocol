
`ynETH.sol`

```mermaid
sequenceDiagram
    participant U as User
    participant y as ynETH
    participant SNM as StakingNodesManager
    participant RD as RewardsDistributor
    participant SN as StakingNode
    participant A as Admin

    %% Initialization %%
    A->>y: initialize()
    y->>y: Set stakingNodesManager, rewardsDistributor, exchangeAdjustmentRate, ROLES
    %% Deposit ETH %%
    U->>y: depositETH(receiver)
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
---
`ynLSD.sol`

```mermaid
sequenceDiagram
    participant User as User
    participant yLSD as yLSD
    participant Token as IERC20
    participant StrategyMgr as IStrategyManager
    participant Oracle as YieldNestOracle
    participant Strategy as IStrategy
    participant Admin as Admin

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
---
`StakeNode.sol`

```mermaid
sequenceDiagram
    participant A as Admin
    participant S as StakingNode
    participant SM as StakingNodesManager
    participant EP as EigenPod
    participant DM as DelegationManager
    participant SRM as StrategyManager
    participant DR as DelayedWithdrawalRouter

    %% Initialization %%
    A->>S: initialize()
    S->>SM: set stakingNodesManager
    S->>SRM: set strategyManager
    S->>S: set nodeId

    %% EigenPod Creation %%
    A->>S: createEigenPod()
    S->>SM: get eigenPodManager
    S->>EP: createPod()
    S->>EP: getPod()
    S->>S: set eigenPod
    S->>A: return eigenPod

    %% Withdrawal Before Restaking %%
    A->>S: withdrawBeforeRestaking()
    S->>EP: withdrawBeforeRestaking()

    %% Claim Delayed Withdrawals %%
    A->>S: claimDelayedWithdrawals(maxNumWithdrawals)
    S->>SM: get delayedWithdrawalRouter
    S->>DR: getUserDelayedWithdrawals()
    S->>DR: claimDelayedWithdrawals()

    %% Delegate %%
    A->>S: delegate(operator)
    S->>SM: get delegationManager
    S->>DM: delegateTo(operator)

    %% Verify Withdrawal Credentials %%
    A->>S: verifyWithdrawalCredentials()
    S->>EP: verifyWithdrawalCredentialsAndBalance()

    %% Start Withdrawal %%
    A->>S: startWithdrawal(amount)
    S->>SRM: queueWithdrawal()
    S->>S: emit WithdrawalStarted

    %% Complete Withdrawal %%
    A->>S: completeWithdrawal(params)
    S->>SRM: completeQueuedWithdrawal()
    S->>SM: processWithdrawnETH()

    %% Allocate Staked ETH %%
    SM->>S: allocateStakedETH(amount)
    S->>S: update totalETHNotRestaked

    %% Get ETH Balance %%
    A->>S: getETHBalance()
    S->>SRM: stakerStrategyShares()
    S->>A: return balance

    %% Implementation %%
    A->>S: implementation()
    S->>S: get beacon implementation
    S->>A: return implementation
```
---
  `StakingNodesManager.sol`

  ```mermaid
  sequenceDiagram
    participant Admin as Admin
    participant SNM as StakingNodesManager
    participant DC as DepositContract
    participant Node as StakingNode
    participant EP as EigenPod

    %% Initialization %%
    Admin->>SNM: initialize()
    SNM->>SNM: Set roles, depositContract, eigenPodManager, ynETH, delegationManager, delayedWithdrawalRouter, strategyManager

    %% Receive ETH %%
    ynETH->>SNM: send ETH

    %% Register Validators %%
    Admin->>SNM: registerValidators(_depositRoot, _depositData)
    SNM->>SNM: Validate deposit data allocation
    loop For each depositData
        SNM->>SNM: Check if validator already used
        SNM->>SNM: Register validator
        SNM->>DC: deposit{value: _depositAmount}(publicKey, withdrawalCredentials, signature, depositDataRoot)
        SNM->>Node: allocateStakedETH(_depositAmount)
    end

    %% Create Staking Node %%
    Admin->>SNM: createStakingNode()
    SNM->>SNM: Check maxNodeCount
    SNM->>Node: initialize()
    Node->>Node: Set StakingNodesManager, strategyManager, nodeId
    Node->>Node: createEigenPod()
    Node->>EP: createPod()
    SNM->>SNM: Add node to nodes array

    %% Register Staking Node Implementation Contract %%
    Admin->>SNM: registerStakingNodeImplementationContract(_implementationContract)
    SNM->>SNM: Update upgradableBeacon

    %% Set Max Node Count %%
    Admin->>SNM: setMaxNodeCount(_maxNodeCount)
    SNM->>SNM: Update maxNodeCount

    %% Process Withdrawn ETH %%
    Node->>SNM: processWithdrawnETH(nodeId)
    SNM->>ynETH: processWithdrawnETH{value: msg.value}()

    %% Get All Validators %%
    User->>SNM: getAllValidators()
    SNM->>User: Return validators array

    %% Get All Nodes %%
    User->>SNM: getAllNodes()
    SNM->>User: Return nodes array

    %% Nodes Length %%
    User->>SNM: nodesLength()
    SNM->>User: Return nodes.length

    %% Is Staking Nodes Admin %%
    User->>SNM: isStakingNodesAdmin(_address)
    SNM->>User: Return hasRole(STAKING_NODES_ADMIN_ROLE, _address)
```
---
`RewardsReceiver.sol`

```mermaid
sequenceDiagram
    participant C as RewardsReceiver
    participant U as User
    participant E as ERC20 Token
    participant R as Recipient
    participant A as Admin

    A->>C: Deploy Contract
    A->>C: initialize(admin, withdrawer)
    Note over C: Initialization
    C->>C: Grant Roles
    U->>C: transfer(to, amount)
    Note over C: ETH Transfer
    C->>R: Transfer ETH
    U->>C: transferERC20(token, to, amount)
    Note over C: ERC20 Transfer
    C->>E: Request Transfer
    E->>R: Transfer ERC20
```
---
`RewardsDistributor.sol`

```mermaid
sequenceDiagram
    participant A as Admin
    participant C as RewardsDistributor Contract
    participant E as ExecutionLayerReceiver
    participant Y as ynETH Contract
    participant F as FeesReceiver

    A->>C: Deploy Contract
    A->>C: initialize(init)
    Note over C: Initialization
    C->>C: Grant Roles
    C->>C: Set executionLayerReceiver, feesReceiver, ynETH
    C->>C: Set feesBasisPoints to 1_000 (10%)

    alt processRewards
        C->>E: Query balance
        E->>C: Return balance (elRewards)
        C->>C: Calculate fees
        C->>E: Transfer elRewards to self
        C->>Y: Transfer netRewards to ynETH
        C->>F: Transfer fees to FeesReceiver
        Note over C,F: Emit FeesCollected event
    end

    alt setFeesReceiver
        A->>C: setFeesReceiver(newReceiver)
        Note over C: Check notZeroAddress
        C->>C: Update feesReceiver
        Note over C,F: Emit FeeReceiverSet event
    end
```
---
`YieldNestOracle.sol`

```mermaid
sequenceDiagram
    participant A as Admin
    participant OM as OracleManager
    participant YNO as YieldNestOracle
    participant PF as PriceFeed

    %% Initialization %%
    A->>YNO: initialize(init)
    YNO->>YNO: Set ADMIN_ROLE and ORACLE_MANAGER_ROLE
    loop For each asset in init
        YNO->>YNO: setAssetPriceFeed(asset, priceFeedAddress, maxAge)
    end

    %% Set Asset Price Feed %%
    OM->>YNO: setAssetPriceFeed(asset, priceFeedAddress, maxAge)
    YNO->>YNO: _setAssetPriceFeed(asset, priceFeedAddress, maxAge)

    %% Get Latest Price %%
    User->>YNO: getLatestPrice(asset)
    YNO->>PF: priceFeed.latestRoundData()
    PF->>YNO: Return (price, timeStamp)
    YNO->>YNO: Check if price feed is too stale
    YNO->>User: Return price
```