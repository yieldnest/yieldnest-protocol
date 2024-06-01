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

interface IWithdrawalQueueManagerEvents {
    event WithdrawalRequested(uint256 indexed tokenId, address requester, uint256 amount);
    event WithdrawalClaimed(uint256 indexed tokenId, address claimer, uint256 redeemedAmount);
}

contract WithdrawalQueueManager is ERC721Upgradeable, AccessControlUpgradeable, ReentrancyGuardUpgradeable, IWithdrawalQueueManagerEvents {

    //--------------------------------------------------------------------------------------
    //----------------------------------  ERRORS  -------------------------------------------
    //--------------------------------------------------------------------------------------

    error NotFinalized(uint256 currentTimestamp, uint256 requestTimestamp, uint256 queueDuration);
    error ZeroAddress();
    
    //--------------------------------------------------------------------------------------
    //----------------------------------  ROLES  -------------------------------------------
    //--------------------------------------------------------------------------------------

    bytes32 public constant WITHDRAWAL_QUEUE_ADMIN_ROLE = keccak256("WITHDRAWAL_QUEUE_ADMIN_ROLE");


    //--------------------------------------------------------------------------------------
    //----------------------------------  VARIABLES  ---------------------------------------
    //--------------------------------------------------------------------------------------

    IERC20 public redeemableAsset;
    IERC20 public redemptionAsset;
    IRedemptionAdapter public redemptionAdapter;

    uint256 private _tokenIdCounter;

    struct WithdrawalRequest {
        uint256 amount;
        uint256 redemptionRateAtRequestTime;
        uint256 creationTimestamp;
        uint256 creationBlock;
    }

    mapping(uint256 => WithdrawalRequest) public withdrawalRequests;

    uint256 secondsToFinalization;

    //--------------------------------------------------------------------------------------
    //----------------------------------  INITIALIZATION  ----------------------------------
    //--------------------------------------------------------------------------------------

    constructor() {
       _disableInitializers();
    }

    struct InitializationParams {
        string name;
        string symbol;
        address redeemableAsset;
        address redemptionAsset;
        address redemptionAdapter;
        address admin;
        address withdrawalQueueAdmin;
    }

    function initialize(InitializationParams memory init)
        public
        notZeroAddress(address(init.admin))
        notZeroAddress(address(init.withdrawalQueueAdmin))
        initializer {
        __ERC721_init(init.name, init.symbol);
        redeemableAsset = IERC20(init.redeemableAsset);
        redemptionAsset = IERC20(init.redemptionAsset);
        redemptionAdapter = IRedemptionAdapter(init.redemptionAdapter);

        _grantRole(DEFAULT_ADMIN_ROLE, init.admin);
        _grantRole(WITHDRAWAL_QUEUE_ADMIN_ROLE, init.withdrawalQueueAdmin);
    }

    function requestWithdrawal(uint256 amount) external nonReentrant {
        require(amount > 0, "WithdrawalQueueManager: amount must be greater than 0");
        require(redeemableAsset.transferFrom(msg.sender, address(this), amount), "WithdrawalQueueManager: Transfer failed");

        uint256 currentRate = redemptionAdapter.getRedemptionRate();
        uint256 tokenId = _tokenIdCounter++;
        withdrawalRequests[tokenId] = WithdrawalRequest({
            amount: amount,
            redemptionRateAtRequestTime: currentRate,
            creationTimestamp: block.timestamp,
            creationBlock: block.number
        });

        redemptionAdapter.transferRedeemableAsset(address(this), amount);

        _mint(msg.sender, tokenId);

        emit WithdrawalRequested(tokenId, msg.sender, amount);
    }

    function claimWithdrawal(uint256 tokenId) external nonReentrant {
        require(_ownerOf(tokenId) == msg.sender || _getApproved(tokenId) == msg.sender, "WithdrawalQueueManager: caller is not owner nor approved");

        WithdrawalRequest memory request = withdrawalRequests[tokenId];
        if (block.timestamp < request.creationTimestamp + secondsToFinalization) {
            revert NotFinalized(block.timestamp, request.creationTimestamp, secondsToFinalization);
        }

        uint256 redeemAmount = (request.amount * request.redemptionRateAtRequestTime) / 1e18; // Assuming rate is scaled by 1e18

        redemptionAdapter.transferRedemptionAsset(msg.sender, redeemAmount);

        _burn(tokenId);
        delete withdrawalRequests[tokenId];

        emit WithdrawalClaimed(tokenId, msg.sender, redeemAmount);
    }

    function setSecondsToFinalization(uint256 _secondsToFinalization) external onlyRole(WITHDRAWAL_QUEUE_ADMIN_ROLE) {
        secondsToFinalization = _secondsToFinalization;
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(AccessControlUpgradeable, ERC721Upgradeable) returns (bool) {
        return interfaceId == type(IERC721).interfaceId || super.supportsInterface(interfaceId);
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  MODIFIERS  ---------------------------------------
    //--------------------------------------------------------------------------------------

    /// @notice Ensure that the given address is not the zero address.
    /// @param _address The address to check.
    modifier notZeroAddress(address _address) {
        if (_address == address(0)) {
            revert ZeroAddress();
        }
        _;
    }
}

