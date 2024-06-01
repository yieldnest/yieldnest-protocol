// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;


import "lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/token/ERC721/ERC721Upgradeable.sol";
import {AccessControlUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";

interface IRedemptionAdapter {
    function getRedemptionRate() external view returns (uint256);
    function transferRedeemableAsset(address to, uint256 amount) external;
    function transferRedemptionAsset(address to, uint256 amount) external;
}

contract WithdrawalQueueManager is ERC721Upgradeable, AccessControlUpgradeable, ReentrancyGuardUpgradeable {
    IERC20 public redeemableAsset;
    IERC20 public redemptionAsset;
    IRedemptionAdapter public redemptionAdapter;

    uint256 private _tokenIdCounter;

    struct WithdrawalRequest {
        uint256 amount;
        uint256 redemptionRateAtRequestTime;
    }

    mapping(uint256 => WithdrawalRequest) public withdrawalRequests;

    event WithdrawalRequested(uint256 indexed tokenId, address requester, uint256 amount);
    event WithdrawalClaimed(uint256 indexed tokenId, address claimer, uint256 redeemedAmount);

    constructor() {
         _disableInitializers();
    }

    struct InitializationParams {
        string name;
        string symbol;
        address redeemableAsset;
        address redemptionAsset;
        address redemptionAdapter;
    }

    function initialize(InitializationParams memory params) public initializer {
        __ERC721_init(params.name, params.symbol);
        redeemableAsset = IERC20(params.redeemableAsset);
        redemptionAsset = IERC20(params.redemptionAsset);
        redemptionAdapter = IRedemptionAdapter(params.redemptionAdapter);
    }

    function requestWithdrawal(uint256 amount) external nonReentrant {
        require(amount > 0, "WithdrawalQueueManager: amount must be greater than 0");
        require(redeemableAsset.transferFrom(msg.sender, address(this), amount), "WithdrawalQueueManager: Transfer failed");

        uint256 currentRate = redemptionAdapter.getRedemptionRate();
        uint256 tokenId = _tokenIdCounter++;
        withdrawalRequests[tokenId] = WithdrawalRequest({
            amount: amount,
            redemptionRateAtRequestTime: currentRate
        });

        redemptionAdapter.transferRedeemableAsset(address(this), amount);

        _mint(msg.sender, tokenId);
        emit WithdrawalRequested(tokenId, msg.sender, amount);
    }

    function claimWithdrawal(uint256 tokenId) external nonReentrant {
        require(_ownerOf(tokenId) == msg.sender || _getApproved(tokenId) == msg.sender, "WithdrawalQueueManager: caller is not owner nor approved");

        WithdrawalRequest storage request = withdrawalRequests[tokenId];
        uint256 redeemAmount = (request.amount * request.redemptionRateAtRequestTime) / 1e18; // Assuming rate is scaled by 1e18

        redemptionAdapter.transferRedemptionAsset(msg.sender, redeemAmount);

        _burn(tokenId);
        delete withdrawalRequests[tokenId];

        emit WithdrawalClaimed(tokenId, msg.sender, redeemAmount);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(AccessControlUpgradeable, ERC721Upgradeable) returns (bool) {
        return interfaceId == type(IERC721).interfaceId || super.supportsInterface(interfaceId);
    }

}

