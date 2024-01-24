pragma solidity ^0.8.22;

interface IEigenLayerBeaconOracle {
    event EigenLayerBeaconOracleUpdate(uint256 slot, uint256 timestamp, bytes32 blockRoot);

    function onlyWhitelistedUpdater() external view returns (bool);

    /// @notice Get beacon block root for the given timestamp
    function getBeaconBlockRoot(uint256 _timestamp) external view returns (bytes32);


    function toBigEndian(uint32 value) external pure returns (bytes4);

    function denebRequest(uint256 _targetTimestamp) external;

}
