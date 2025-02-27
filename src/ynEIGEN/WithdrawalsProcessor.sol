// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {AccessControlUpgradeable} from
    "lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {Initializable} from "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";

import {IDelegationManager, IDelegationManagerTypes} from "lib/eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategy} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";

import {IwstETH} from "../external/lido/IwstETH.sol";

import {IWithdrawalQueueManager} from "../interfaces/IWithdrawalQueueManager.sol";
import {ITokenStakingNodesManager} from "../interfaces/ITokenStakingNodesManager.sol";
import {ITokenStakingNode} from "../interfaces/ITokenStakingNode.sol";
import {IAssetRegistry} from "../interfaces/IAssetRegistry.sol";
import {IYieldNestStrategyManager} from "../interfaces/IYieldNestStrategyManager.sol";
import {IynEigen} from "../interfaces/IynEigen.sol";
import {IRedemptionAssetsVault} from "../interfaces/IRedemptionAssetsVault.sol";
import {IWrapper} from "../interfaces/IWrapper.sol";
import {IWithdrawalsProcessor} from "../interfaces/IWithdrawalsProcessor.sol";

contract WithdrawalsProcessor is IWithdrawalsProcessor, Initializable, AccessControlUpgradeable {

    uint256 public totalQueuedWithdrawals; // denominated in unit account

    // minimum amount of pending withdrawal requests to be queued
    uint256 public minPendingWithdrawalRequestAmount; // denominated in unit account

    IDs private _ids;

    mapping(uint256 id => QueuedWithdrawal) private _queuedWithdrawals;
    mapping(uint256 fromId => uint256 toId) public batch;

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
    IERC20 public immutable STETH;
    IwstETH public immutable WSTETH;
    IERC20 public immutable OETH;
    IERC4626 public immutable WOETH;

    // used to prevent rounding errors
    uint256 public constant MIN_DELTA = 1000;

    // roles
    bytes32 public constant KEEPER_ROLE = keccak256("KEEPER_ROLE");

    /**
     * @notice The role that can update the buffer factor.
     */
    bytes32 public constant BUFFER_FACTOR_UPDATER_ROLE = keccak256("BUFFER_FACTOR_UPDATER_ROLE");

    /**
     * @notice The buffer factor used to withdraw more than the pending withdrawal requests to account for slashing.
     * @dev It is denominated in ether (1e18).
     * @dev If the pending withdrawal requests are 100 ether, and the buffer factor is 1.1 ether, then the amount to withdraw is 110 ether.
     */
    uint256 public bufferFactor;

    /**
     * @notice The amount of shares withdrawn upon completion of a queued withdrawal.
     */
    mapping(uint256 => uint256) public withdrawnAtCompletion;

    /**
     * @notice The amount of unbuffered withdrawal requests in a batch.
     * @dev Keeps track of the requested withdrawal amount in a batch before the buffer factor is applied.
     * @dev It is used to calculate whether more than requested was withdrawn and to reinvest the difference.
     */
    mapping(uint256 => uint256) public unbufferedRequestAmountInBatch;

    /**
     * @notice The amount of queued withdrawal requests in a batch.
     * @dev Keeps track of the requested withdrawal amount in a batch after the buffer factor is applied.
     * @dev It is used to prevent accounting issues with totalQueuedWithdrawals in the event of slashing.
     */
    mapping(uint256 => uint256) public queuedWithdrawalAmountInBatch;

    //
    // Constructor
    //
    constructor(
        address _withdrawalQueueManager,
        address _tokenStakingNodesManager,
        address _assetRegistry,
        address _ynStrategyManager,
        address _delegationManager,
        address _yneigen,
        address _redemptionAssetsVault,
        address _wrapper,
        address _steth,
        address _wsteth,
        address _oeth,
        address _woeth
    ) {
        if (
            _withdrawalQueueManager == address(0) || _tokenStakingNodesManager == address(0)
                || _assetRegistry == address(0) || _ynStrategyManager == address(0) || _delegationManager == address(0)
                || _yneigen == address(0) || _redemptionAssetsVault == address(0) || _wrapper == address(0)
        ) revert InvalidInput();

        withdrawalQueueManager = IWithdrawalQueueManager(_withdrawalQueueManager);
        tokenStakingNodesManager = ITokenStakingNodesManager(_tokenStakingNodesManager);
        assetRegistry = IAssetRegistry(_assetRegistry);
        ynStrategyManager = IYieldNestStrategyManager(_ynStrategyManager);
        delegationManager = IDelegationManager(_delegationManager);
        yneigen = IynEigen(_yneigen);
        redemptionAssetsVault = IRedemptionAssetsVault(_redemptionAssetsVault);
        wrapper = IWrapper(_wrapper);

        STETH = IERC20(_steth);
        WSTETH = IwstETH(_wsteth);
        OETH = IERC20(_oeth);
        WOETH = IERC4626(_woeth);
    }

    function initialize(address _owner, address _keeper) public initializer {
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, _owner);
        _grantRole(KEEPER_ROLE, _keeper);

        minPendingWithdrawalRequestAmount = 0.1 ether;
    }

    /**
     * @notice Initializes the contract.
     * @param _bufferFactorUpdater The address of the buffer factor updater.
     * @param _bufferFactor The buffer factor.
     */
    function initializeV2(address _bufferFactorUpdater, uint256 _bufferFactor) public reinitializer(2) {
        _grantRole(BUFFER_FACTOR_UPDATER_ROLE, _bufferFactorUpdater);

        _updateBufferFactor(_bufferFactor);
    }

    //
    // view functions
    //

    /// @notice IDs of the queued, completed, and processed withdrawals, used for internal accounting
    /// @return The IDs
    function ids() external view returns (IDs memory) {
        return _ids;
    }

    /// @notice Gets the queued withdrawal at the given ID
    /// @param _id The ID of the queued withdrawal
    /// @return The queued withdrawal
    function queuedWithdrawals(
        uint256 _id
    ) external view returns (QueuedWithdrawal memory) {
        return _queuedWithdrawals[_id];
    }

    /// @notice Checks if withdrawals should be queued
    /// @dev returns true if there is not enough redemption assets to cover the pending withdrawals considering the minPendingWithdrawalRequestAmount
    /// @return True if withdrawals should be queued, false otherwise
    function shouldQueueWithdrawals() external view returns (bool) {
        uint256 pendingAmount = withdrawalQueueManager.pendingRequestedRedemptionAmount();
        uint256 availableAmount = redemptionAssetsVault.availableRedemptionAssets() + totalQueuedWithdrawals;

        if (pendingAmount <= availableAmount) {
            return false;
        }
        uint256 deficitAmount = pendingAmount - availableAmount;

        return deficitAmount >= minPendingWithdrawalRequestAmount;
    }

    /// @notice Checks if queued withdrawals should be completed
    /// @return True if queued withdrawals should be completed, false otherwise
    function shouldCompleteQueuedWithdrawals() external view returns (bool) {
        uint256 _queuedId = _ids.queued;
        uint256 _completedId = _ids.completed;
        if (_queuedId == _completedId) return false;

        for (; _completedId < _queuedId; ++_completedId) {
            QueuedWithdrawal memory _queuedWithdrawal = _queuedWithdrawals[_completedId];

            IStrategy[] memory _strategies = new IStrategy[](1);
            _strategies[0] = IStrategy(_queuedWithdrawal.strategy);
            uint256 _withdrawalDelay = delegationManager.minWithdrawalDelayBlocks();
            if (block.number >= _queuedWithdrawal.startBlock + _withdrawalDelay) {
                return true;
            }
        }

        return false;
    }

    /// @notice Checks if principal withdrawals should be processed
    /// @return True if principal withdrawals should be processed, false otherwise
    function shouldProcessPrincipalWithdrawals() external view returns (bool) {
        return _ids.completed != _ids.processed;
    }

    /// @notice Gets the total pending withdrawal requests
    /// @return deficitAmount The total pending withdrawal requests
    function getPendingWithdrawalRequests() public view returns (uint256 deficitAmount) {
        uint256 pendingAmount = withdrawalQueueManager.pendingRequestedRedemptionAmount();
        uint256 availableAmount = redemptionAssetsVault.availableRedemptionAssets() + totalQueuedWithdrawals;
        if (pendingAmount <= availableAmount) {
            revert CurrentAvailableAmountIsSufficient();
        }
        deficitAmount = pendingAmount - availableAmount;
        if (deficitAmount < minPendingWithdrawalRequestAmount) {
            revert PendingWithdrawalRequestsTooLow();
        }
    }

    /// @notice Gets the arguments for `queueWithdrawals`
    /// @param _asset The asset to withdraw - the asset with the highest balance
    /// @param _nodes The list of nodes to withdraw from
    /// @param _shares The share amounts to withdraw from each node to achieve balanced distribution
    function getQueueWithdrawalsArgs()
        external
        view
        returns (IERC20 _asset, ITokenStakingNode[] memory _nodes, uint256[] memory _shares)
    {
        // get `_asset` with the highest balance
        {
            IERC20[] memory _assets = assetRegistry.getAssets();

            uint256 _highestBalance;
            uint256 _assetsLength = _assets.length;
            for (uint256 i = 0; i < _assetsLength; ++i) {
                uint256 _stakedBalance = _stakedBalanceForStrategy(_assets[i]);
                if (_stakedBalance > _highestBalance) {
                    _highestBalance = _stakedBalance;
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

                if (_nodeShares < _minNodeShares) _minNodeShares = _nodeShares;
            }
        }

        // calculate withdrawal amounts for each node
        {
            _shares = new uint256[](_nodesLength);
            uint256 _pendingWithdrawalRequests = bufferFactor * getPendingWithdrawalRequests() / 1 ether;
            uint256 _pendingWithdrawalRequestsInShares = 
                _unitToShares(_pendingWithdrawalRequests, _asset, _strategy);

            // first pass: equalize all nodes to the minimum balance
            for (uint256 i = 0; i < _nodesLength && _pendingWithdrawalRequestsInShares > 0; ++i) {
                if (_nodesShares[i] > _minNodeShares) {
                    uint256 _availableToWithdraw = _nodesShares[i] - _minNodeShares;
                    uint256 _toWithdraw = _availableToWithdraw < _pendingWithdrawalRequestsInShares
                        ? _availableToWithdraw
                        : _pendingWithdrawalRequestsInShares;
                    _shares[i] = _toWithdraw;
                    _pendingWithdrawalRequestsInShares -= _toWithdraw;
                }
            }

            // second pass: withdraw evenly from all nodes if there is still more to withdraw
                uint256 _equalWithdrawal = _pendingWithdrawalRequestsInShares / _nodesLength + 1;
                for (uint256 i = 0; i < _nodesLength; ++i) {
                    _shares[i] = _equalWithdrawal + MIN_DELTA > _nodesShares[i] ? _nodesShares[i] : _equalWithdrawal;
                }
        }
    }

    //
    // mutative functions
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
    ) external onlyRole(KEEPER_ROLE) returns (bool) {
        uint256 _nodesLength = _nodes.length;
        if (_nodesLength != _amounts.length) revert InvalidInput();

        uint256 _pendingWithdrawalRequestsWithoutBuffer = getPendingWithdrawalRequests(); // NOTE: reverts if too low
        uint256 _pendingWithdrawalRequests = bufferFactor * _pendingWithdrawalRequestsWithoutBuffer / 1 ether;
        uint256 _toBeQueued = _pendingWithdrawalRequests;

        IStrategy _strategy = ynStrategyManager.strategies(_asset);
        if (_strategy == IStrategy(address(0))) revert InvalidInput();

        uint256 _queuedId = _ids.queued;
        uint256 _pendingWithdrawalRequestsInShares = _unitToShares(_pendingWithdrawalRequests, _asset, _strategy);
        for (uint256 j = 0; j < _nodesLength; ++j) {
            uint256 _toWithdraw = _amounts[j];
            if (_toWithdraw > 0) {
                _toWithdraw > _pendingWithdrawalRequestsInShares
                    ? _pendingWithdrawalRequestsInShares = 0
                    : _pendingWithdrawalRequestsInShares -= _toWithdraw;

                address _node = address(_nodes[j]);
                
                bytes32[] memory _fullWithdrawalRoots = ITokenStakingNode(_node).queueWithdrawals(_strategy, _toWithdraw);
                IDelegationManagerTypes.Withdrawal memory _queuedWithdrawal = delegationManager.getQueuedWithdrawal(_fullWithdrawalRoots[0]);

                _queuedWithdrawals[_queuedId++] = QueuedWithdrawal({
                    node: _node,
                    strategy: address(_queuedWithdrawal.strategies[0]),
                    nonce: _queuedWithdrawal.nonce,
                    shares: _queuedWithdrawal.scaledShares[0],
                    tokenIdToFinalize: withdrawalQueueManager._tokenIdCounter(),
                    startBlock: _queuedWithdrawal.startBlock,
                    completed: false,
                    delegatedTo: _queuedWithdrawal.delegatedTo
                });
            }

            if (_pendingWithdrawalRequestsInShares == 0) {
                batch[_ids.queued] = _queuedId;
                unbufferedRequestAmountInBatch[_ids.queued] = _pendingWithdrawalRequestsWithoutBuffer;
                queuedWithdrawalAmountInBatch[_ids.queued] = _toBeQueued;
                _ids.queued = _queuedId;
                totalQueuedWithdrawals += _toBeQueued;
                return true;
            }
        }

        _pendingWithdrawalRequests = _sharesToUnit(_pendingWithdrawalRequestsInShares, _asset, _strategy);

        if (_pendingWithdrawalRequests < _toBeQueued) {
            batch[_ids.queued] = _queuedId;
            unbufferedRequestAmountInBatch[_ids.queued] = _pendingWithdrawalRequestsWithoutBuffer;
            queuedWithdrawalAmountInBatch[_ids.queued] = _toBeQueued - _pendingWithdrawalRequests;
            _ids.queued = _queuedId;
            totalQueuedWithdrawals += _toBeQueued - _pendingWithdrawalRequests;
        }

        return false;
    }

    /// @notice Completes queued withdrawals
    /// @dev Completes the queued withdrawals in a batch
    function completeQueuedWithdrawals() external onlyRole(KEEPER_ROLE) {
        uint256 _completedId = _ids.completed;
        uint256 _queuedId = batch[_completedId];
        if (_completedId == _queuedId) revert NoQueuedWithdrawals();

        for (; _completedId < _queuedId; ++_completedId) {
            _queuedWithdrawals[_completedId].completed = true;

            QueuedWithdrawal memory queuedWithdrawal_ = _queuedWithdrawals[_completedId];

            IStrategy[] memory _strategies = new IStrategy[](1);
            _strategies[0] = IStrategy(queuedWithdrawal_.strategy);

            uint256[] memory _shares = new uint256[](1);
            _shares[0] = queuedWithdrawal_.shares;

            IDelegationManagerTypes.Withdrawal memory _withdrawal = IDelegationManagerTypes.Withdrawal({
                staker: address(queuedWithdrawal_.node),
                delegatedTo: queuedWithdrawal_.delegatedTo,
                withdrawer: address(queuedWithdrawal_.node),
                nonce: queuedWithdrawal_.nonce,
                startBlock: queuedWithdrawal_.startBlock,
                strategies: _strategies,
                scaledShares: _shares
            });

            ITokenStakingNode _node = ITokenStakingNode(queuedWithdrawal_.node);
            uint256 _queuedSharesBefore = _node.getQueuedShares(_strategies[0]);
            _node.completeQueuedWithdrawals(
                _withdrawal,
                true // updateTokenStakingNodesBalances
            );
            withdrawnAtCompletion[_completedId] = _queuedSharesBefore - _node.getQueuedShares(_strategies[0]);
        }

        _ids.completed = _completedId;
    }


    /// @notice Processes principal withdrawals
    /// @dev Must be called immediately after `completeQueuedWithdrawals` so that the shares value does't change
    function processPrincipalWithdrawals() external onlyRole(KEEPER_ROLE) {
        uint256 _completedId = _ids.completed;
        uint256 _processedId = _ids.processed;
        if (_completedId == _processedId) revert NothingToProcess();

        uint256 _batchLength = batch[_processedId] - _processedId;
        IYieldNestStrategyManager.WithdrawalAction[] memory _actions =
            new IYieldNestStrategyManager.WithdrawalAction[](_batchLength);
        uint256 _queuedWithdrawalAmountInBatch = queuedWithdrawalAmountInBatch[_processedId];
        uint256 _unbufferedRequestAmountInBatch = unbufferedRequestAmountInBatch[_processedId];

        // Delete the values for gas optimization.
        delete queuedWithdrawalAmountInBatch[_processedId];
        delete unbufferedRequestAmountInBatch[_processedId];

        address _asset;
        address _strategy;
        uint256 _totalWithdrawn;
        uint256 _tokenIdToFinalize;
        uint256 _processedIdAtStart = _processedId;
        for (uint256 i = 0; _processedId < _processedIdAtStart + _batchLength; ++i) {
            uint256 _withdrawnAtCompletion = withdrawnAtCompletion[_processedId];

            // Delete the value for gas optimization.
            delete withdrawnAtCompletion[_processedId];

            QueuedWithdrawal memory queuedWithdrawal_ = _queuedWithdrawals[_processedId++];

            if (_asset == address(0)) {
                _strategy = queuedWithdrawal_.strategy;
                _asset = _underlyingTokenForStrategy(IStrategy(_strategy));
            }

            uint256 _queuedAmountInUnit = _sharesToUnit(_withdrawnAtCompletion, IERC20(_asset), IStrategy(_strategy));
            _totalWithdrawn += _queuedAmountInUnit;

            // Reinvest the difference between the withdrawn amount and the unbuffered request amount.
            uint256 _amountToReinvest = _queuedAmountInUnit > _unbufferedRequestAmountInBatch ? _queuedAmountInUnit - _unbufferedRequestAmountInBatch : 0;

            if (_amountToReinvest > 0) {
                _amountToReinvest = assetRegistry.convertFromUnitOfAccount(IERC20(_asset), _amountToReinvest);
            }

            _actions[i] = IYieldNestStrategyManager.WithdrawalAction({
                nodeId: ITokenStakingNode(queuedWithdrawal_.node).nodeId(),
                amountToReinvest: _amountToReinvest,
                amountToQueue: assetRegistry.convertFromUnitOfAccount(IERC20(_asset), _queuedAmountInUnit) - _amountToReinvest,
                asset: _asset
            });

            if (_tokenIdToFinalize == 0) _tokenIdToFinalize = queuedWithdrawal_.tokenIdToFinalize;
        }

        if (_tokenIdToFinalize == 0) revert SanityCheck();

        if (_queuedWithdrawalAmountInBatch != 0) {
            _totalWithdrawn += _queuedWithdrawalAmountInBatch;
        }

        _ids.processed = _processedId;

        uint256 _totalQueuedWithdrawals = totalQueuedWithdrawals;
        totalQueuedWithdrawals =
            _totalWithdrawn > _totalQueuedWithdrawals ? 0 : _totalQueuedWithdrawals - _totalWithdrawn;

        ynStrategyManager.processPrincipalWithdrawals(_actions);

        if (withdrawalQueueManager.lastFinalizedIndex() < _tokenIdToFinalize) {
            withdrawalQueueManager.finalizeRequestsUpToIndex(_tokenIdToFinalize);
        }
    }

    //
    // management functions
    //

    /// @notice Updates the minimum pending withdrawal request amount
    /// @param _minPendingWithdrawalRequestAmount The new minimum pending withdrawal request amount
    function updateMinPendingWithdrawalRequestAmount(
        uint256 _minPendingWithdrawalRequestAmount
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_minPendingWithdrawalRequestAmount == 0) revert InvalidInput();
        minPendingWithdrawalRequestAmount = _minPendingWithdrawalRequestAmount;
        emit MinPendingWithdrawalRequestAmountUpdated(_minPendingWithdrawalRequestAmount);
    }

    /**
     * @notice Updates the buffer factor.
     * @param _bufferFactor The new buffer factor.
     */
    function updateBufferFactor(uint256 _bufferFactor) external onlyRole(BUFFER_FACTOR_UPDATER_ROLE) {
        _updateBufferFactor(_bufferFactor);
    }

    //
    // private functions
    //
    function _stakedBalanceForStrategy(
        IERC20 _asset
    ) public view returns (uint256 _stakedBalance) {
        ITokenStakingNode[] memory _nodesArray = tokenStakingNodesManager.getAllNodes();
        IStrategy _strategy = ynStrategyManager.strategies(_asset);
        uint256 _nodesLength = _nodesArray.length;
        for (uint256 i = 0; i < _nodesLength; ++i) {
            _stakedBalance += _strategy.shares(address(_nodesArray[i]));
        }
    }

    function _underlyingTokenForStrategy(
        IStrategy _strategy
    ) private view returns (address) {
        address _token = address(_strategy.underlyingToken());
        if (_token == address(STETH)) return address(WSTETH);
        if (_token == address(OETH)) return address(WOETH);
        return _token;
    }

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
                _asset,
                address(_asset) == address(WSTETH) ? WSTETH.getWstETHByStETH(_amount) : WOETH.previewDeposit(_amount)
            )
            : assetRegistry.convertToUnitOfAccount(_asset, _amount);
    }

    function _updateBufferFactor(uint256 _bufferFactor) internal {
        // It must be greater than 1 ether to be effective, as it can only be used to increase the amount of withdrawable requests.
        if (_bufferFactor < 1 ether) {
            revert InvalidInput();
        }

        bufferFactor = _bufferFactor;

        emit BufferFactorUpdated(_bufferFactor);
    }
}
