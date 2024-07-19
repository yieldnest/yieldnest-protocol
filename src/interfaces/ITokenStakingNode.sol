// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ISignatureUtils} from "lib/eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";
import {ITokenStakingNodesManager} from "src/interfaces/ITokenStakingNodesManager.sol";
import {IStrategy} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";

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
}
