pragma solidity ^0.8.0;

interface IStakeFishBatchDeposit {
    event FeeChanged(uint256 previousFee, uint256 newFee);
    event Withdrawn(address indexed payee, uint256 weiAmount);
    event FeeCollected(address indexed payee, uint256 weiAmount);

    function batchDeposit(
        bytes calldata pubkeys, 
        bytes calldata withdrawal_credentials, 
        bytes calldata signatures, 
        bytes32[] calldata deposit_data_roots
    ) external payable;

    function withdraw(address payable receiver) external;

    function changeFee(uint256 newFee) external;

    function pause() external;

    function unpause() external;

    function fee() external view returns (uint256);
}