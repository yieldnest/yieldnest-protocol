


# Basic multisig-based flow

```
ynETH ERC4626
       |
 withdrawETH
       |
       v
  +--------+    ETH    +-------------------+
  |Multisig|---------->|Ethereum Staking   |
  +--------+           |Contract           |
       |               |(eigenPod as       |
       |               |withdrawal address)|
       |               +-------------------+
       |                       |
       |                       v
       |               +-------------------+
       |               |Delegation to      |
       +--------------->EigenLayer Node    |
       |               |Operator           |
       |               +-------------------+
       |
       v
  +--------+
  |eigenPod|
  +--------+

```