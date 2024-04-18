// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IynETH} from "src/interfaces/IynETH.sol";

import "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";

/// @title Pooled Deposits Vault
/// @notice This contract allows users to deposit ETH into a pooled vault, which can then be converted into ynETH shares.
// Once the ynETH token is launched. This allows depositors pre-release access to the YieldNest deposits.
/// ETH deposits are enabled until the Owner defines the address of the ynETH token.
// Once ynETH is set to a non-zero address, deposits can be finalized, and no new ETH deposits are allowed.
contract PooledDepositsVault is Initializable, OwnableUpgradeable {

    error DepositMustBeGreaterThanZero();
    error YnETHIsSet();
    error YnETHNotSet();
    error AlreadySetAsYnETH();

    event DepositReceived(address indexed depositor, uint256 amount, uint256 totalAmount);
    event DepositFinalized(address indexed depositor, uint256 totalAmount, uint256 ynETHAmount);
    event YnETHSet(address indexed previousValue, address indexed newValue);

    mapping(address => uint256) public balances;
    IynETH public ynETH;

    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the contract with the initial owner.
    /// @param _initialOwner The address of the initial owner.
    function initialize(address _initialOwner) public initializer {
        __Ownable_init(_initialOwner);
    }

    /// @notice Sets the YnETH contract address.
    /// @param _ynETH The address of the YnETH contract.
    function setYnETH(IynETH _ynETH) public onlyOwner {
        if (address(_ynETH) == address(ynETH)) revert AlreadySetAsYnETH();
        emit YnETHSet(address(ynETH), address(_ynETH));
        ynETH = _ynETH;
    }

    /// @notice Allows users to deposit ETH into the contract.
    /// @dev Emits a DepositReceived event upon success.
    function deposit() public payable {
        if (address(ynETH) != address(0)) revert YnETHIsSet();
        if (msg.value == 0) revert DepositMustBeGreaterThanZero();
        balances[msg.sender] += msg.value;
        emit DepositReceived(msg.sender, msg.value, balances[msg.sender]);
    }

    /// @notice Finalizes deposits by converting deposited ETH into ynETH shares for each depositor.
    /// @param _depositors An array of addresses of depositors whose deposits are to be finalized.
    /// @dev Emits a DepositFinalized event for each depositor.
    function finalizeDeposits(address[] calldata _depositors) external {
        if (address(ynETH) == address(0)) revert YnETHNotSet();
        
        for (uint i = 0; i < _depositors.length; i++) {
            address depositor = _depositors[i];
            uint256 depositAmountPerDepositor = balances[depositor];
            if (depositAmountPerDepositor == 0) {
                continue;
            }
            balances[depositor] = 0;
            uint256 shares = ynETH.depositETH{value: depositAmountPerDepositor}(depositor);
            emit DepositFinalized(depositor, depositAmountPerDepositor, shares);
        }
    }

    /// @notice Allows the contract to receive ETH directly and triggers the deposit function.
    receive() external payable {
        deposit();
    }
}
