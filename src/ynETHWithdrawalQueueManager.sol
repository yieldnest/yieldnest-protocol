// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import "lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/token/ERC721/ERC721Upgradeable.sol";
import {IWithdrawalQueueManager} from "src/interfaces/IWithdrawalQueueManager.sol";
import {IynETH} from "src/interfaces/IynETH.sol";
import {AccessControlUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";

import {WithdrawalQueueManager} from "src/WithdrawalQueueManager.sol";

interface IRedemptionAdapter {
    function getRedemptionRate() external view returns (uint256);
    function transferRedeemableAsset(address from, address to, uint256 amount) external;
    function transferRedemptionAsset(address to, uint256 amount) external;
}

interface IynETHWithdrawalQueueManagerEvents {
    event ETHReceived(address indexed sender, uint256 value);
}

contract ynETHWithdrawalQueueManager is WithdrawalQueueManager, IynETHWithdrawalQueueManagerEvents {

    uint256 public constant YN_ETH_UNIT = 1e18;

    receive() external payable {
        emit ETHReceived(msg.sender, msg.value);
    }

    function redemptionRate() public view override returns (uint256) {
        return IynETH(address(redeemableAsset)).previewRedeem(YN_ETH_UNIT);
    }

    function availableRedemptionAssets() public view override returns (uint256) {
        return address(this).balance;
    }

    function transferRedemptionAssets(address to, uint256 amount) internal override {
        (bool success, ) = payable(to).call{value: amount}("");
        if (!success) {
            revert TransferFailed(amount, to);
        }
    }

    function withdrawRedemptionAssets(uint256 amount) internal override {
        IynETH ynETH = IynETH(address(redeemableAsset));
        ynETH.processWithdrawnETH{ value: amount }();
    }
}