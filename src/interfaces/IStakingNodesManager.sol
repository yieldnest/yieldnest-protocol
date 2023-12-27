pragma solidity ^0.8.0;

import "./eigenlayer/IDelegationManager.sol";
import "./eigenlayer/IEigenPodManager.sol";

interface IStakingNodesManager {

    struct DepositData {
        bytes publicKey;
        bytes signature;
        bytes32 depositDataRoot;
    }

    function eigenPodManager() external view returns (IEigenPodManager);

    function delegationManager() external view returns (IDelegationManager);
}


