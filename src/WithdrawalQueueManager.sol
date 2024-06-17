// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import "lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "lib/openzeppelin-contracts-upgradeable/contracts/token/ERC721/ERC721Upgradeable.sol";
import {IWithdrawalQueueManager} from "src/interfaces/IWithdrawalQueueManager.sol";
import {AccessControlUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import {IRedeemableAsset} from "src/interfaces/IRedeemableAsset.sol";

interface IWithdrawalQueueManagerEvents {
    event WithdrawalRequested(uint256 indexed tokenId, address requester, uint256 amount);
    event WithdrawalClaimed(uint256 indexed tokenId, address claimer, address receiver, IWithdrawalQueueManager.WithdrawalRequest request);
    event WithdrawalFeeUpdated(uint256 newFeePercentage);
    event FeeReceiverUpdated(address indexed oldFeeReceiver, address indexed newFeeReceiver);
}

abstract contract WithdrawalQueueManager is IWithdrawalQueueManager, ERC721Upgradeable, AccessControlUpgradeable, ReentrancyGuardUpgradeable, IWithdrawalQueueManagerEvents {

    //--------------------------------------------------------------------------------------
    //----------------------------------  ERRORS  -------------------------------------------
    //--------------------------------------------------------------------------------------

    error NotFinalized(uint256 currentTimestamp, uint256 requestTimestamp, uint256 queueDuration);
    error ZeroAddress();
    error WithdrawalAlreadyProcessed();
    error InsufficientBalance(uint256 currentBalance, uint256 requestedBalance);
    error TransferFailed(uint256 amount, address destination);
    error CallerNotOwnerNorApproved(uint256 tokenId, address caller);
    
    //--------------------------------------------------------------------------------------
    //----------------------------------  ROLES  -------------------------------------------
    //--------------------------------------------------------------------------------------

    bytes32 public constant WITHDRAWAL_QUEUE_ADMIN_ROLE = keccak256("WITHDRAWAL_QUEUE_ADMIN_ROLE");

    //--------------------------------------------------------------------------------------
    //----------------------------------  CONSTANTS  ---------------------------------------
    //--------------------------------------------------------------------------------------

    uint256 constant public FEE_PRECISION = 1000000;

    //--------------------------------------------------------------------------------------
    //----------------------------------  VARIABLES  ---------------------------------------
    //--------------------------------------------------------------------------------------

    IRedeemableAsset public redeemableAsset;

    uint256 public _tokenIdCounter;

    mapping(uint256 => WithdrawalRequest) public withdrawalRequests;

    uint256 public secondsToFinalization;
    uint256 public withdrawalFee;
    address public feeReceiver;

    /// pending requested redemption amount in redemption unit of account
    uint256 public pendingRequestedRedemptionAmount;

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
        address admin;
        address withdrawalQueueAdmin;
        uint256 withdrawalFee;
        address feeReceiver;
    }

    function initialize(Init memory init)
        public
        notZeroAddress(address(init.admin))
        notZeroAddress(address(init.redeemableAsset))
        notZeroAddress(address(init.withdrawalQueueAdmin))
        notZeroAddress(address(init.feeReceiver))
    
        initializer {
        __ERC721_init(init.name, init.symbol);
        redeemableAsset = IRedeemableAsset(init.redeemableAsset);

        _grantRole(DEFAULT_ADMIN_ROLE, init.admin);
        _grantRole(WITHDRAWAL_QUEUE_ADMIN_ROLE, init.withdrawalQueueAdmin);

        withdrawalFee = init.withdrawalFee;
        feeReceiver = init.feeReceiver;
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  WITHDRAWAL REQUESTS  -----------------------------
    //--------------------------------------------------------------------------------------

    function requestWithdrawal(uint256 amount) external nonReentrant {
        require(amount > 0, "WithdrawalQueueManager: amount must be greater than 0");
        
        redeemableAsset.transferFrom(msg.sender, address(this), amount);

        uint256 currentRate = redemptionRate();
        uint256 tokenId = _tokenIdCounter++;
        withdrawalRequests[tokenId] = WithdrawalRequest({
            amount: amount,
            feeAtRequestTime: withdrawalFee,
            redemptionRateAtRequestTime: currentRate,
            creationTimestamp: block.timestamp,
            creationBlock: block.number,
            processed: false
        });

        pendingRequestedRedemptionAmount += calculateRedemptionAmount(amount, currentRate);

        _mint(msg.sender, tokenId);

        emit WithdrawalRequested(tokenId, msg.sender, amount);
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  CLAIMS  ------------------------------------------
    //--------------------------------------------------------------------------------------

    function claimWithdrawal(uint256 tokenId, address receiver) public nonReentrant {
        if (_ownerOf(tokenId) != msg.sender && _getApproved(tokenId) != msg.sender) {
            revert CallerNotOwnerNorApproved(tokenId, msg.sender);
        }

        WithdrawalRequest memory request = withdrawalRequests[tokenId];

        if (request.processed) {
            revert WithdrawalAlreadyProcessed();
        }

        if (!isFinalized(request)) {
            revert NotFinalized(block.timestamp, request.creationTimestamp, secondsToFinalization);
        }

        withdrawalRequests[tokenId].processed = true;
        pendingRequestedRedemptionAmount -= calculateRedemptionAmount(request.amount, request.redemptionRateAtRequestTime);

        _burn(tokenId);
        redeemableAsset.burn(request.amount);

        transferRedemptionAssets(receiver, request);

        emit WithdrawalClaimed(tokenId, msg.sender, receiver, request);
    }

    /**
     * @notice Allows a batch of withdrawals to be claimed by their respective token IDs.
     * @param tokenIds An array of token IDs representing the withdrawal requests to be claimed.
     */
    function claimWithdrawals(uint256[] calldata tokenIds, address[] calldata receivers) external {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            claimWithdrawal(tokenIds[i], receivers[i]);
        }
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  ADMIN  -------------------------------------------
    //--------------------------------------------------------------------------------------

    function setSecondsToFinalization(uint256 _secondsToFinalization) external onlyRole(WITHDRAWAL_QUEUE_ADMIN_ROLE) {
        secondsToFinalization = _secondsToFinalization;
    }

    /// @notice Sets the withdrawal fee percentage.
    /// @param feePercentage The fee percentage in basis points.
    function setWithdrawalFee(uint256 feePercentage) external onlyRole(WITHDRAWAL_QUEUE_ADMIN_ROLE) {
        require(feePercentage <= FEE_PRECISION, "WithdrawalQueueManager: Fee percentage cannot exceed 100%");
        withdrawalFee = feePercentage;
        emit WithdrawalFeeUpdated(feePercentage);
    }

    /// @notice Sets the address where withdrawal fees are sent.
    /// @param _feeReceiver The address that will receive the withdrawal fees.
    function setFeeReceiver(address _feeReceiver) external onlyRole(WITHDRAWAL_QUEUE_ADMIN_ROLE) {
        require(_feeReceiver != address(0), "WithdrawalQueueManager: Fee receiver cannot be the zero address");
        emit FeeReceiverUpdated(feeReceiver, _feeReceiver);
        feeReceiver = _feeReceiver;
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  COMPUTATIONS  ------------------------------------
    //--------------------------------------------------------------------------------------

    function calculateRedemptionAmount(
        uint256 amount,
        uint256 redemptionRateAtRequestTime
    ) public view returns (uint256) {
        return amount * redemptionRateAtRequestTime / (10 ** redeemableAsset.decimals());
    }


    /// @notice Calculates the withdrawal fee based on the amount and the current fee percentage.
    /// @param amount The amount from which the fee should be calculated.
    /// @return fee The calculated fee.
    function calculateFee(uint256 amount, uint256 requestWithdrawalFee) public view returns (uint256) {
        return (amount * requestWithdrawalFee) / FEE_PRECISION;
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  VIRTUAL  -----------------------------------------
    //--------------------------------------------------------------------------------------


    /// @notice Retrieves the current redemption rate for the asset in the unit of account.
    /// @return The current redemption rate
    function redemptionRate() public view virtual returns (uint256);

    /// @notice Transfers redemption assets to a specified address based on a withdrawal request.
    /// @param to The address to which the assets will be transferred.
    /// @param request The withdrawal request containing details such as amount and fee.
    function transferRedemptionAssets(address to, WithdrawalRequest memory request) public virtual;

    /// @notice Gets the total amount of redemption assets available for withdrawal in the unit of account.
    /// @return The available amount of redemption assets
    function availableRedemptionAmount() public view virtual returns (uint256);

    //--------------------------------------------------------------------------------------
    //----------------------------------  VIEWS  -------------------------------------------
    //--------------------------------------------------------------------------------------


    /// @notice Calculates the surplus of redemption assets after accounting for all pending withdrawals.
    /// @return surplus The amount of surplus redemption assets in the unit of account.
    function surplusRedemptionAmount() public view returns (uint256) {
        uint256 availableAmount = availableRedemptionAmount();
        if (availableAmount > pendingRequestedRedemptionAmount) {
            return availableAmount - pendingRequestedRedemptionAmount;
        } 
        
        return 0;
    }

    /// @notice Calculates the deficit of redemption assets after accounting for all pending withdrawals.
    /// @return deficit The amount of deficit redemption assets in the unit of account.
    function deficitRedemptionAmount() public view returns (uint256) {
        uint256 availableAmount = availableRedemptionAmount();
        if (pendingRequestedRedemptionAmount > availableAmount) {
            return pendingRequestedRedemptionAmount - availableAmount;
        }
        
        return 0;
    }

    /**
     * @notice Checks if a withdrawal request with a given index is finalized.
     * @param index The index of the withdrawal request.
     * @return True if the request is finalized, false otherwise.
     */
    function withdrawalRequestIsFinalized(uint256 index) public view returns (bool) {
        WithdrawalRequest memory request = withdrawalRequests[index];
        return isFinalized(request);
    }

    /**
     * @notice Checks if a withdrawal request is finalized.
     * @param request The withdrawal request to check.
     * @return True if the request is finalized, false otherwise.
     */
    function isFinalized(WithdrawalRequest memory request) public view returns (bool) {
        return block.timestamp >= request.creationTimestamp + secondsToFinalization;
    }

    /**
     * @notice Returns the details of a withdrawal request.
     * @param tokenId The token ID of the withdrawal request.
     * @return request The withdrawal request details.
     */
    function withdrawalRequest(uint256 tokenId) public view returns (WithdrawalRequest memory request) {
        request = withdrawalRequests[tokenId];
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

