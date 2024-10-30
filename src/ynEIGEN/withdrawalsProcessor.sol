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

    struct PendingWithdrawal {
        address node;
        uint256 nonce;
        uint256 shares;
        uint32 _startBlock;
    }

    uint256 public withdrawalsId;
    uint256 public minNodeShares;
    uint256 public minPendingWithdrawalRequestAmount;

    IWithdrawalQueueManager public immutable withdrawalQueueManager;
    ITokenStakingNodesManager public immutable tokenStakingNodesManager;
    IAssetRegistry public immutable assetRegistry;
    IEigenStrategyManager public immutable eigenStrategyManager;

    IDelegationManager public immutable delegationManager;

    mapping(uint256 id => mapping(IStrategy => PendingWithdrawal[])) public pendingWithdrawals; // @todo - here -- dont use array, use mapping instead (compiler does multi writes anyways)


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

    function queueWithdrawals() public onlyOwner returns (bool) {

        uint256 _pendingWithdrawalRequests = withdrawalQueueManager.pendingRequestedRedemptionAmount();
        if (_pendingWithdrawalRequests <= minPendingWithdrawalRequestAmount) return true;

        ITokenStakingNode[] memory _nodes = tokenStakingNodesManager.getAllNodes();
        IERC20[] memory _assets = assetRegistry.getAssets();

        uint256 _assetsLength = _assets.length;
        uint256 _nodesLength = _nodes.length;
        uint256 _minNodeShares = minNodeShares;
        for (uint256 i = 0; i < _assetsLength; ++i) {
            bool _rektStrategy;
            IStrategy _strategy = eigenStrategyManager.strategies(_assets[i]);
            uint256 _pendingWithdrawalRequestsInShares = _unitToShares(_pendingWithdrawalRequests);
            Node[] memory _pendingWithdrawals = new Node[](_nodesLength);
            for (uint256 j = 0; j < _nodesLength; ++j) {
                bool _rektNode;
                uint256 _nonce;
                uint256 _withdrawnShares;
                address _node = address(_nodes[j]);
                uint256 _nodeShares = _strategy.shares(_node);
                if (_nodeShares > _pendingWithdrawalRequestsInShares) {
                    _rektNode = true;
                    _withdrawnShares = _nodeShares - _pendingWithdrawalRequestsInShares;
                    _pendingWithdrawalRequestsInShares = 0;
                } else if (_nodeShares > _minNodeShares) {
                    _rektNode = true;
                    _withdrawnShares = _nodeShares;
                    _pendingWithdrawalRequestsInShares -= _withdrawnShares;
                }

                if (_rektNode) {
                    _rektStrategy = true;
                    _nonce = delegationManager.cumulativeWithdrawalsQueued(_node);
                    _pendingWithdrawals[j] = Node(_node, _nonce, _withdrawnShares);
                    ITokenStakingNode(_node).queueWithdrawals(_strategy, _withdrawnShares);
                }
            }

            if (_rektStrategy) {
                // pendingWithdrawals[withdrawalsId++][_strategy] = PendingWithdrawal(_pendingWithdrawals, uint32(block.number));
                pendingWithdrawals[withdrawalsId][_strategy] = _pendingWithdrawals;
                if (_pendingWithdrawalRequestsInShares == 0) return true;
            }

            _pendingWithdrawalRequests = _sharesToUnit(_pendingWithdrawalRequestsInShares);
        }
        return false;
    }

    function completeQueuedWithdrawals() public {
        // complete withdrawals according to data saved in `queueWithdrawals`
    }

    function processPrincipalWithdrawals() public {
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

    //
    // Events
    //

    event MinNodeSharesUpdated(uint256 minNodeShares);
    event MinPendingWithdrawalRequestAmountUpdated(uint256 minPendingWithdrawalRequestAmount);
}