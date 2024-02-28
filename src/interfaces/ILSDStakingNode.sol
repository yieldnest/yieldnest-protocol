// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IynLSD} from "./IynLSD.sol";

interface ILSDStakingNode {

    /// @notice Configuration for contract initialization.
    struct Init {
        IynLSD ynLSD;
        uint nodeId;
    }

    function initialize(Init calldata init) external;
    

    function implementation() external view returns (address);
}
