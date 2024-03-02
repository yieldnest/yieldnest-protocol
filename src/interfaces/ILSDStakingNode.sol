// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IynLSD} from "./IynLSD.sol";

interface ILSDStakingNode {

    /// @notice Configuration for contract initialization.
    struct Init {
        IynLSD ynLSD;
        uint nodeId;
    }

    function nodeId() external returns (uint256);

    function initialize(Init calldata init) external;
    
   function depositAssetsToEigenlayer(
        IERC20[] memory assets,
        uint[] memory amounts
    ) external;


    function implementation() external view returns (address);

    function getInitializedVersion() external view returns (uint64);
}
