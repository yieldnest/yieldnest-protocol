// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IynETH} from "src/interfaces/IynETH.sol";

import "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";

contract PooledDepositsVault is Initializable, OwnableUpgradeable {

    error DepositMustBeGreaterThanZero();
    error YnETHIsSet();
    error YnETHNotSet();

    mapping(address => uint256) public balances;

    event DepositReceived(address indexed depositor, uint256 amount);
    event DepositsFinalized(address indexed depositor, uint256 totalAmount, uint256 ynETHAmount);
    event YnETHSet(address previousValue, address newValue);

    IynETH public ynETH;

    function initialize(address initialOwner) public initializer {
        __Ownable_init(initialOwner);
    }

    function setYnETH(IynETH _ynETH) public onlyOwner {
        emit YnETHSet(address(ynETH), address(_ynETH));
        ynETH = _ynETH;
    }

    function deposit() public payable {
        if (address(ynETH) != address(0)) revert YnETHIsSet();
        if (msg.value == 0) revert DepositMustBeGreaterThanZero();
        balances[msg.sender] += msg.value;
        emit DepositReceived(msg.sender, msg.value);
    }

    function finalizeDeposits(address[] calldata depositors) external {
        if (address(ynETH) == address(0)) revert YnETHNotSet();
        
        for (uint i = 0; i < depositors.length; i++) {
            address depositor = depositors[i];
            uint256 depositAmountPerDepositor = balances[depositor];
            if (depositAmountPerDepositor == 0) {
                continue;
            }
            balances[depositor] = 0;
            uint256 shares = ynETH.depositETH{value: depositAmountPerDepositor}(depositor);
            emit DepositsFinalized(depositor, depositAmountPerDepositor, shares);
        }
    }

    receive() external payable {
        deposit();
    }
}
