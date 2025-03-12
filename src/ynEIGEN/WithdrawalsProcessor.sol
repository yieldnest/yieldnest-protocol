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

    /// @custom:deprecated use `getTotalQueuedWithdrawals()` instead.
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

    // ELIP-002 - EigenLayer Slashing Upgrade

    bytes32 public constant BUFFER_SETTER_ROLE = keccak256("BUFFER_SETTER_ROLE");

    /// @notice Multiplier applied to withdrawal amounts to account for potential slashing.
    /// @dev Value is in ether units. To withdraw 10% more, set buffer to 1.1 ether.
    uint256 public buffer;

    /// @notice Tracks the amount of requested amounts at each batch.
    /// @dev Used to determine how much to queue vs reinvest during principal withdrawals.
    mapping(uint256 => uint256) public pendingRequestsAtBatch;
    
    /// @notice Tracks the actual amount withdrawn at each completed withdrawal.
    /// @dev Used for the same purpose as `pendingRequestsAtBatch`.
    mapping(uint256 => uint256) public withdrawnAtCompletedWithdrawal;

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

    /// @notice Initializes the v2 version of the contract.
    /// @param _bufferSetter The address that will be granted the BUFFER_SETTER_ROLE.
    /// @param _buffer The buffer value.
    function initializeV2(address _bufferSetter, uint256 _buffer) public reinitializer(2) {
        _grantRole(BUFFER_SETTER_ROLE, _bufferSetter);

        _setBuffer(_buffer);
    }

    //
    // view functions
    //

    /// @notice Gets the buffer value.
    /// @dev Reverts if the buffer has not been set.
    /// @return The buffer value.
    function getBuffer() public view returns (uint256) {
        if (buffer == 0) {
            revert BufferNotSet();
        }

        return buffer;
    }

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
        return _getPendingWithdrawalRequests(getTotalQueuedWithdrawals());
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
                _totalQueuedWithdrawals += _sharesToUnit(_queuedWithdrawals, _asset, _strategy) + assetRegistry.convertToUnitOfAccount(_asset, _withdrawn);
            }
        }
    }

    /// @notice Gets the arguments for `queueWithdrawals`
    /// @return _args The arguments for `queueWithdrawals`
    function getQueueWithdrawalsArgs() external view returns (QueueWithdrawalsArgs memory _args) {
        // Step 1: Identify the asset with the highest unit balance.
        {
            IERC20[] memory _assets = assetRegistry.getAssets();

            uint256 _highestBalance;
            uint256 _assetsLength = _assets.length;
            for (uint256 i = 0; i < _assetsLength; ++i) {
                uint256 _stakedBalance = _stakedBalanceForStrategy(_assets[i]);
                if (_stakedBalance > _highestBalance) {
                    _highestBalance = _stakedBalance;
                    _args.asset = _assets[i];
                }
            }
        }

        IStrategy _strategy = ynStrategyManager.strategies(_args.asset);
        _args.nodes = tokenStakingNodesManager.getAllNodes();
        uint256 _nodesLength = _args.nodes.length;
        uint256 _minNodeShares = type(uint256).max;
        uint256[] memory _nodesShares = new uint256[](_nodesLength);
        IStrategy[] memory _singleStrategy = new IStrategy[](1);
        _singleStrategy[0] = _strategy;

        // Step 2: Iterate the nodes and extract the value of the node with the least amount staked in it.
        {
            for (uint256 i = 0; i < _nodesLength; ++i) {
                ITokenStakingNode _node = _args.nodes[i];

                (uint256[] memory _singleWithdrawableShares,) = delegationManager.getWithdrawableShares(address(_node), _singleStrategy);

                uint256 _withdrawableShares = _singleWithdrawableShares[0];

                _nodesShares[i] = _withdrawableShares;

                if (_withdrawableShares < _minNodeShares) {
                    _minNodeShares = _withdrawableShares;
                }
            }
        }

        // Step 3: Calculate how much to withdraw from each node.
        {
            _args.shares = new uint256[](_nodesLength);
            // Store the current amount of queued withdrawals in the return value.
            // This allows the queueWithdrawals function to use the already computed value to save some gas.
            _args.totalQueuedWithdrawals = getTotalQueuedWithdrawals();
            // Apply a buffer to the pending withdrawal requests.
            // This is helpful in case there is a slashing event after queuing the withdrawals.
            // This is beause on a slashing event, the withdrawn shares will be less.
            // Without the buffer, the withdrawn shares would not be enough for the users to claim.
            uint256 _pendingWithdrawalRequests = _applyBuffer(_getPendingWithdrawalRequests(_args.totalQueuedWithdrawals)) + MIN_DELTA;
            uint256 _pendingWithdrawalRequestsInShares = _unitToShares(_pendingWithdrawalRequests, _args.asset, _strategy);

            // Try to normalize the value each node has by withdrawing from the nodes that have more shares. 
            for (uint256 i = 0; i < _nodesLength && _pendingWithdrawalRequestsInShares > 0; ++i) {
                if (_nodesShares[i] > _minNodeShares) {
                    uint256 _availableToWithdraw = _nodesShares[i] - _minNodeShares;
                    uint256 _toWithdraw = _availableToWithdraw < _pendingWithdrawalRequestsInShares
                        ? _availableToWithdraw
                        : _pendingWithdrawalRequestsInShares;
                    _args.shares[i] = _toWithdraw;
                    _pendingWithdrawalRequestsInShares -= _toWithdraw;
                }
            }

            // Once the nodes have been normalized to a base value, distribute the remaining withdrawal requests evenly.
            uint256 _equalWithdrawal = _pendingWithdrawalRequestsInShares / _nodesLength + 1;
            for (uint256 i = 0; i < _nodesLength; ++i) {
                uint256 _nodeRemainingShares = _nodesShares[i] - _args.shares[i];

                if (_equalWithdrawal > _nodeRemainingShares) {
                    _args.shares[i] += _nodeRemainingShares;
                } else {
                    _args.shares[i] += _equalWithdrawal;
                }
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
    /// @param _args The arguments for `queueWithdrawals`
    /// @return True if all pending withdrawal requests were queued, false otherwise
    function queueWithdrawals(QueueWithdrawalsArgs memory _args) external onlyRole(KEEPER_ROLE) returns (bool) {
        uint256 _nodesLength = _args.nodes.length;
        if (_nodesLength != _args.shares.length) revert InvalidInput();

        uint256 _pendingWithdrawalRequestsNoBuffer = _getPendingWithdrawalRequests(_args.totalQueuedWithdrawals); // NOTE: reverts if too low
        uint256 _pendingWithdrawalRequests = _applyBuffer(_pendingWithdrawalRequestsNoBuffer);
        uint256 _toBeQueued = _pendingWithdrawalRequests;

        IStrategy[] memory _singleStrategy = new IStrategy[](1);
        IStrategy _strategy = ynStrategyManager.strategies(_args.asset);
        _singleStrategy[0] = _strategy;
        uint256[] memory _singleToWithdraw = new uint256[](1);
        if (_strategy == IStrategy(address(0))) revert InvalidInput();

        uint256 _queuedId = _ids.queued;

        // Stores how much was requested for this particular batch.
        // This is useful for the `processPrincipalWithdrawals` to calculate how much surplus was withdrawn in order to reinvest.
        pendingRequestsAtBatch[_queuedId] = _pendingWithdrawalRequestsNoBuffer;

        uint256 _pendingWithdrawalRequestsInShares = _unitToShares(_pendingWithdrawalRequests, _args.asset, _strategy);
        for (uint256 i = 0; i < _nodesLength; ++i) {
            uint256 _toWithdraw = _args.shares[i];
            _singleToWithdraw[0] = _toWithdraw;
            if (_toWithdraw > 0) {
                _toWithdraw > _pendingWithdrawalRequestsInShares
                    ? _pendingWithdrawalRequestsInShares = 0
                    : _pendingWithdrawalRequestsInShares -= _toWithdraw;

                address _node = address(_args.nodes[i]);
                uint256 _depositShares = delegationManager.convertToDepositShares(_node, _singleStrategy, _singleToWithdraw)[0];
                
                bytes32[] memory _fullWithdrawalRoots = ITokenStakingNode(_node).queueWithdrawals(_strategy, _depositShares);
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
                _ids.queued = _queuedId;
                return true;
            }
        }

        _pendingWithdrawalRequests = _sharesToUnit(_pendingWithdrawalRequestsInShares, _args.asset, _strategy);

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
            uint256 _totalSharesBefore = _strategies[0].totalShares();
            ITokenStakingNode(queuedWithdrawal_.node).completeQueuedWithdrawals(
                _withdrawal,
                true // updateTokenStakingNodesBalances
            ); 

            // Stores how many shares were withdrawn.
            // This is useful for the `processPrincipalWithdrawals` along `pendingRequestsAtBatch` to calculate if the amount withdrawn matches the amount requested.
            withdrawnAtCompletedWithdrawal[_completedId] = _totalSharesBefore - _strategies[0].totalShares();
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
        uint256 _tokenIdToFinalize;
        uint256 _processedIdAtStart = _processedId;
        // Adds a extra to the pending requests amount to avoid rounding errors and ensure that the redemption vault receives the same or more of what was requested
        uint256 _pendingRequestsAtBatch = pendingRequestsAtBatch[_processedIdAtStart] + MIN_DELTA;
        uint256 _accWithdrawnUnits;
        for (uint256 i = 0; _processedId < _processedIdAtStart + _batchLength; ++i) {
            uint256 _withdrawnAtCompletedWithdrawal = withdrawnAtCompletedWithdrawal[_processedId];

            QueuedWithdrawal memory queuedWithdrawal_ = _queuedWithdrawals[_processedId++];

            if (_asset == address(0)) {
                _strategy = queuedWithdrawal_.strategy;
                _asset = _underlyingTokenForStrategy(IStrategy(_strategy));
            }

            uint256 _withdrawnUnits = _sharesToUnit(_withdrawnAtCompletedWithdrawal, IERC20(_asset), IStrategy(_strategy));

            _accWithdrawnUnits += _withdrawnUnits;

            uint256 _amountToReinvest;
            uint256 _amountToQueue;

            if (_accWithdrawnUnits <= _pendingRequestsAtBatch) {
                // If we haven't exceeded the pending requests amount, queue everything for the redemption vault
                _amountToReinvest = 0;
                _amountToQueue = assetRegistry.convertFromUnitOfAccount(IERC20(_asset), _withdrawnUnits);
            } else if (_accWithdrawnUnits - _withdrawnUnits < _pendingRequestsAtBatch) {
                // If the threshold was exceeded, but it was exceeded by this withdrawal, split it between reinvesting and queuing
                uint256 _remainingToFill = _pendingRequestsAtBatch - (_accWithdrawnUnits - _withdrawnUnits);

                _amountToReinvest = assetRegistry.convertFromUnitOfAccount(IERC20(_asset), _withdrawnUnits - _remainingToFill);
                _amountToQueue = assetRegistry.convertFromUnitOfAccount(IERC20(_asset), _remainingToFill);
            } else {
                // If the threshold was exceeded before this withdrawal, reinvest everything
                _amountToReinvest = assetRegistry.convertFromUnitOfAccount(IERC20(_asset), _withdrawnUnits);
                _amountToQueue = 0;
            }

            _actions[i] = IYieldNestStrategyManager.WithdrawalAction({
                nodeId: ITokenStakingNode(queuedWithdrawal_.node).nodeId(),
                amountToReinvest: _amountToReinvest,
                amountToQueue: _amountToQueue,
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

    /// @notice Updates the buffer value.
    /// @dev Only callable by the buffer setter role.
    /// @param _buffer The new buffer value.
    function setBuffer(uint256 _buffer) external onlyRole(BUFFER_SETTER_ROLE) {
        _setBuffer(_buffer);
    }

    //
    // private functions
    //
    
    /// @dev This is an internal helper that allows passing a pre-calculated total queued withdrawals value
    function _getPendingWithdrawalRequests(uint256 _totalQueuedWithdrawals) private view returns (uint256 deficitAmount) {
        uint256 pendingAmount = withdrawalQueueManager.pendingRequestedRedemptionAmount();
        uint256 availableAmount = redemptionAssetsVault.availableRedemptionAssets() + _totalQueuedWithdrawals;
        if (pendingAmount <= availableAmount) {
            revert CurrentAvailableAmountIsSufficient();
        }
        deficitAmount = pendingAmount - availableAmount;
        if (deficitAmount < minPendingWithdrawalRequestAmount) {
            revert PendingWithdrawalRequestsTooLow();
        }
    }

    function _stakedBalanceForStrategy(
        IERC20 _asset
    ) private view returns (uint256 _stakedBalance) {
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

    /// @dev Applies the buffer to the amount.
    /// @param _amount The amount to apply the buffer to.
    /// @return The amount after the buffer has been applied.
    function _applyBuffer(uint256 _amount) private view returns (uint256) {
        return getBuffer() * _amount / 1 ether;
    }

    /// @dev Updates the buffer value and emits an event.
    /// @dev Reverts if the buffer is less than 1 ether.
    function _setBuffer(uint256 _buffer) private {
        if (_buffer < 1 ether) {
            revert InvalidBuffer();
        }

        buffer = _buffer;

        emit BufferSet(buffer);
    }
}
