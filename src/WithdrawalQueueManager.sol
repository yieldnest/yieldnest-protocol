// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;


import "lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/token/ERC721/ERC721Upgradeable.sol";
import {IWithdrawalQueueManager} from "src/interfaces/IWithdrawalQueueManager.sol";
import {AccessControlUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";


interface IRedemptionAdapter {
    function getRedemptionRate() external view returns (uint256);
    function transferRedeemableAsset(address from, address to, uint256 amount) external;
    function transferRedemptionAsset(address to, uint256 amount) external;
}

interface IWithdrawalQueueManagerEvents {
    event WithdrawalRequested(uint256 indexed tokenId, address requester, uint256 amount);
    event WithdrawalClaimed(uint256 indexed tokenId, address claimer, uint256 redeemedAmount);
}

contract WithdrawalQueueManager is IWithdrawalQueueManager, ERC721Upgradeable, AccessControlUpgradeable, ReentrancyGuardUpgradeable, IWithdrawalQueueManagerEvents {

    //--------------------------------------------------------------------------------------
    //----------------------------------  ERRORS  -------------------------------------------
    //--------------------------------------------------------------------------------------

    error NotFinalized(uint256 currentTimestamp, uint256 requestTimestamp, uint256 queueDuration);
    error ZeroAddress();
    error WithdrawalAlreadyProcessed();
    
    //--------------------------------------------------------------------------------------
    //----------------------------------  ROLES  -------------------------------------------
    //--------------------------------------------------------------------------------------

    bytes32 public constant WITHDRAWAL_QUEUE_ADMIN_ROLE = keccak256("WITHDRAWAL_QUEUE_ADMIN_ROLE");

    //--------------------------------------------------------------------------------------
    //----------------------------------  CONSTANTS  ---------------------------------------
    //--------------------------------------------------------------------------------------

    uint256 FEE_PRECISION = 10000;

    //--------------------------------------------------------------------------------------
    //----------------------------------  VARIABLES  ---------------------------------------
    //--------------------------------------------------------------------------------------

    IERC20Metadata public redeemableAsset;
    IERC20Metadata public redemptionAsset;
    IRedemptionAdapter public redemptionAdapter;

    uint256 public _tokenIdCounter;

    mapping(uint256 => WithdrawalRequest) public withdrawalRequests;

    uint256 secondsToFinalization;
    uint256 withdrawalFee;

    //--------------------------------------------------------------------------------------
    //----------------------------------  INITIALIZATION  ----------------------------------
    //--------------------------------------------------------------------------------------

    constructor() {
       _disableInitializers();
    }

    struct Init {
        string name;
        string symbol;
        address redeemableAsset;
        address redemptionAsset;
        address redemptionAdapter;
        address admin;
        address withdrawalQueueAdmin;
        uint256 withdrawalFee;
    }

    function initialize(Init memory init)
        public
        notZeroAddress(address(init.admin))
        notZeroAddress(address(init.withdrawalQueueAdmin))
        initializer {
        __ERC721_init(init.name, init.symbol);
        redeemableAsset = IERC20Metadata(init.redeemableAsset);
        redemptionAsset = IERC20Metadata(init.redemptionAsset);
        redemptionAdapter = IRedemptionAdapter(init.redemptionAdapter);

        _grantRole(DEFAULT_ADMIN_ROLE, init.admin);
        _grantRole(WITHDRAWAL_QUEUE_ADMIN_ROLE, init.withdrawalQueueAdmin);

        withdrawalFee = init.withdrawalFee;
    }
    function requestWithdrawal(uint256 amount) external nonReentrant {
        require(amount > 0, "WithdrawalQueueManager: amount must be greater than 0");
        
        uint256 fee = calculateFee(amount);
        uint256 amountAfterFee = amount - fee;
        
        redeemableAsset.transferFrom(msg.sender, address(this), amountAfterFee);

        uint256 currentRate = redemptionAdapter.getRedemptionRate();
        uint256 tokenId = _tokenIdCounter++;
        withdrawalRequests[tokenId] = WithdrawalRequest({
            amount: amountAfterFee,
            redemptionRateAtRequestTime: currentRate,
            creationTimestamp: block.timestamp,
            creationBlock: block.number,
            processed: false
        });

        redemptionAdapter.transferRedeemableAsset(msg.sender, address(this), amount);

        _mint(msg.sender, tokenId);

        emit WithdrawalRequested(tokenId, msg.sender, amount);
    }

    function claimWithdrawal(uint256 tokenId) public nonReentrant {
        require(_ownerOf(tokenId) == msg.sender || _getApproved(tokenId) == msg.sender, "WithdrawalQueueManager: caller is not owner nor approved");


        WithdrawalRequest memory request = withdrawalRequests[tokenId];

        if (request.processed) {
            revert WithdrawalAlreadyProcessed();
        }

        if (block.timestamp < request.creationTimestamp + secondsToFinalization) {
            revert NotFinalized(block.timestamp, request.creationTimestamp, secondsToFinalization);
        }

        uint256 redeemAmount = (request.amount * request.redemptionRateAtRequestTime) / (10 ** redeemableAsset.decimals());

        redemptionAdapter.transferRedemptionAsset(msg.sender, redeemAmount);

        _burn(tokenId);
        withdrawalRequests[tokenId].processed = true;

        emit WithdrawalClaimed(tokenId, msg.sender, redeemAmount);
    }

    /**
     * @notice Allows a batch of withdrawals to be claimed by their respective token IDs.
     * @param tokenIds An array of token IDs representing the withdrawal requests to be claimed.
     */
    function claimWithdrawals(uint256[] calldata tokenIds) external {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            claimWithdrawal(tokenIds[i]);
        }
    }

    /// @notice Calculates the withdrawal fee based on the amount and the current fee percentage.
    /// @param amount The amount from which the fee should be calculated.
    /// @return fee The calculated fee.
    function calculateFee(uint256 amount) public view returns (uint256) {
        return (amount * withdrawalFee) / 10000;
    }

    function setSecondsToFinalization(uint256 _secondsToFinalization) external onlyRole(WITHDRAWAL_QUEUE_ADMIN_ROLE) {
        secondsToFinalization = _secondsToFinalization;
    }

    /// @notice Sets the withdrawal fee percentage.
    /// @param feePercentage The fee percentage in basis points.
    function setWithdrawalFee(uint256 feePercentage) external onlyRole(WITHDRAWAL_QUEUE_ADMIN_ROLE) {
        require(feePercentage <= 10000, "WithdrawalQueueManager: Fee percentage cannot exceed 100%");
        withdrawalFee = feePercentage;
        emit WithdrawalFeeUpdated(feePercentage);
    }

    event WithdrawalFeeUpdated(uint256 newFeePercentage);

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

