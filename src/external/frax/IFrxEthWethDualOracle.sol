// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

interface IFrxEthWethDualOracle {

    /// @notice The ```getCurveEmaEthPerFrxEth``` function gets the EMA price of frxEth in eth units
    /// @dev normalized to match precision of oracle
    /// @return _ethPerFrxEth
     function getCurveEmaEthPerFrxEth() external view returns (uint256 _ethPerFrxEth);
}