// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ISignatureUtilsMixinTypes} from "lib/eigenlayer-contracts/src/contracts/interfaces/ISignatureUtilsMixin.sol";
import {ITokenStakingNodesManager} from "src/interfaces/ITokenStakingNodesManager.sol";
import {IStrategy} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IDelegationManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";

interface ITokenStakingNode {
    /// @notice Configuration for contract initialization.
    struct Init {
        ITokenStakingNodesManager tokenStakingNodesManager;
        uint256 nodeId;
    }

    function nodeId() external returns (uint256);

    function initialize(Init calldata init) external;

    function initializeV2() external;

    function initializeV3() external;

    function depositAssetsToEigenlayer(IERC20[] memory assets, uint256[] memory amounts, IStrategy[] memory strategies)
        external;

    function tokenStakingNodesManager() external view returns (ITokenStakingNodesManager);

    function implementation() external view returns (address);

    function getInitializedVersion() external view returns (uint64);

    function delegate(address operator, ISignatureUtilsMixinTypes.SignatureWithExpiry memory signature, bytes32 approverSalt)
        external;

    function undelegate() external returns (bytes32[] memory withdrawalRoots);

    function getQueuedSharesAndWithdrawn(IStrategy _strategy, IERC20 _asset) external view returns (uint256, uint256);
    function queueWithdrawals(IStrategy _strategy, uint256 _shares)
        external
        returns (bytes32[] memory _fullWithdrawalRoots);
    function completeQueuedWithdrawals(
        IDelegationManager.Withdrawal calldata withdrawal,
        bool updateTokenStakingNodesBalances
    ) external;

    function completeQueuedWithdrawals(
        IDelegationManager.Withdrawal[] memory withdrawals,
        bool updateTokenStakingNodesBalances
    ) external;

    function completeQueuedWithdrawalsAsShares(
        IDelegationManager.Withdrawal[] calldata withdrawals
    ) external;

    function deallocateTokens(IERC20 _token, uint256 _amount) external;

    function synchronize() external;

    function queuedShares(IStrategy _strategy) external view returns (uint256);
    function withdrawn(IERC20 _token) external view returns (uint256);
    function maxMagnitudeByWithdrawalRoot(bytes32 _withdrawalRoot) external view returns (uint64);
    function withdrawableSharesByWithdrawalRoot(bytes32 _withdrawalRoot) external view returns (uint256);
    function legacyQueuedShares(IStrategy _strategy) external view returns (uint256);
    function queuedAfterSlashingUpgrade(bytes32 _withdrawalRoot) external view returns (bool);

    /**
     * @notice Checks if the StakingNode's delegation state is synced with the DelegationManager.
     * @dev Compares the locally stored delegatedTo address with the actual delegation in DelegationManager.
     * @return True if the delegation state is synced, false otherwise.
     */
    function isSynchronized() external view returns (bool);

    function delegatedTo() external view returns (address);

    function setClaimer(address claimer) external;
}
