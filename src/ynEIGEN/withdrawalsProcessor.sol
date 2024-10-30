// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IDelegationManager} from "@eigenlayer/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategy} from "@eigenlayer/src/contracts/interfaces/IStrategy.sol";

import {IWithdrawalQueueManager} from "../interfaces/IWithdrawalQueueManager.sol";
import {ITokenStakingNodesManager} from "../interfaces/ITokenStakingNodesManager.sol";
import {ITokenStakingNode} from "../interfaces/ITokenStakingNode.sol";
import {IAssetRegistry} from "../interfaces/IAssetRegistry.sol";
import {IEigenStrategyManager} from "../interfaces/IEigenStrategyManager.sol";

contract withdrawalsProcessor is Ownable {

    struct QueuedWithdrawal {
        address node;
        address strategy;
        uint256 nonce;
        uint256 shares;
        uint32 startBlock;
        bool completed;
    }

    uint256 public id;
    uint256 public minNodeShares;
    uint256 public minPendingWithdrawalRequestAmount;

    // yieldnest
    IWithdrawalQueueManager public immutable withdrawalQueueManager;
    ITokenStakingNodesManager public immutable tokenStakingNodesManager;
    IAssetRegistry public immutable assetRegistry;
    IEigenStrategyManager public immutable eigenStrategyManager;

    // eigenlayer
    IDelegationManager public immutable delegationManager;

    mapping(uint256 id => QueuedWithdrawal) public queuedWithdrawals;

    //
    // Constructor
    //

    constructor(
        address _owner,
        address _withdrawalQueueManager,
        address _tokenStakingNodesManager,
        address _assetRegistry,
        address _eigenStrategyManager,
        address _delegationManager
    ) Ownable(_owner) {
        if (
            _withdrawalQueueManager == address(0) ||
            _tokenStakingNodesManager == address(0) ||
            _assetRegistry == address(0) ||
            _eigenStrategyManager == address(0) ||
            _delegationManager == address(0)
        ) revert InvalidInput();

        withdrawalQueueManager = IWithdrawalQueueManager(_withdrawalQueueManager);
        tokenStakingNodesManager = ITokenStakingNodesManager(_tokenStakingNodesManager);
        assetRegistry = IAssetRegistry(_assetRegistry);
        eigenStrategyManager = IEigenStrategyManager(_eigenStrategyManager);
        delegationManager = IDelegationManager(_delegationManager);
    }

    //
    // Processor functions
    //

    function queueWithdrawals() external onlyOwner returns (bool) {

        uint256 _pendingWithdrawalRequests = withdrawalQueueManager.pendingRequestedRedemptionAmount();
        if (_pendingWithdrawalRequests <= minPendingWithdrawalRequestAmount) return true;

        ITokenStakingNode[] memory _nodes = tokenStakingNodesManager.getAllNodes();
        IERC20[] memory _assets = assetRegistry.getAssets();

        uint256 _assetsLength = _assets.length;
        uint256 _nodesLength = _nodes.length;
        uint256 _minNodeShares = minNodeShares;
        for (uint256 i = 0; i < _assetsLength; ++i) {
            IStrategy _strategy = eigenStrategyManager.strategies(_assets[i]);
            uint256 _pendingWithdrawalRequestsInShares = _unitToShares(_pendingWithdrawalRequests);
            for (uint256 j = 0; j < _nodesLength; ++j) {
                bool _rekt;
                uint256 _withdrawnShares;
                address _node = address(_nodes[j]);
                uint256 _nodeShares = _strategy.shares(_node);
                if (_nodeShares > _pendingWithdrawalRequestsInShares) {
                    _rekt = true;
                    _withdrawnShares = _nodeShares - _pendingWithdrawalRequestsInShares;
                    _pendingWithdrawalRequestsInShares = 0;
                } else if (_nodeShares > _minNodeShares) {
                    _rekt = true;
                    _withdrawnShares = _nodeShares;
                    _pendingWithdrawalRequestsInShares -= _withdrawnShares;
                }

                if (_rekt) {
                    queuedWithdrawals[id++] = QueuedWithdrawal(
                        _node, // stakingNode
                        address(_strategy), // strategy
                        delegationManager.cumulativeWithdrawalsQueued(_node), // nonce
                        _withdrawnShares, // shares
                        uint32(block.number), // startBlock
                        false // completed
                    );
                    ITokenStakingNode(_node).queueWithdrawals(_strategy, _withdrawnShares);
                }

                if (_pendingWithdrawalRequestsInShares == 0) return true;
            }

            _pendingWithdrawalRequests = _sharesToUnit(_pendingWithdrawalRequestsInShares);
        }

        return false;
    }

    function completeQueuedWithdrawals(uint256 _startId) external {

        uint256 _id = id;
        if (_startId > _id) revert InvalidInput();

        for (uint256 i = _startId; i < _id; ++i) {

            QueuedWithdrawal memory _queuedWithdrawal = queuedWithdrawals[i];
            if (_queuedWithdrawal.completed) revert AlreadyCompleted();

            queuedWithdrawals[i].completed = true;

            IStrategy[] memory _strategies = new IStrategy[](1);
            _strategies[0] = _queuedWithdrawal.strategy;
            uint256 _withdrawalDelay = delegationManager.getWithdrawalDelay(_strategies);
            if (block.number < _queuedWithdrawal.startBlock + _withdrawalDelay) revert NotReady();

            uint256[] memory _middlewareTimesIndexes = new uint256[](1);
            _middlewareTimesIndexes[0] = 0;

            ITokenStakingNode(_queuedWithdrawal.node).completeQueuedWithdrawals(
                _queuedWithdrawal.nonce,
                _queuedWithdrawal.startBlock,
                _queuedWithdrawal.shares,
                _queuedWithdrawal.strategy,
                _middlewareTimesIndexes,
                true // updateTokenStakingNodesBalances
            );
        }
    }

    function processPrincipalWithdrawals() external {
        // 1. check pending withdrawal requests
        // 2. send everything to queue if can't satisfy (or can satisfy everything without extra)
        // 3. if extra, reinvest
    }

    //
    // Management functions
    //

    function updateMinNodeShares(uint256 _minNodeShares) external onlyOwner {
        if (_minNodeShares == 0) revert InvalidInput();
        minNodeShares = _minNodeShares;
        emit MinNodeSharesUpdated(_minNodeShares);
    }

    function updateMinPendingWithdrawalRequestAmount(uint256 _minPendingWithdrawalRequestAmount) external onlyOwner {
        if (_minPendingWithdrawalRequestAmount == 0) revert InvalidInput();
        minPendingWithdrawalRequestAmount = _minPendingWithdrawalRequestAmount;
        emit MinPendingWithdrawalRequestAmountUpdated(_minPendingWithdrawalRequestAmount);
    }

    //
    // Private functions
    //

    function _unitToShares(uint256 _unit) private pure returns (uint256) {}
    function _sharesToUnit(uint256 _shares) private pure returns (uint256) {}

    //
    // Errors
    //

    error InvalidInput();
    error AlreadyCompleted();
    error NotReady();

    //
    // Events
    //

    event MinNodeSharesUpdated(uint256 minNodeShares);
    event MinPendingWithdrawalRequestAmountUpdated(uint256 minPendingWithdrawalRequestAmount);
}