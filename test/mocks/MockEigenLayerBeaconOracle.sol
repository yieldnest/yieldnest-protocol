import "lib/eigenlayer-contracts/src/contracts/interfaces/IBeaconChainOracle.sol";

contract MockEigenLayerBeaconOracle is IBeaconChainOracle  {
    bytes32 public mockBeaconChainStateRoot;

    function getOracleBlockRootAtTimestamp() external view returns(bytes32) {
        return mockBeaconChainStateRoot;
    }

    function setOracleBlockRootAtTimestamp(bytes32 beaconChainStateRoot) external {
        mockBeaconChainStateRoot = beaconChainStateRoot;
    }

    function timestampToBlockRoot(uint256 /*blockNumber*/) external view returns(bytes32) {
        return mockBeaconChainStateRoot;
    }
}
