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
import {IYieldNestStrategyManager} from "../interfaces/IYieldNestStrategyManager.sol";

import "forge-std/console.sol";

/// @dev - there are inefficiencies if stratagies have different withdrawal delays
///        specifically, in `completeQueuedWithdrawals`, we need to wait for the longest withdrawal delay
contract WithdrawalsProcessor is Ownable {

    struct QueuedWithdrawal {
        address node;
        address strategy;
        uint256 nonce;
        uint256 shares;
        uint32 startBlock;
        bool completed;
    }

    // @todo - put ids in a struct
    uint256 public queuedId;
    uint256 public completedId;
    uint256 public processedId;

    uint256 public totalQueuedWithdrawals;

    uint256 public minPendingWithdrawalRequestAmount;

    // yieldnest
    IWithdrawalQueueManager public immutable withdrawalQueueManager;
    ITokenStakingNodesManager public immutable tokenStakingNodesManager;
    IAssetRegistry public immutable assetRegistry;
    IYieldNestStrategyManager public immutable ynStrategyManager;

    // eigenlayer
    IDelegationManager public immutable delegationManager;

    mapping(uint256 id => QueuedWithdrawal) public queuedWithdrawals;
    mapping(uint256 fromId => uint256 toId) public batch;
    mapping (IERC20 asset => uint256 minShares) public minShares;

    //
    // Constructor
    //

    constructor(
        address _owner,
        address _withdrawalQueueManager,
        address _tokenStakingNodesManager,
        address _assetRegistry,
        address _ynStrategyManager,
        address _delegationManager
    ) Ownable(_owner) {
        if (
            _withdrawalQueueManager == address(0) ||
            _tokenStakingNodesManager == address(0) ||
            _assetRegistry == address(0) ||
            _ynStrategyManager == address(0) ||
            _delegationManager == address(0)
        ) revert InvalidInput();

        withdrawalQueueManager = IWithdrawalQueueManager(_withdrawalQueueManager);
        tokenStakingNodesManager = ITokenStakingNodesManager(_tokenStakingNodesManager);
        assetRegistry = IAssetRegistry(_assetRegistry);
        ynStrategyManager = IYieldNestStrategyManager(_ynStrategyManager);
        delegationManager = IDelegationManager(_delegationManager);

        minPendingWithdrawalRequestAmount = 0.1 ether;

        // @todo - fix that
        IERC20[] memory _assets = assetRegistry.getAssets();
        for (uint256 i = 0; i < _assets.length; ++i) {
            minShares[_assets[i]] = 1 ether;
        }
    }

    //
    // Processor functions
    //

    /// @notice Queues withdrawals
    /// @dev Reverts if the total pending withdrawal requests are below the minimum threshold
    /// @dev Skips nodes with shares below the minimum threshold
    /// @dev If a nodes has more shares than the minimum threshold, exits the node entirely
    /// @dev Tries to satisfy the pending withdrawal requests while prioritizing withdrawals in one asset
    /// @dev Saves the queued withdrawals together in a batch, to be completed in the next step (`completeQueuedWithdrawals`)
    /// @return True if all pending withdrawal requests were queued, false otherwise
    function queueWithdrawals() external onlyOwner returns (bool) {

        uint256 _minPendingWithdrawalRequestAmount = minPendingWithdrawalRequestAmount;
        uint256 _pendingWithdrawalRequests = withdrawalQueueManager.pendingRequestedRedemptionAmount() - totalQueuedWithdrawals;
        if (_pendingWithdrawalRequests <= minPendingWithdrawalRequestAmount) revert PendingWithdrawalRequestsTooLow();

        totalQueuedWithdrawals += _pendingWithdrawalRequests;

        ITokenStakingNode[] memory _nodes = tokenStakingNodesManager.getAllNodes();
        IERC20[] memory _assets = assetRegistry.getAssets();

        uint256 _queuedIdBefore = queuedId;
        uint256 _assetsLength = _assets.length;
        uint256 _nodesLength = _nodes.length;
        for (uint256 i = 0; i < _assetsLength; ++i) {
            uint256 _minShares = minShares[_assets[i]];
            IStrategy _strategy = ynStrategyManager.strategies(_assets[i]);
            for (uint256 j = 0; j < _nodesLength; ++j) {
                address _node = address(_nodes[j]);
                uint256 _nodeShares = _strategy.shares(_node);
                if (_nodeShares > _minShares) {
                    uint256 _unitWithdrawalAmount = _sharesToUnit(_nodeShares, _assets[i], _strategy);
                    _pendingWithdrawalRequests =
                        _unitWithdrawalAmount < _pendingWithdrawalRequests ? _pendingWithdrawalRequests - _unitWithdrawalAmount : 0;
                    queuedWithdrawals[queuedId++] = QueuedWithdrawal(
                        _node,
                        address(_strategy),
                        delegationManager.cumulativeWithdrawalsQueued(_node), // nonce
                        _nodeShares,
                        uint32(block.number), // startBlock
                        false // completed
                    );
                    ITokenStakingNode(_node).queueWithdrawals(_strategy, _nodeShares);
                }

                if (_pendingWithdrawalRequests <= _minPendingWithdrawalRequestAmount) {
                    batch[_queuedIdBefore] = queuedId;
                    return true;
                }
            }
        }

        totalQueuedWithdrawals -= _pendingWithdrawalRequests;
        batch[_queuedIdBefore] = queuedId;

        return false;
    }

    function completeQueuedWithdrawals() external {

        uint256 _completedId = completedId;
        uint256 _queuedId = batch[_completedId];
        if (_completedId == _queuedId) revert NoQueuedWithdrawals();

        for (; _completedId < _queuedId; ++_completedId) {

            queuedWithdrawals[_completedId].completed = true;

            QueuedWithdrawal memory _queuedWithdrawal = queuedWithdrawals[_completedId];

            // @todo redundant check - will fail on `completeQueuedWithdrawals` if not ready
            IStrategy[] memory _strategies = new IStrategy[](1);
            _strategies[0] = IStrategy(_queuedWithdrawal.strategy);
            uint256 _withdrawalDelay = delegationManager.getWithdrawalDelay(_strategies);
            if (block.number < _queuedWithdrawal.startBlock + _withdrawalDelay) revert NotReady();
            //

            uint256[] memory _middlewareTimesIndexes = new uint256[](1);
            _middlewareTimesIndexes[0] = 0;

            ITokenStakingNode(_queuedWithdrawal.node).completeQueuedWithdrawals(
                _queuedWithdrawal.nonce,
                _queuedWithdrawal.startBlock,
                _queuedWithdrawal.shares,
                IStrategy(_queuedWithdrawal.strategy),
                _middlewareTimesIndexes,
                true // updateTokenStakingNodesBalances
            );
        }

        completedId = _completedId;
    }

    // @todo - check how much to re-invest
    function processPrincipalWithdrawals() external {

        uint256 _completedId = completedId;
        uint256 _processedId = processedId;
        uint256 _batchLength = batch[_processedId];
        IYieldNestStrategyManager.WithdrawalAction[] memory _actions = new IYieldNestStrategyManager.WithdrawalAction[](_batchLength);
        for (; _processedId < _completedId; ++_processedId) {
            QueuedWithdrawal memory _queuedWithdrawal = queuedWithdrawals[_processedId];
            _actions[_processedId] = IYieldNestStrategyManager.WithdrawalAction({
                nodeId: ITokenStakingNode(_queuedWithdrawal.node).nodeId(),
                amountToReinvest: 0,
                amountToQueue: _queuedWithdrawal.shares,
                asset: address(IStrategy(_queuedWithdrawal.strategy).underlyingToken()) // @todo if steth/oeth ?
            });
        }

        processedId = _processedId;

        ynStrategyManager.processPrincipalWithdrawals(_actions);
    }

    //
    // Management functions
    //

    // @todo - add setter to minShares mapping
    // function updateMinNodeShares(uint256 _minNodeShares) external onlyOwner {
    //     if (_minNodeShares == 0) revert InvalidInput();
    //     minNodeShares = _minNodeShares;
    //     emit MinNodeSharesUpdated(_minNodeShares);
    // }

    function updateMinPendingWithdrawalRequestAmount(uint256 _minPendingWithdrawalRequestAmount) external onlyOwner {
        if (_minPendingWithdrawalRequestAmount == 0) revert InvalidInput();
        minPendingWithdrawalRequestAmount = _minPendingWithdrawalRequestAmount;
        emit MinPendingWithdrawalRequestAmountUpdated(_minPendingWithdrawalRequestAmount);
    }

    //
    // Private functions
    //

    // // @todo - here -- there's some problem with the conversion
    // function _unitToShares(uint256 _amount, IERC20 _asset, IStrategy _strategy) private view returns (uint256) {
    //     _amount = assetRegistry.convertFromUnitOfAccount(_asset, _amount);
    //     return _strategy.underlyingToSharesView(_amount);
    // }

    function _sharesToUnit(uint256 _shares, IERC20 _asset, IStrategy _strategy) private view returns (uint256) {
        uint256 _amount = _strategy.sharesToUnderlyingView(_shares);
        return assetRegistry.convertToUnitOfAccount(_asset, _amount);
    }

    //
    // Errors
    //

    error InvalidInput();
    error PendingWithdrawalRequestsTooLow();
    error NoQueuedWithdrawals();
    error NotReady();

    //
    // Events
    //

    event MinNodeSharesUpdated(uint256 minNodeShares);
    event MinPendingWithdrawalRequestAmountUpdated(uint256 minPendingWithdrawalRequestAmount);
}