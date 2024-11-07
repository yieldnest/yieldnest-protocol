// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";

import {IDelegationManager} from "@eigenlayer/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategy} from "@eigenlayer/src/contracts/interfaces/IStrategy.sol";

import {IWithdrawalQueueManager} from "../interfaces/IWithdrawalQueueManager.sol";
import {ITokenStakingNodesManager} from "../interfaces/ITokenStakingNodesManager.sol";
import {ITokenStakingNode} from "../interfaces/ITokenStakingNode.sol";
import {IAssetRegistry} from "../interfaces/IAssetRegistry.sol";
import {IYieldNestStrategyManager} from "../interfaces/IYieldNestStrategyManager.sol";

import "forge-std/console.sol";

// @todo - move to interfaces
interface IWSTETH {
    function getWstETHByStETH(uint256 _stETHAmount) external view returns (uint256);
}

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

    struct QueuedWithdrawalsVars {
        uint256 queuedId;
        uint256 assetsLength;
        uint256 nodesLength; 
        uint256 minNodeShares;
        uint96 maxNodeAllocation;
        uint8 nodeCursor;
    }

    // @todo - put ids in a struct
    uint256 public queuedId;
    uint256 public completedId;
    uint256 public processedId;

    uint256 public totalQueuedWithdrawals;

    uint256 public minNodeShares;
    uint256 public minPendingWithdrawalRequestAmount;

    // yieldnest
    IWithdrawalQueueManager public immutable withdrawalQueueManager;
    ITokenStakingNodesManager public immutable tokenStakingNodesManager;
    IAssetRegistry public immutable assetRegistry;
    IYieldNestStrategyManager public immutable ynStrategyManager;

    // eigenlayer
    IDelegationManager public immutable delegationManager;

    // assets
    IWSTETH private constant WSTETH = IWSTETH(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
    IERC4626 private constant WOETH = IERC4626(0xDcEe70654261AF21C44c093C300eD3Bb97b78192);

    // used to prevent rounding errors
    uint256 private constant MIN_DELTA = 1_000;

    mapping(uint256 id => QueuedWithdrawal) public queuedWithdrawals;
    mapping(uint256 fromId => uint256 toId) public batch;

    uint96 public maxNodeAllocation;
    uint8 public nodeCursor;

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

        minNodeShares = 1 ether;
        minPendingWithdrawalRequestAmount = 0.1 ether;
    }

    //
    // Processor functions
    //

    /// @notice Queues withdrawals
    /// @dev Reverts if the total pending withdrawal requests are below the minimum threshold
    /// @dev Skips nodes with shares below the minimum threshold
    /// @dev Tries to satisfy the pending withdrawal requests while prioritizing withdrawals in one asset
    /// @dev Saves the queued withdrawals together in a batch, to be completed in the next step (`completeQueuedWithdrawals`)
    /// @return True if all pending withdrawal requests were queued, false otherwise
    function queueWithdrawals() external onlyOwner returns (bool) {

        uint256 _pendingWithdrawalRequests = withdrawalQueueManager.pendingRequestedRedemptionAmount() - totalQueuedWithdrawals;
        if (_pendingWithdrawalRequests <= minPendingWithdrawalRequestAmount) revert PendingWithdrawalRequestsTooLow();

        if (_pendingWithdrawalRequests > maxNodeAllocation) {
            _pendingWithdrawalRequests = maxNodeAllocation;
        }

        uint256 _toBeQueued = _pendingWithdrawalRequests;

        ITokenStakingNode[] memory _nodes = tokenStakingNodesManager.getAllNodes();
        IERC20[] memory _assets = assetRegistry.getAssets();
        QueuedWithdrawalsVars memory vars = QueuedWithdrawalsVars({
            maxNodeAllocation: maxNodeAllocation,
            nodeCursor: nodeCursor,
            queuedId: queuedId,
            assetsLength: _assets.length,
            nodesLength: _nodes.length,
            minNodeShares: minNodeShares
        });

        for (uint256 i = 0; i < vars.assetsLength; ++i) {

            IStrategy _strategy = ynStrategyManager.strategies(_assets[i]);
            uint256 _pendingWithdrawalRequestsInShares = _unitToShares(_pendingWithdrawalRequests, _assets[i], _strategy);

            uint256 j = 0;
            for (j = 0; j < vars.nodesLength; ++j) {
                uint256 _withdrawnShares;

                uint256 nodeIndex = (j + vars.nodeCursor) % vars.nodesLength;

                address _node = address(_nodes[nodeIndex]);
                uint256 _nodeShares = _strategy.shares(_node);
                if (_nodeShares > _pendingWithdrawalRequestsInShares) {
                    _withdrawnShares =
                        (_nodeShares - _pendingWithdrawalRequestsInShares) < MIN_DELTA
                            ? _nodeShares
                            : _pendingWithdrawalRequestsInShares;
                    _pendingWithdrawalRequestsInShares = 0;
                } else if (_nodeShares > vars.minNodeShares) {
                    _withdrawnShares = _nodeShares;
                    _pendingWithdrawalRequestsInShares -= _nodeShares;
                }

                if (_withdrawnShares > 0) {
                    queuedWithdrawals[vars.queuedId++] = QueuedWithdrawal(
                        _node,
                        address(_strategy),
                        delegationManager.cumulativeWithdrawalsQueued(_node), // nonce
                        _withdrawnShares,
                        uint32(block.number), // startBlock
                        false // completed
                    );
                    ITokenStakingNode(_node).queueWithdrawals(_strategy, _withdrawnShares);
                }

                if (_pendingWithdrawalRequestsInShares == 0) {
                    batch[queuedId] = vars.queuedId;
                    queuedId = vars.queuedId;
                    totalQueuedWithdrawals += _toBeQueued;

                    vars.nodeCursor = uint8(j);
                    nodeCursor = vars.nodeCursor;

                    return true;
                }
            }

            vars.nodeCursor = uint8(j);
  

            _pendingWithdrawalRequests = _sharesToUnit(_pendingWithdrawalRequestsInShares, _assets[i], _strategy);
        }

        

        if (_pendingWithdrawalRequests < _toBeQueued) {
            batch[queuedId] = vars.queuedId;
            queuedId = vars.queuedId;
            totalQueuedWithdrawals += _toBeQueued - _pendingWithdrawalRequests;
        }

        nodeCursor = vars.nodeCursor;

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

    function _unitToShares(uint256 _amount, IERC20 _asset, IStrategy _strategy) private view returns (uint256) {
        return _strategy.underlyingToSharesView(
            (address(_asset) == address(WSTETH) || address(_asset) == address(WOETH))
                ? _amount
                : assetRegistry.convertFromUnitOfAccount(_asset, _amount)
            );
    }

    function _sharesToUnit(uint256 _shares, IERC20 _asset, IStrategy _strategy) private view returns (uint256) {
        uint256 _amount = _strategy.sharesToUnderlyingView(_shares);
        return (address(_asset) == address(WSTETH) || address(_asset) == address(WOETH))
            ? assetRegistry.convertToUnitOfAccount(
                _asset, address(_asset) == address(WSTETH) ? WSTETH.getWstETHByStETH(_amount) : WOETH.previewDeposit(_amount)
            )
            : assetRegistry.convertToUnitOfAccount(_asset, _amount);
    }

    function _min(uint256 a, uint256 b) private pure returns (uint256) {
        return a < b ? a : b;
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