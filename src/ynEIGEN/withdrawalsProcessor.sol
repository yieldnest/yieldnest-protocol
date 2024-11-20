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
import {IynEigen} from "../interfaces/IynEigen.sol";
import {IRedemptionAssetsVault} from "../interfaces/IRedemptionAssetsVault.sol";
import {IWrapper} from "../interfaces/IWrapper.sol";

import "forge-std/console.sol";

// @todo - move to interfaces
interface IWSTETH {
    function getWstETHByStETH(uint256 _stETHAmount) external view returns (uint256);
}

// @todo - change onlyOwner to role
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

    uint256 public minNodeShares;
    uint256 public minPendingWithdrawalRequestAmount;

    // yieldnest
    IWithdrawalQueueManager public immutable withdrawalQueueManager;
    ITokenStakingNodesManager public immutable tokenStakingNodesManager;
    IAssetRegistry public immutable assetRegistry;
    IYieldNestStrategyManager public immutable ynStrategyManager;
    IynEigen public immutable yneigen;
    IRedemptionAssetsVault public immutable redemptionAssetsVault;
    IWrapper public immutable wrapper;

    // eigenlayer
    IDelegationManager public immutable delegationManager;

    // assets
    IWSTETH private constant WSTETH = IWSTETH(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
    IERC4626 private constant WOETH = IERC4626(0xDcEe70654261AF21C44c093C300eD3Bb97b78192);

    // used to prevent rounding errors
    uint256 private constant MIN_DELTA = 1_000;

    mapping(uint256 id => QueuedWithdrawal) public queuedWithdrawals;
    mapping(uint256 fromId => uint256 toId) public batch;

    //
    // Constructor
    //

    constructor(
        address _owner,
        address _withdrawalQueueManager,
        address _tokenStakingNodesManager,
        address _assetRegistry,
        address _ynStrategyManager,
        address _delegationManager,
        address _yneigen,
        address _redemptionAssetsVault,
        address _wrapper
    ) Ownable(_owner) {
        if (
            _withdrawalQueueManager == address(0) ||
            _tokenStakingNodesManager == address(0) ||
            _assetRegistry == address(0) ||
            _ynStrategyManager == address(0) ||
            _delegationManager == address(0) ||
            _yneigen == address(0) ||
            _redemptionAssetsVault == address(0) ||
            _wrapper == address(0)
        ) revert InvalidInput();

        withdrawalQueueManager = IWithdrawalQueueManager(_withdrawalQueueManager);
        tokenStakingNodesManager = ITokenStakingNodesManager(_tokenStakingNodesManager);
        assetRegistry = IAssetRegistry(_assetRegistry);
        ynStrategyManager = IYieldNestStrategyManager(_ynStrategyManager);
        delegationManager = IDelegationManager(_delegationManager);
        yneigen = IynEigen(_yneigen);
        redemptionAssetsVault = IRedemptionAssetsVault(_redemptionAssetsVault);
        wrapper = IWrapper(_wrapper);

        minNodeShares = 1 ether;
        minPendingWithdrawalRequestAmount = 0.1 ether;
    }

    //
    // Processor functions - view
    //

    function shouldQueueWithdrawals() external view returns (bool) {
        return
            withdrawalQueueManager.pendingRequestedRedemptionAmount()
            - totalQueuedWithdrawals
            - redemptionAssetsVault.availableRedemptionAssets()
            > minPendingWithdrawalRequestAmount;
    }

    function getPendingWithdrawalRequests() public view returns (uint256 _pendingWithdrawalRequests) {
        _pendingWithdrawalRequests = withdrawalQueueManager.pendingRequestedRedemptionAmount()
            - totalQueuedWithdrawals
            - redemptionAssetsVault.availableRedemptionAssets();
        if (_pendingWithdrawalRequests <= minPendingWithdrawalRequestAmount) revert PendingWithdrawalRequestsTooLow();
    }

    /// @notice Gets the arguments for `queueWithdrawals`
    /// @param _asset The asset to withdraw: the asset with the highest balance
    /// @param _nodes The list of nodes to withdraw from
    /// @param _shares The share amounts to withdraw from each node to achieve balanced distribution
    function getQueueWithdrawalsArgs() external view returns (
        IERC20 _asset,
        ITokenStakingNode[] memory _nodes,
        uint256[] memory _shares
    ) {

        // get `_asset` with the highest balance
        {
            IERC20[] memory _assets = assetRegistry.getAssets();
            uint256[] memory _balances = yneigen.assetBalances(_assets);

            uint256 _highestBalance;
            uint256 _assetsLength = _assets.length;
            for (uint256 i = 0; i < _assetsLength; ++i) {
                if (_balances[i] > _highestBalance) {
                    _highestBalance = _balances[i];
                    _asset = _assets[i];
                }
            }
        }

        IStrategy _strategy = ynStrategyManager.strategies(_asset);
        ITokenStakingNode[] memory _nodesArray = tokenStakingNodesManager.getAllNodes();
        uint256 _nodesLength = _nodesArray.length;
        uint256 _minNodeShares = type(uint256).max;
        uint256[] memory _nodesShares = new uint256[](_nodesLength);

        // get all nodes and their shares
        {
            _nodes = new ITokenStakingNode[](_nodesLength);

            // populate node shares and find the minimum balance
            for (uint256 i = 0; i < _nodesLength; ++i) {
                ITokenStakingNode _node = _nodesArray[i];
                uint256 _nodeShares = _strategy.shares(address(_node));
                _nodesShares[i] = _nodeShares;
                _nodes[i] = _node;

                if (_nodeShares < _minNodeShares) {
                    _minNodeShares = _nodeShares;
                }
            }
        }

        // calculate withdrawal amounts for each node
        {
            _shares = new uint256[](_nodesLength);
            uint256 _pendingWithdrawalRequestsInShares = _unitToShares(getPendingWithdrawalRequests(), _asset, _strategy);

            // first pass: equalize all nodes to the minimum balance
            for (uint256 i = 0; i < _nodesLength && _pendingWithdrawalRequestsInShares > 0; ++i) {
                if (_nodesShares[i] > _minNodeShares) {
                    uint256 _availableToWithdraw = _nodesShares[i] - _minNodeShares;
                    uint256 _toWithdraw =
                        _availableToWithdraw < _pendingWithdrawalRequestsInShares
                            ? _availableToWithdraw
                            : _pendingWithdrawalRequestsInShares;
                    _shares[i] = _toWithdraw;
                    _pendingWithdrawalRequestsInShares -= _toWithdraw;
                }
            }

            // second pass: withdraw evenly from all nodes if there is still more to withdraw
            if (_pendingWithdrawalRequestsInShares > minPendingWithdrawalRequestAmount) { // NOTE: here we compare shares to unit... nbd?
                uint256 _equalWithdrawal = _pendingWithdrawalRequestsInShares / _nodesLength;
                for (uint256 i = 0; i < _nodesLength; ++i) {
                    _shares[i] += _equalWithdrawal;
                }
            }
        }
    }

    //
    // Processor functions - mutative
    //

    /// @notice Queues withdrawals
    /// @dev Reverts if the total pending withdrawal requests are below the minimum threshold
    /// @dev Saves the queued withdrawals together in a batch, to be completed in the next step (`completeQueuedWithdrawals`)
    /// @dev Before calling this function, call `getQueueWithdrawalsArgs()` to get the arguments
    /// @param _asset The asset to withdraw
    /// @param _nodes The list of nodes to withdraw from
    /// @param _amounts The share amounts to withdraw from each node
    /// @return True if all pending withdrawal requests were queued, false otherwise
    function queueWithdrawals(
        IERC20 _asset,
        ITokenStakingNode[] memory _nodes,
        uint256[] memory _amounts
    ) external onlyOwner returns (bool) {

        uint256 _nodesLength = _nodes.length;
        if (_nodesLength != _amounts.length) revert InvalidInput();

        uint256 _pendingWithdrawalRequests = getPendingWithdrawalRequests(); // NOTE: reverts if too low
        uint256 _toBeQueued = _pendingWithdrawalRequests;

        IStrategy _strategy = ynStrategyManager.strategies(_asset);
        if (_strategy == IStrategy(address(0))) revert InvalidInput();

        uint256 _queuedId = queuedId;
        uint256 _pendingWithdrawalRequestsInShares = _unitToShares(_pendingWithdrawalRequests, _asset, _strategy);
        for (uint256 j = 0; j < _nodesLength; ++j) {
            uint256 _toWithdraw = _amounts[j];
            if (_toWithdraw > 0) {
                _toWithdraw > _pendingWithdrawalRequestsInShares
                    ? _pendingWithdrawalRequestsInShares = 0
                    : _pendingWithdrawalRequestsInShares -= _toWithdraw;

                address _node = address(_nodes[j]);
                queuedWithdrawals[_queuedId++] = QueuedWithdrawal(
                    _node,
                    address(_strategy),
                    delegationManager.cumulativeWithdrawalsQueued(_node), // nonce
                    _toWithdraw,
                    uint32(block.number), // startBlock
                    false // completed
                );
                ITokenStakingNode(_node).queueWithdrawals(_strategy, _toWithdraw);
            }

            if (_pendingWithdrawalRequestsInShares == 0) {
                batch[queuedId] = _queuedId;
                queuedId = _queuedId;
                totalQueuedWithdrawals += _toBeQueued;
                return true;
            }
        }

        _pendingWithdrawalRequests = _sharesToUnit(_pendingWithdrawalRequestsInShares, _asset, _strategy);

        if (_pendingWithdrawalRequests < _toBeQueued) {
            batch[queuedId] = _queuedId;
            queuedId = _queuedId;
            totalQueuedWithdrawals += _toBeQueued - _pendingWithdrawalRequests;
        }

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

        // @todo - `--totalQueuedWithdrawals` somehow

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