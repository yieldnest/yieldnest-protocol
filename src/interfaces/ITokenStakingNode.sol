// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ISignatureUtils} from "lib/eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";
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
    
    function depositAssetsToEigenlayer(
        IERC20[] memory assets,
        uint256[] memory amounts,
        IStrategy[] memory strategies
    ) external;

    function tokenStakingNodesManager() external view returns (ITokenStakingNodesManager);
    
    function implementation() external view returns (address);

    function getInitializedVersion() external view returns (uint64);

    function delegate(
        address operator,
        ISignatureUtils.SignatureWithExpiry memory signature,
        bytes32 approverSalt
    ) external;

    function undelegate() external;

    function queueWithdrawals(IStrategy _strategy, uint256 _shares) external returns (bytes32[] memory _fullWithdrawalRoots);
    function completeQueuedWithdrawals(uint256 _nonce, uint32 _startBlock, uint256 _shares, IStrategy _strategy, uint256[] memory _middlewareTimesIndexes) external;

    function deallocateTokens(IERC20 _token, uint256 _amount) external;

    function queuedShares(IStrategy _strategy) external view returns (uint256);
    function withdrawn(IERC20 _token) external view returns (uint256);
}
