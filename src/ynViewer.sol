// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IDelegationManager, IStrategy} from "@eigenlayer/src/contracts/interfaces/IDelegationManager.sol";
import {IEigenPodManager} from "@eigenlayer/src/contracts/interfaces/IEigenPodManager.sol";

import {IStakingNode, IStakingNodesManager, IynViewer} from "./interfaces/IynViewer.sol";

interface IynETH {
    function totalSupply() external view returns (uint256);
    function totalAssets() external view returns (uint256);
}

contract ynViewer is IynViewer {

    IynETH public immutable ynETH;
    IStakingNodesManager public immutable stakingNodesManager;

    /// @notice Initializes a new ynViewer contract.
    /// @param _ynETH The address of the ynETH contract.
    /// @param _stakingNodesManager The address of the StakingNodesManager contract.
    constructor(address _ynETH, address _stakingNodesManager) {
        ynETH = IynETH(_ynETH);
        stakingNodesManager = IStakingNodesManager(_stakingNodesManager);
    }

    /// @inheritdoc IynViewer
    function getAllValidators() public view returns (IStakingNodesManager.Validator[] memory) {
        return stakingNodesManager.getAllValidators();
    }

    /// @inheritdoc IynViewer
    function getRate() external view returns (uint256) {
        uint256 _totalSupply = ynETH.totalSupply();
        uint256 _totalAssets = ynETH.totalAssets();
        if (_totalSupply == 0 || _totalAssets == 0) return 1 ether;
        return 1 ether * _totalAssets / _totalSupply;
    }

    /// @inheritdoc IynViewer
    function withdrawalDelayBlocks(address) external view returns (uint256) {
        IDelegationManager _delegationManager = stakingNodesManager.delegationManager();
        return _delegationManager.minWithdrawalDelayBlocks();
    }

    /// @inheritdoc IynViewer
    function getStakingNodeData() external view returns (StakingNodeData[] memory _data) {
        IStakingNode[] memory _nodes = stakingNodesManager.getAllNodes();

        uint256 _length = _nodes.length;
        _data = new StakingNodeData[](_length);

        IEigenPodManager _eigenPodManager = stakingNodesManager.eigenPodManager();
        for (uint256 i = 0; i < _length; ++i) {
            IStakingNode _node = _nodes[i];
            address _eigenPod = address(_eigenPodManager.getPod(address(_node)));
            _data[i] = StakingNodeData({
                nodeId: _node.nodeId(),
                ethBalance: _node.getETHBalance(),
                eigenPodEthBalance: _eigenPod.balance,
                podOwnerShares: _eigenPodManager.podOwnerDepositShares(address(_node)),
                stakingNode: address(_node),
                eigenPod: _eigenPod,
                delegatedTo: stakingNodesManager.delegationManager().delegatedTo(address(_node))
            });
        }
    }
}