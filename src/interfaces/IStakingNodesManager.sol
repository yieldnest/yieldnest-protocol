pragma solidity ^0.8.0;

interface IStakingNodesManager {

    struct DepositData {
        bytes publicKey;
        bytes signature;
        bytes32 depositDataRoot;
    }

    function eigenPodManager() external view returns (address);
}


