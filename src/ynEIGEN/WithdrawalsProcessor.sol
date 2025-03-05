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

    // @custom:deprecated use `getTotalQueuedWithdrawals()` instead.
    uint256 public totalQueuedWithdrawals;

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
        uint256 availableAmount = redemptionAssetsVault.availableRedemptionAssets() + getTotalQueuedWithdrawals();

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
        uint256 availableAmount = redemptionAssetsVault.availableRedemptionAssets() + getTotalQueuedWithdrawals();
        if (pendingAmount <= availableAmount) {
            revert CurrentAvailableAmountIsSufficient();
        }
         deficitAmount = pendingAmount - availableAmount;
        if (deficitAmount < minPendingWithdrawalRequestAmount) {
            revert PendingWithdrawalRequestsTooLow();
        }
    }

    /// @notice Gets the total queued withdrawals in unit account
    /// @dev Replaces `totalQueuedWithdrawals` which was prone to be unsynced due to slashing.
    function getTotalQueuedWithdrawals() public view returns (uint256 _totalQueuedWithdrawals) {
        ITokenStakingNode[] memory _nodes = tokenStakingNodesManager.getAllNodes();
        IERC20[] memory _assets = assetRegistry.getAssets();

        for (uint256 i = 0; i < _assets.length; ++i) {
            IERC20 _asset = _assets[i];
            IStrategy _strategy = ynStrategyManager.strategies(_asset);

            for (uint256 j = 0; j < _nodes.length; ++j) {
                ITokenStakingNode _node = _nodes[j];
                (uint256 _queuedWithdrawals, uint256 _withdrawn) = _node.getQueuedSharesAndWithdrawn(_strategy, _asset);
                _totalQueuedWithdrawals += _sharesToUnit(_queuedWithdrawals, _asset, _strategy) + _withdrawn;
            }
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
                uint256 _balance = _stakedAssetBalance(_assets[i]);
                if (_balance > _highestBalance) {
                    _highestBalance = _balance;
                    _asset = _assets[i];
                }
            }
        }

        IStrategy _strategy = ynStrategyManager.strategies(_asset);
        _nodes = tokenStakingNodesManager.getAllNodes();
        uint256 _nodesLength = _nodes.length;
        uint256 _minNodeShares = type(uint256).max;
        uint256[] memory _nodesShares = new uint256[](_nodesLength);
        uint256[] memory _nodesWithdrawableShares = new uint256[](_nodesLength);
        IStrategy[] memory _singleStrategy = new IStrategy[](1);
        _singleStrategy[0] = _strategy;

        // get all nodes and their shares
        {
            // populate node shares and find the minimum balance
            for (uint256 i = 0; i < _nodesLength; ++i) {
                ITokenStakingNode _node = _nodes[i];

                (uint256[] memory _singleWithdrawableShares, uint256[] memory _singleDepositShares) = delegationManager.getWithdrawableShares(address(_node), _singleStrategy);

                uint256 _withdrawableShares = _singleWithdrawableShares[0];

                _nodesShares[i] = _singleDepositShares[0];
                _nodesWithdrawableShares[i] = _withdrawableShares;

                if (_withdrawableShares < _minNodeShares) {
                    _minNodeShares = _withdrawableShares;
                }
            }
        }

        // calculate deposit amounts for each node
        {
            _shares = new uint256[](_nodesLength);
            uint256 _pendingWithdrawalRequestsInShares = _unitToShares(getPendingWithdrawalRequests(), _asset, _strategy);

            // first pass: equalize all nodes to the minimum balance
            for (uint256 i = 0; i < _nodesLength && _pendingWithdrawalRequestsInShares > 0; ++i) {
                if (_nodesWithdrawableShares[i] > _minNodeShares) {
                    uint256 _availableToWithdraw = _nodesWithdrawableShares[i] - _minNodeShares;
                    uint256 _toWithdraw = _availableToWithdraw < _pendingWithdrawalRequestsInShares ? _availableToWithdraw : _pendingWithdrawalRequestsInShares;
                    _shares[i] = _toWithdraw;
                    _pendingWithdrawalRequestsInShares -= _toWithdraw;
                }
            }

            uint256[] memory _singleWithdrawableShares = new uint256[](1);

            // second pass: 
            // - withdraw evenly from all nodes if there is still more to withdraw 
            // - convert withdrawable shares to deposit shares.
            uint256 _equalWithdrawal = _pendingWithdrawalRequestsInShares / _nodesLength + 1;
            for (uint256 i = 0; i < _nodesLength; ++i) {
                _shares[i] = _equalWithdrawal + MIN_DELTA > _nodesWithdrawableShares[i] ? _nodesWithdrawableShares[i] : _equalWithdrawal;

                _singleWithdrawableShares[0] = _shares[i];

                _shares[i] = delegationManager.convertToDepositShares(address(_nodes[i]), _singleStrategy, _singleWithdrawableShares)[0];
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

        uint256 _pendingWithdrawalRequests = getPendingWithdrawalRequests(); // NOTE: reverts if too low
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
                (IDelegationManagerTypes.Withdrawal memory _queuedWithdrawal,) = delegationManager.getQueuedWithdrawal(_fullWithdrawalRoots[0]);

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
                _ids.queued = _queuedId;
                return true;
            }
        }

        _pendingWithdrawalRequests = _sharesToUnit(_pendingWithdrawalRequestsInShares, _asset, _strategy);

        if (_pendingWithdrawalRequests < _toBeQueued) {
            batch[_ids.queued] = _queuedId;
            _ids.queued = _queuedId;
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
            ITokenStakingNode(queuedWithdrawal_.node).completeQueuedWithdrawals(
                _withdrawal,
                true // updateTokenStakingNodesBalances
            );
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

        address _asset;
        address _strategy;
        uint256 _totalWithdrawn;
        uint256 _tokenIdToFinalize;
        uint256 _processedIdAtStart = _processedId;
        for (uint256 i = 0; _processedId < _processedIdAtStart + _batchLength; ++i) {
            QueuedWithdrawal memory queuedWithdrawal_ = _queuedWithdrawals[_processedId++];

            if (_asset == address(0)) {
                _strategy = queuedWithdrawal_.strategy;
                _asset = _underlyingTokenForStrategy(IStrategy(_strategy));
            }

            uint256 _queuedAmountInUnit = _sharesToUnit(queuedWithdrawal_.shares, IERC20(_asset), IStrategy(_strategy));
            _totalWithdrawn += _queuedAmountInUnit;

            _actions[i] = IYieldNestStrategyManager.WithdrawalAction({
                nodeId: ITokenStakingNode(queuedWithdrawal_.node).nodeId(),
                amountToReinvest: 0,
                amountToQueue: assetRegistry.convertFromUnitOfAccount(IERC20(_asset), _queuedAmountInUnit),
                asset: _asset
            });

            if (_tokenIdToFinalize == 0) _tokenIdToFinalize = queuedWithdrawal_.tokenIdToFinalize;
        }

        if (_tokenIdToFinalize == 0) revert SanityCheck();

        _ids.processed = _processedId;

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

    //
    // private functions
    //
    function _stakedAssetBalance(IERC20 _asset) private view returns (uint256 _stakedBalance) {
        ITokenStakingNode[] memory _nodesArray = tokenStakingNodesManager.getAllNodes();
        IStrategy _strategy = ynStrategyManager.strategies(_asset);
        uint256 _nodesLength = _nodesArray.length;
        uint256 _stakedShares;
        IStrategy[] memory _singleStrategy = new IStrategy[](1);
        _singleStrategy[0] = _strategy;

        for (uint256 i = 0; i < _nodesLength; ++i) {
            (uint256[] memory _singleWithdrawableShares,) = delegationManager.getWithdrawableShares(address(_nodesArray[i]), _singleStrategy);
            _stakedShares += _singleWithdrawableShares[0];
        }

        _stakedBalance = _sharesToUnit(_stakedShares, _asset, _strategy);
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

}
