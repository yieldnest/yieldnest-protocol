// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {Initializable} from "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {IBeacon} from "lib/openzeppelin-contracts/contracts/proxy/beacon/IBeacon.sol";
import {ReentrancyGuardUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC20 as IERC20V4} from "lib/eigenlayer-contracts/lib/openzeppelin-contracts-v4.9.0/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ISignatureUtils} from "lib/eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";
import {IStrategyManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IDelegationManager, IDelegationManagerTypes} from "lib/eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategy} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {ITokenStakingNode} from "src/interfaces/ITokenStakingNode.sol";
import {ITokenStakingNodesManager} from "src/interfaces/ITokenStakingNodesManager.sol";
import {IWrapper} from "src/interfaces/IWrapper.sol";
import {IYieldNestStrategyManager} from "src/interfaces/IYieldNestStrategyManager.sol";

interface ITokenStakingNodeEvents {
    event DepositToEigenlayer(
        IERC20 indexed asset,
        IStrategy indexed strategy,
        uint256 amount,
        uint256 eigenShares
    );
    event Delegated(address indexed operator, bytes32 approverSalt);
    event Undelegated(bytes32[] withdrawalRoots);
    event QueuedWithdrawals(IStrategy strategies, uint256 shares, bytes32[] fullWithdrawalRoots);
    event CompletedQueuedWithdrawals(uint256 shares, uint256 amountOut, address strategy);
    event DeallocatedTokens(uint256 amount, IERC20 token);
}

/**
 * @title Token Staking Node
 * @dev Implements staking node functionality for tokens, enabling token staking, delegation, and rewards management.
 * This contract interacts with the Eigenlayer protocol to deposit assets, delegate staking operations, and manage staking rewards.
 */
contract TokenStakingNode is
    ITokenStakingNode,
    Initializable,
    ReentrancyGuardUpgradeable,
    ITokenStakingNodeEvents
{
    using SafeERC20 for IERC20;

    //--------------------------------------------------------------------------------------
    //----------------------------------  ERRORS  ------------------------------------------
    //--------------------------------------------------------------------------------------

    error ZeroAddress();
    error NotTokenStakingNodeOperator();
    error NotStrategyManager();
    error NotTokenStakingNodeDelegator();
    error NotTokenStakingNodesWithdrawer();
    error ArrayLengthMismatch();
    error NotSyncedAfterSlashing();

    //--------------------------------------------------------------------------------------
    //----------------------------------  VARIABLES  ---------------------------------------
    //--------------------------------------------------------------------------------------

    ITokenStakingNodesManager public override tokenStakingNodesManager;
    uint256 public nodeId;

    mapping(IStrategy => uint256) public queuedShares;
    mapping(IERC20 => uint256) public withdrawn;

    /**
     * @notice Maps withdrawal roots to the shares that were queued for withdrawal.
     * @dev Used in withdrawal completion to prevent accounting discrepancies with queued withdrawals.
     */
    mapping(bytes32 => uint256) public queuedSharesForWithdrawal;

    //--------------------------------------------------------------------------------------
    //----------------------------------  INITIALIZATION  ----------------------------------
    //--------------------------------------------------------------------------------------

    constructor() {
        _disableInitializers();
    }

    function initialize(
        Init memory init
    )
        public
        notZeroAddress(address(init.tokenStakingNodesManager))
        initializer
    {
        __ReentrancyGuard_init();
        tokenStakingNodesManager = init.tokenStakingNodesManager;
        nodeId = init.nodeId;
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  EIGENLAYER DEPOSITS  -----------------------------
    //--------------------------------------------------------------------------------------

    /**
     * @notice Deposits multiple assets into their respective strategies on Eigenlayer by retrieving them from tokenStakingNodesManager.
     * @dev Iterates through the provided arrays of assets and amounts, depositing each into its corresponding strategy.
     * @param assets An array of IERC20 tokens to be deposited.
     * @param amounts An array of amounts corresponding to each asset to be deposited.
     */
    function depositAssetsToEigenlayer(
        IERC20[] calldata assets,
        uint256[] calldata amounts,
        IStrategy[] calldata strategies
    ) external nonReentrant onlyYieldNestStrategyManager {

        uint256 assetsLength = assets.length;
        if (assetsLength != amounts.length || assetsLength != strategies.length) {
            revert ArrayLengthMismatch();
        }

        IStrategyManager strategyManager = tokenStakingNodesManager
            .strategyManager();

        for (uint256 i = 0; i < assetsLength; i++) {
            IERC20 asset = assets[i];
            uint256 amount = amounts[i];
            IStrategy strategy = strategies[i];

            asset.forceApprove(address(strategyManager), amount);

            uint256 eigenShares = strategyManager.depositIntoStrategy(
                IStrategy(strategy),
                IERC20V4(address(asset)),
                amount
            );
            emit DepositToEigenlayer(asset, strategy, amount, eigenShares);
        }
    }

    //--------------------------------------------------------------------------------------
    //-------------------------------- EIGENLAYER WITHDRAWALS  -----------------------------
    //--------------------------------------------------------------------------------------

    function getQueuedSharesAndWithdrawn(IStrategy _strategy, IERC20 _asset) external view returns (uint256, uint256) {
        return (queuedShares[_strategy], withdrawn[_asset]);
    }

    /**
     * @notice Queues withdrawals for a specific strategy
     * @param _strategy The strategy to withdraw from.
     * @param _depositShares The number of deposit shares to withdraw.
     * @return fullWithdrawalRoots An array of containing the withdrawal root of the queued withdrawal.
     *
     * NOTE: The number of shares withdrawn upon completion may be less than the amount initially queued due to the slashing factor.
     */
    function queueWithdrawals(
        IStrategy _strategy,
        uint256 _depositShares
    ) external onlyTokenStakingNodesWithdrawer returns (bytes32[] memory fullWithdrawalRoots) {
        IDelegationManagerTypes.QueuedWithdrawalParams[] memory queueWithdrawalParams = new IDelegationManagerTypes.QueuedWithdrawalParams[](1);

        queueWithdrawalParams[0] = IDelegationManagerTypes.QueuedWithdrawalParams({
            strategies: new IStrategy[](1),
            depositShares: new uint256[](1),
            __deprecated_withdrawer: address(0) // This field is ignored by EigenLayer v1.0.3.
        });

        queueWithdrawalParams[0].strategies[0] = _strategy;
        queueWithdrawalParams[0].depositShares[0] = _depositShares;

        IDelegationManager delegationManager = tokenStakingNodesManager.delegationManager();

        address operator = delegationManager.delegatedTo(address(this));

        uint256 withdrawableShares;

        if (operator == address(0)) {
            // Shares cannot be slashed if they were not delegated to an operator.
            // Therefore, the withdrawable shares will be the same amount as the deposit shares.
            withdrawableShares = _depositShares;

            fullWithdrawalRoots = delegationManager.queueWithdrawals(queueWithdrawalParams);
        } else {
            uint256[] memory operatorSharesBefore = delegationManager.getOperatorShares(operator, queueWithdrawalParams[0].strategies);

            fullWithdrawalRoots = delegationManager.queueWithdrawals(queueWithdrawalParams);

            uint256[] memory operatorSharesAfter = delegationManager.getOperatorShares(operator, queueWithdrawalParams[0].strategies);

            // Operator shares are decreased by the amount of withdrawable shares after the withdrawal is queued.
            // Using the diff before and after queue is the simplest way to get the withdrawable shares.
            withdrawableShares = operatorSharesBefore[0] - operatorSharesAfter[0];
        }

        queuedShares[_strategy] += withdrawableShares;
        queuedSharesForWithdrawal[fullWithdrawalRoots[0]] = withdrawableShares;

        emit QueuedWithdrawals(_strategy, withdrawableShares, fullWithdrawalRoots);
    }

    /**
     * @notice Completes queued withdrawals for a specific strategy
     * @param _nonce The nonce of the withdrawal
     * @param _startBlock The block number when the withdrawal was queued
     * @param _scaledShares The deposit shares scaled by the deposit scaling factor on the time of the withdrawal.
     * @param _strategy The strategy from which to withdraw
     * @param __deprecated_middlewareTimesIndexes This field is ignored. DelegationManager.completeQueuedWithdrawals does not use it anymore.
     * @param _updateTokenStakingNodesBalances If true calls updateTokenStakingNodesBalances for yieldNestStrategyManager
     */
    function completeQueuedWithdrawals(
        uint256 _nonce,
        uint32 _startBlock,
        uint256 _scaledShares,
        IStrategy _strategy,
        uint256[] calldata __deprecated_middlewareTimesIndexes,
        bool _updateTokenStakingNodesBalances
    ) public onlyTokenStakingNodesWithdrawer {
        IDelegationManager delegationManager = tokenStakingNodesManager.delegationManager();

        IDelegationManagerTypes.Withdrawal memory withdrawal = IDelegationManagerTypes.Withdrawal({
            staker: address(this),
            delegatedTo: delegationManager.delegatedTo(address(this)),
            withdrawer: address(this),
            nonce: _nonce,
            startBlock: _startBlock,
            strategies: new IStrategy[](1),
            scaledShares: new uint256[](1)
        });

        withdrawal.strategies[0] = _strategy;
        withdrawal.scaledShares[0] = _scaledShares;

        IERC20 token =  IERC20(address(_strategy.underlyingToken()));

        IERC20V4[] memory tokens = new IERC20V4[](1);
        // Uses OZ v4 ERC20 interface to be compatible with Eigenlayer v1.0.3.
        tokens[0] = IERC20V4(address(token));

        uint256 balanceBefore = token.balanceOf(address(this));
        uint256 strategyTotalSharesBefore = _strategy.totalShares();

        delegationManager.completeQueuedWithdrawal({
            withdrawal: withdrawal, 
            tokens: tokens, 
            receiveAsTokens: true
        });

        {
            uint256 withdrawnShares = strategyTotalSharesBefore - _strategy.totalShares();
            bytes32 withdrawalRoot = delegationManager.calculateWithdrawalRoot(withdrawal);

            if (withdrawnShares != queuedSharesForWithdrawal[withdrawalRoot]) {
                revert NotSyncedAfterSlashing();
            }

            queuedShares[_strategy] -= withdrawnShares;
        }

        uint256 withdrawnBalance = token.balanceOf(address(this)) - balanceBefore;
        
        IWrapper wrapper = IYieldNestStrategyManager(tokenStakingNodesManager.yieldNestStrategyManager()).wrapper();
        token.forceApprove(address(wrapper), withdrawnBalance); // NOTE: approving also token that will not be transferred
        (withdrawnBalance, token) = wrapper.wrap(withdrawnBalance, token);

        withdrawn[token] += withdrawnBalance;

        if (_updateTokenStakingNodesBalances) {
            // Actual balance changes only if slashing occured. choose to update here
            // only if the off-chain considers it necessary to save gas
            IYieldNestStrategyManager(tokenStakingNodesManager.yieldNestStrategyManager()).updateTokenStakingNodesBalances(token);
        }

        emit CompletedQueuedWithdrawals(_scaledShares, withdrawnBalance, address(_strategy));
    }

    /**
     * @notice Syncs queued shares in case of slashing to prevent accounting discrepancies between withdrawal queue and completion.
     * @dev This function is to be called as soon as slashing is detected.
     */
    function syncQueuedShares() external onlyDelegator {
        IDelegationManager delegationManager = tokenStakingNodesManager.delegationManager();

        (IDelegationManagerTypes.Withdrawal[] memory withdrawals, uint256[][] memory withdrawableShares) = delegationManager.getQueuedWithdrawals(address(this));

        for (uint256 i = 0; i < withdrawals.length; i++) {
            for (uint256 j = 0; j < withdrawals[i].strategies.length; j++) {
                queuedShares[withdrawals[i].strategies[j]] = 0;
            }
        }

        for (uint256 i = 0; i < withdrawals.length; i++) {
            IDelegationManagerTypes.Withdrawal memory withdrawal = withdrawals[i];
            
            for (uint256 j = 0; j < withdrawal.strategies.length; j++) {
                uint256 strategyWithdrawableShares = withdrawableShares[i][j];

                queuedShares[withdrawal.strategies[j]] += strategyWithdrawableShares;
                queuedSharesForWithdrawal[delegationManager.calculateWithdrawalRoot(withdrawal)] = strategyWithdrawableShares;
            }
        }
    }

    /**
     * @notice Deallocates tokens from the withdrawn balance and approves them for transfer.
     * @param _token The ERC20 token to deallocate.
     * @param _amount The amount of tokens to deallocate.
     */
    function deallocateTokens(IERC20 _token, uint256 _amount) external onlyYieldNestStrategyManager {
        withdrawn[_token] -= _amount;
        _token.safeTransfer(msg.sender, _amount);

        emit DeallocatedTokens(_amount, _token);
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  DELEGATION  --------------------------------------
    //--------------------------------------------------------------------------------------

    /**
     * @notice Delegates the staking operation to a specified operator.
     * @param operator The address of the operator to whom the staking operation is being delegated.
     */
    function delegate(
        address operator,
        ISignatureUtils.SignatureWithExpiry memory signature,
        bytes32 approverSalt
    ) public virtual onlyDelegator {
        IDelegationManager delegationManager = tokenStakingNodesManager
            .delegationManager();
        delegationManager.delegateTo(operator, signature, approverSalt);

        emit Delegated(operator, approverSalt);
    }

    /**
     * @notice Undelegates the staking operation.
     */
    function undelegate() public override onlyDelegator {
        IDelegationManager delegationManager = IDelegationManager(
            address(tokenStakingNodesManager.delegationManager())
        );
        bytes32[] memory withdrawalRoots = delegationManager.undelegate(
            address(this)
        );

        emit Undelegated(withdrawalRoots);
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  MODIFIERS  ---------------------------------------
    //--------------------------------------------------------------------------------------

    modifier onlyOperator() {
        if (
            !tokenStakingNodesManager.hasTokenStakingNodeOperatorRole(msg.sender)
        ) {
            revert NotTokenStakingNodeOperator();
        }
        _;
    }

    modifier onlyDelegator() {
        if (!tokenStakingNodesManager.hasTokenStakingNodeDelegatorRole(msg.sender)) {
            revert NotTokenStakingNodeDelegator();
        }
        _;
    }

    modifier onlyYieldNestStrategyManager() {
        if (!tokenStakingNodesManager.hasYieldNestStrategyManagerRole(msg.sender)) {
            revert NotStrategyManager();
        }
        _;
    }

    modifier onlyTokenStakingNodesWithdrawer() {
        if (
            !IYieldNestStrategyManager(tokenStakingNodesManager.yieldNestStrategyManager()).isStakingNodesWithdrawer(msg.sender)
        ) revert NotTokenStakingNodesWithdrawer();
        _;
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  BEACON IMPLEMENTATION  ---------------------------
    //--------------------------------------------------------------------------------------

    /**
      Beacons slot value is defined here:
      https://github.com/OpenZeppelin/openzeppelin-contracts/blob/afb20119b33072da041c97ea717d3ce4417b5e01/contracts/proxy/ERC1967/ERC1967Upgrade.sol#L142
     */
    function implementation() public view returns (address) {
        bytes32 slot = bytes32(uint256(keccak256("eip1967.proxy.beacon")) - 1);
        address implementationVariable;
        assembly {
            implementationVariable := sload(slot)
        }

        IBeacon beacon = IBeacon(implementationVariable);
        return beacon.implementation();
    }

    /// @notice Retrieve the version number of the highest/newest initialize
    ///         function that was executed.
    function getInitializedVersion() external view returns (uint64) {
        return _getInitializedVersion();
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  MODIFIERS  ---------------------------------------
    //--------------------------------------------------------------------------------------

    /// @notice Ensure that the given address is not the zero address.
    /// @param _address The address to check.
    modifier notZeroAddress(address _address) {
        if (_address == address(0)) {
            revert ZeroAddress();
        }
        _;
    }
}
