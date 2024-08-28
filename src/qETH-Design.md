Upcoming Components
Unified liquidity model - Withdrawal flow
The ability to withdraw will not be available immediately upon launch. This functionality will be introduced in subsequent epochs to ensure stability and security within the YieldNest protocol. We are currently developing a unified liquidity model for all our LRT products that will be implemented over time; a more detailed explanation follows below.


Unified liquidity model
As YieldNest develops a broader range of LRT products (e.g., thematic AVS baskets, risk-tranched AVS baskets, and isolated AVS tokens), it becomes increasingly important to ensure deep liquidity for each of the ever-growing number of YieldNest LRTs. Because we envision a rapidly expanding AVS and LRT landscape, we prioritized designing a liquidity model that minimizes liquidity fragmentation by providing unified liquidity for all YieldNest LRTs. This model works by introducing a liquid token (qETH) representing ETH that is escrowed in the EigenLayer withdrawal queue. Because withdrawal-escrowed ETH no longer has exposure to any particular AVS's risks (slashing) or rewards (yield), all YieldNest LRTs become fungible once withdrawal escrow is initiated. Therefore, any YieldNest LRT can be directly converted to the same token (qETH) representing ETH in the withdrawal-escrowed state. This allows for a single qETH/ETH liquidity hub to support expedited exit from any YieldNest LRT.

Curve ynTryLSD - R&D - WIP
YieldNest plans to develop and deploy a TryLSD Pool on Curve with blue chip liquid staking derivatives (LSDs), including wstETH, rETH, and sfrxETH.

YieldNest will onboard many AVSs and new collateral types that make sense for the protocol and broader ecosystem. It sees the use of restaked LP pools like TryLSD as a natural and beneficial development. The TryLSD Curve pool can be used as restaked collateral and economic security, making staking more capital efficient.

In addition to facilitating restaking with high-quality AVSs, YieldNest also plans to [or: may also] launch its own AVSs which cater to core needs throughout the DeFi ecosystem. For example, many DeFi protocols have tunable parameters that are adjusted over time to accommodate changing risks and market conditions. YieldFi may develop AVSs that are specialized for running optimization software (e.g., curvesim) and/or AI models to update these parameters in an automated manner.

Ethereum Validators/EigenLayer Operators
Phase 1:

To ensure the security, scalability, reliability, and high yield of its Native Liquid Restaking Protocol, YieldNest will initially work exclusively with a permissioned group of professional operators. These carefully selected EigenLayer operators will be responsible for running Ethereum validators that natively restake on EigenLayer and run AVS modules to maximize restaking rewards for ynETH token holders. 

The permissioned setup will allow YieldNest to meticulously control and optimize the protocol's performance, ensuring a smooth user experience. Ethereum validators and Eigenlayer operators will be whitelisted following a rigorous vetting process conducted by the YieldNest DAO. Once approved, operators will receive token delegations via smart contracts, enabling them to participate in the restaking process.

Given the potential risks associated with AVSs, the YieldNest DAO will conduct thorough research and vote on each AVS proposed for inclusion. Only approved AVSs will be whitelisted, allowing node operators to select from a pool of vetted and secure options.

Phase 2:

YieldNest is committed to Ethereum's long-term decentralization and censorship resistance goals and ethos. To that point, when it matures, the protocol plans to transition from a permissioned to a permissionless validator/operator system, leveraging Distributed Validator Technology (DVT).

With DVT, YieldNest will drastically reduce the Ethereum validator staking requirement from 32 ETH to 1-4 ETH. This will lower the barrier to entry for Ethereum validators, enabling individuals who don't have 32 ETH to participate in the network actively.

DVT also mitigates slashing risks and enhances uptime, contributing to higher yields for ynETH token holders. This trifecta of benefits—lower barriers to entry, reduced risks, and improved yields—paves the way for a more inclusive, resilient, and rewarding YieldNest ecosystem.