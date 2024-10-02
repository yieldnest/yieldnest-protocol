import {IntegrationBaseTest} from "test/integration/IntegrationBaseTest.sol";
import {IStakingNode} from "src/interfaces/IStakingNode.sol";
import {IDelegationManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {BeaconChainMock, BeaconChainProofs, CheckpointProofs, CredentialProofs } from "lib/eigenlayer-contracts/src/test/integration/mocks/BeaconChainMock.t.sol";
import {IStrategy} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";

interface IEigenPodSimplified {
    function verifyWithdrawalCredentials(uint64 beaconTimestamp, BeaconChainProofs.StateRootProof calldata stateRootProof, uint40[] calldata validatorIndices, bytes[] calldata validatorFieldsProofs, bytes32[][] calldata validatorFields) external;
    function verifyCheckpointProofs(BeaconChainProofs.BalanceContainerProof calldata balanceContainerProof, BeaconChainProofs.BalanceProof[] calldata proofs) external;
}

interface ITransparentUpgradeableProxy {
    function upgradeTo(address) external payable;
}

contract StakingNodeTestBase is IntegrationBaseTest {
    
    struct QueuedWithdrawalInfo {
        uint256 withdrawnAmount;
    }

    struct StateSnapshot {
        uint256 totalAssets;
        uint256 totalSupply;
        uint256 stakingNodeBalance;
        uint256 queuedShares;
        uint256 withdrawnETH;
        uint256 unverifiedStakedETH;
        int256 podOwnerShares;
    }

    function createStakingNodes(uint nodeCount) public returns (uint256[] memory) {
        uint256[] memory nodeIds = new uint256[](nodeCount);
        for (uint256 i = 0; i < nodeCount; i++) {
            vm.prank(actors.ops.STAKING_NODE_CREATOR);
            IStakingNode node = stakingNodesManager.createStakingNode();
            nodeIds[i] = node.nodeId();
        }
        return nodeIds;
    }

    function _verifyWithdrawalCredentials(uint256 _nodeId, uint40 _validatorIndex) internal {
        uint40[] memory _validators = new uint40[](1);
        _validators[0] = _validatorIndex;

        
        CredentialProofs memory _proofs = beaconChain.getCredentialProofs(_validators);
        vm.startPrank(actors.ops.STAKING_NODES_OPERATOR);
        IEigenPodSimplified(address(stakingNodesManager.nodes(_nodeId))).verifyWithdrawalCredentials({
            beaconTimestamp: _proofs.beaconTimestamp,
            stateRootProof: _proofs.stateRootProof,
            validatorIndices: _validators,
            validatorFieldsProofs: _proofs.validatorFieldsProofs,
            validatorFields: _proofs.validatorFields
        });
        vm.stopPrank();
    }

    function takeSnapshot(uint256 nodeId) internal view returns (StateSnapshot memory) {
        return StateSnapshot({
            totalAssets: yneth.totalAssets(),
            totalSupply: yneth.totalSupply(),
            stakingNodeBalance: stakingNodesManager.nodes(nodeId).getETHBalance(),
            queuedShares: stakingNodesManager.nodes(nodeId).getQueuedSharesAmount(),
            withdrawnETH: stakingNodesManager.nodes(nodeId).getWithdrawnETH(),
            unverifiedStakedETH: stakingNodesManager.nodes(nodeId).unverifiedStakedETH(),
            podOwnerShares: eigenPodManager.podOwnerShares(address(stakingNodesManager.nodes(nodeId)))
        });
    }

    function _completeQueuedWithdrawals(QueuedWithdrawalInfo[] memory queuedWithdrawals, uint256 nodeId) internal {
        // create Withdrawal struct
        IDelegationManager.Withdrawal[] memory _withdrawals = new IDelegationManager.Withdrawal[](queuedWithdrawals.length);
        {
            for (uint256 i = 0; i < queuedWithdrawals.length; i++) {
                uint256[] memory _shares = new uint256[](1);
                _shares[0] = queuedWithdrawals[i].withdrawnAmount;
                IStrategy[] memory _strategies = new IStrategy[](1);
                _strategies[0] = IStrategy(0xbeaC0eeEeeeeEEeEeEEEEeeEEeEeeeEeeEEBEaC0); // beacon chain eth strat
                address _stakingNode = address(stakingNodesManager.nodes(nodeId));
                _withdrawals[i] = IDelegationManager.Withdrawal({
                    staker: _stakingNode,
                    delegatedTo: delegationManager.delegatedTo(_stakingNode),
                    withdrawer: _stakingNode,
                    nonce: delegationManager.cumulativeWithdrawalsQueued(_stakingNode) - 1,
                    startBlock: uint32(block.number),
                    strategies: _strategies,
                    shares: _shares
                });   
            }
        }

        {
            IStrategy[] memory _strategies = new IStrategy[](1);
            _strategies[0] = IStrategy(0xbeaC0eeEeeeeEEeEeEEEEeeEEeEeeeEeeEEBEaC0); // beacon chain eth strat

            // advance time to allow completion
            vm.roll(block.number + delegationManager.getWithdrawalDelay(_strategies));
        }

        // complete queued withdrawals
        {
            uint256[] memory _middlewareTimesIndexes = new uint256[](_withdrawals.length);
            // all is zeroed out by defailt
            _middlewareTimesIndexes[0] = 0;
            vm.startPrank(actors.ops.STAKING_NODES_OPERATOR);
            stakingNodesManager.nodes(nodeId).completeQueuedWithdrawals(_withdrawals, _middlewareTimesIndexes);
            vm.stopPrank();
        }
    }

    function startAndVerifyCheckpoint(uint256 nodeId, uint40[] memory _validators) internal {
        // start checkpoint
        {
            vm.startPrank(actors.ops.STAKING_NODES_OPERATOR);
            stakingNodesManager.nodes(nodeId).startCheckpoint(true);
            vm.stopPrank();
        }
        // verify checkpoints
        {
            IStakingNode _node = stakingNodesManager.nodes(nodeId);
            CheckpointProofs memory _cpProofs = beaconChain.getCheckpointProofs(_validators, _node.eigenPod().currentCheckpointTimestamp());
            IEigenPodSimplified(address(_node.eigenPod())).verifyCheckpointProofs({
                balanceContainerProof: _cpProofs.balanceContainerProof,
                proofs: _cpProofs.balanceProofs
            });
        }
    }
}