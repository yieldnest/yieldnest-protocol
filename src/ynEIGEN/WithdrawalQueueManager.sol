// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import "lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IWithdrawalQueueManager} from "src/interfaces/IWithdrawalQueueManager.sol";
import {AccessControlUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import {IRedeemableAsset} from "src/interfaces/IRedeemableAsset.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC721EnumerableUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IRedemptionAssetsVault} from "./interfaces/IRedemptionAssetsVault.sol";

interface IWithdrawalQueueManagerEvents {
    event WithdrawalRequested(uint256 indexed tokenId, address indexed requester, uint256 amount);
    event WithdrawalClaimed(
        uint256 indexed tokenId,
        address claimer,
        address receiver,
        IWithdrawalQueueManager.WithdrawalRequest request,
        uint256 finalizationId
    );
    event WithdrawalFeeUpdated(uint256 newFeePercentage);
    event FeeReceiverUpdated(address indexed oldFeeReceiver, address indexed newFeeReceiver);
    event SecondsToFinalizationUpdated(uint256 previousValue, uint256 newValue);
    event RequestsFinalized(uint256 indexed finalizationIndex, uint256 newFinalizedIndex, uint256 previousFinalizedIndex, uint256 redemptionRate);
}

/**
 * @title Withdrawal Queue Manager for Redeemable Assets
 * @dev Manages the queue of withdrawal requests for redeemable assets, handling fees, finalization times, and claims.
 * This contract extends ERC721 to represent each withdrawal request as a unique token.
 * 
 */

contract WithdrawalQueueManager is IWithdrawalQueueManager, ERC721EnumerableUpgradeable, AccessControlUpgradeable, ReentrancyGuardUpgradeable, IWithdrawalQueueManagerEvents {
    using SafeERC20 for IRedeemableAsset;

    //--------------------------------------------------------------------------------------
    //----------------------------------  ERRORS  -------------------------------------------
    //--------------------------------------------------------------------------------------

    error NotFinalized(uint256 tokenId);
    error ZeroAddress();
    error WithdrawalAlreadyProcessed(uint256 tokenId);
    error InsufficientBalance(uint256 currentBalance, uint256 requestedBalance);
    error CallerNotOwnerNorApproved(uint256 tokenId, address caller);
    error AmountExceedsSurplus(uint256 requestedAmount, uint256 availableSurplus);
    error AmountMustBeGreaterThanZero();
    error FeePercentageExceedsLimit();
    error ArrayLengthMismatch(uint256 length1, uint256 length2);
    error SecondsToFinalizationExceedsLimit(uint256 value);
    error WithdrawalRequestDoesNotExist(uint256 tokenId);
    error IndexExceedsTokenCount(uint256 index, uint256 tokenCount);
    error IndexNotAdvanced(uint256 newIndex, uint256 currentIndex);
    error InvalidFinalizationId(uint256 finalizationId);
    error TokenIdNotInFinalizationRange(uint256 tokenId, uint256 finalizationId, uint256 startIndex, uint256 endIndex);

    //--------------------------------------------------------------------------------------
    //----------------------------------  ROLES  -------------------------------------------
    //--------------------------------------------------------------------------------------

    /// @dev Role identifier for administrators who can manage the withdrawal queue settings.
    bytes32 public constant WITHDRAWAL_QUEUE_ADMIN_ROLE = keccak256("WITHDRAWAL_QUEUE_ADMIN_ROLE");

    /// @dev Role identifier for accounts authorized to withdraw surplus redemption assets.
    bytes32 public constant REDEMPTION_ASSET_WITHDRAWER_ROLE = keccak256("REDEMPTION_ASSET_WITHDRAWER_ROLE");

    /// @dev Role identifier for accounts authorized to finalize withdrawal requests.
    bytes32 public constant REQUEST_FINALIZER_ROLE = keccak256("REQUEST_FINALIZER_ROLE");

    //--------------------------------------------------------------------------------------
    //----------------------------------  CONSTANTS  ---------------------------------------
    //--------------------------------------------------------------------------------------

    uint256 constant public FEE_PRECISION = 1000000;
    uint256 constant public MAX_SECONDS_TO_FINALIZATION = 3600 * 24 * 28; // 4 weeks

    //--------------------------------------------------------------------------------------
    //----------------------------------  VARIABLES  ---------------------------------------
    //-------------------------------------------------------------------------------------- // @todo - move all mappings to a struct

    /// @notice The asset that can be redeemed through withdrawal requests.
    IRedeemableAsset public redeemableAsset;

    /// @notice The vault where redemption assets are stored.
    IRedemptionAssetsVault public redemptionAssetsVault;

    /// @notice Counter for tracking the next token ID to be assigned.
    // uint256 public _tokenIdCounter;
    mapping(IERC20 => uint256) public _tokenIdCounter;

    /// @notice Mapping of token IDs to their corresponding withdrawal requests.
    // mapping(uint256 => WithdrawalRequest) public withdrawalRequests;
    mapping(IERC20 => mapping(uint256 => WithdrawalRequest)) public withdrawalRequests;

    /// @notice The required duration in seconds between a withdrawal request and when it can be finalized.
    // uint256 public secondsToFinalization; // not used

    /// @notice The fee percentage charged on withdrawals.
    uint256 public withdrawalFee;

    /// @notice The address where withdrawal fees are sent.
    address public feeReceiver;

    /// @notice The address authorized to finalize withdrawal requests.
    address public requestFinalizer;

    /// @notice pending requested redemption amount in redemption unit of account
    // uint256 public pendingRequestedRedemptionAmount;
    mapping(IERC20 => uint256) public pendingRequestedRedemptionAmount;

    // uint256 public lastFinalizedIndex;
    mapping(IERC20 => uint256) public lastFinalizedIndex;

    /// @notice Array to store finalization data
    // Finalization[] public finalizations;
    mapping(IERC20 => Finalization[]) public finalizations;

    //--------------------------------------------------------------------------------------
    //----------------------------------  INITIALIZATION  ----------------------------------
    //--------------------------------------------------------------------------------------

    constructor() {
       _disableInitializers();
    }

    struct Init {
        string name;
        string symbol;
        IRedeemableAsset redeemableAsset;
        IRedemptionAssetsVault redemptionAssetsVault;
        address admin;
        address withdrawalQueueAdmin;
        address redemptionAssetWithdrawer;
        uint256 withdrawalFee;
        address feeReceiver;
        address requestFinalizer;

    }

    function initialize(Init memory init)
        public
        notZeroAddress(address(init.admin))
        notZeroAddress(address(init.redeemableAsset))
        notZeroAddress(address(init.redemptionAssetsVault))
        notZeroAddress(address(init.withdrawalQueueAdmin))
        notZeroAddress(address(init.feeReceiver))
        notZeroAddress(address(init.requestFinalizer))
    
        initializer {
        __ERC721_init(init.name, init.symbol);
        redeemableAsset = init.redeemableAsset;
        redemptionAssetsVault = init.redemptionAssetsVault;

        _grantRole(DEFAULT_ADMIN_ROLE, init.admin);
        _grantRole(WITHDRAWAL_QUEUE_ADMIN_ROLE, init.withdrawalQueueAdmin);
        _grantRole(REDEMPTION_ASSET_WITHDRAWER_ROLE, init.redemptionAssetWithdrawer);
        _grantRole(REQUEST_FINALIZER_ROLE, init.requestFinalizer);

        withdrawalFee = init.withdrawalFee;
        feeReceiver = init.feeReceiver;
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  WITHDRAWAL REQUESTS  -----------------------------
    //--------------------------------------------------------------------------------------

    // @todo - make sure we have enough balance of _asset that is restaked (maxRedeem(asset,amount))
    function requestWithdrawal(
        IERC20 _asset,
        uint256 _amount,
        bytes calldata _data
    ) public nonReentrant returns (uint256 _tokenId) {
        if (_amount == 0) revert AmountMustBeGreaterThanZero();

        redeemableAsset.safeTransferFrom(msg.sender, address(this), _amount);

        uint256 _currentRate = redemptionAssetsVault.redemptionRate(_asset);
        _tokenId = _tokenIdCounter[_asset]++;
        withdrawalRequests[_asset][_tokenId] = WithdrawalRequest({
            amount: _amount,
            feeAtRequestTime: withdrawalFee,
            redemptionRateAtRequestTime: _currentRate,
            creationTimestamp: block.timestamp,
            processed: false,
            data: _data
        });

        pendingRequestedRedemptionAmount[_asset] += calculateRedemptionAmount(_amount, _currentRate);

        _mint(msg.sender, _tokenId);

        emit WithdrawalRequested(_tokenId, msg.sender, _amount);
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  CLAIMS  ------------------------------------------
    //--------------------------------------------------------------------------------------

    function claimWithdrawal(IERC20 _asset, uint256 _tokenId, address _receiver) public nonReentrant {
        if (msg.sender != _ownerOf(_tokenId) && msg.sender != _getApproved(_tokenId))
            revert CallerNotOwnerNorApproved(_tokenId, msg.sender);

        uint256 _finalizationId = findFinalizationForTokenId(_asset, _tokenId);
        if (_finalizationId >= finalizations[_asset].length) revert InvalidFinalizationId(_finalizationId);

        Finalization memory _finalization = finalizations[_asset][_finalizationId];
        if (_tokenId < _finalization.startIndex || _tokenId >= _finalization.endIndex)
            revert TokenIdNotInFinalizationRange(_tokenId, _finalizationId, _finalization.startIndex, _finalization.endIndex);

        WithdrawalRequest memory _request = withdrawalRequests[_asset][_tokenId];
        if (!withdrawalRequestExists(_request)) revert WithdrawalRequestDoesNotExist(_tokenId);
        if (_request.processed) revert WithdrawalAlreadyProcessed(_tokenId);

        if (!withdrawalRequestIsFinalized(_asset, _tokenId)) revert NotFinalized(_tokenId);

        uint256 _unitOfAccountAmount = calculateRedemptionAmount(
            _request.amount,
            _request.redemptionRateAtRequestTime < _finalization.redemptionRate
            ? _request.redemptionRateAtRequestTime
            : _finalization.redemptionRate
        );

        withdrawalRequests[_asset][_tokenId].processed = true;
        pendingRequestedRedemptionAmount[_asset] -= _unitOfAccountAmount;

        _burn(_tokenId);
        redeemableAsset.burn(_request.amount);

        uint256 _feeAmount = calculateFee(_unitOfAccountAmount, _request.feeAtRequestTime);

        uint256 _currentBalance = redemptionAssetsVault.availableRedemptionAssets(address(_asset));
        if (_currentBalance < _unitOfAccountAmount) revert InsufficientBalance(_currentBalance, _unitOfAccountAmount);

        redemptionAssetsVault.transferRedemptionAssets(address(_asset), _receiver, _unitOfAccountAmount - _feeAmount, _request.data);
        if (_feeAmount > 0) redemptionAssetsVault.transferRedemptionAssets(address(_asset), feeReceiver, _feeAmount, _request.data);

        // emit WithdrawalClaimed(tokenId, msg.sender, receiver, request, finalizationId); // @todo
    }

    // /**
    //  * @notice Allows a batch of withdrawals to be claimed by their respective token IDs.
    //  * @param tokenIds An array of token IDs corresponding to the withdrawal requests to be claimed.
    //  * @param receivers An array of addresses to receive the claimed withdrawals.
    //  * @dev The length of tokenIds and receivers must be the same.
    //  */
    // function claimWithdrawals(uint256[] calldata tokenIds, address[] calldata receivers) external {
    //     if (tokenIds.length != receivers.length) {
    //         revert ArrayLengthMismatch(tokenIds.length, receivers.length);
    //     }

    //     for (uint256 i = 0; i < tokenIds.length; i++) {
    //         claimWithdrawal(tokenIds[i], receivers[i]);
    //     }
    // }

    // /**
    //  * @notice Allows a batch of withdrawals to be claimed by their respective token IDs.
    //  * @param claims An array of claims corresponding to the withdrawal requests to be claimed.
    //  */
    // function claimWithdrawals(WithdrawalClaim[] calldata claims) external {
    //     for (uint256 i = 0; i < claims.length; i++) {
    //         WithdrawalClaim memory claim = claims[i];
    //         claimWithdrawal(claim);
    //     }
    // }

    //--------------------------------------------------------------------------------------
    //----------------------------------  ADMIN  -------------------------------------------
    //--------------------------------------------------------------------------------------

    /**
     * @notice Sets the withdrawal fee percentage.
     * @param feePercentage The fee percentage in basis points.
     */
    function setWithdrawalFee(uint256 feePercentage) external onlyRole(WITHDRAWAL_QUEUE_ADMIN_ROLE) {
        if (feePercentage > FEE_PRECISION) {
            revert FeePercentageExceedsLimit();
        }
        withdrawalFee = feePercentage;
        emit WithdrawalFeeUpdated(feePercentage);
    }

    /**
     * @notice Sets the address where withdrawal fees are sent.
     * @param _feeReceiver The address that will receive the withdrawal fees.
     */
    function setFeeReceiver(
        address _feeReceiver
        ) external notZeroAddress(_feeReceiver) onlyRole(WITHDRAWAL_QUEUE_ADMIN_ROLE) {

        emit FeeReceiverUpdated(feeReceiver, _feeReceiver);
        feeReceiver = _feeReceiver;
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  COMPUTATIONS  ------------------------------------
    //--------------------------------------------------------------------------------------

    /**
     * @notice Calculates the redemption amount based on the provided amount and the redemption rate at the time of request.
     * @param amount The amount of the redeemable asset.
     * @param redemptionRate The redemption rate expressed in the same unit of decimals as the redeemable asset.
     * @return The calculated redemption amount, adjusted for the decimal places of the redeemable asset.
     */
    function calculateRedemptionAmount(
        uint256 amount,
        uint256 redemptionRate
    ) public view returns (uint256) {
        return amount * redemptionRate / (10 ** redeemableAsset.decimals());
    }

    /**
     * @notice Calculates the withdrawal fee based on the amount and the current fee percentage.
     * @param amount The amount from which the fee should be calculated.
     * @param requestWithdrawalFee The current fee percentage in basis points.
     * @return fee The calculated fee.
     */
    function calculateFee(uint256 amount, uint256 requestWithdrawalFee) public pure returns (uint256) {
        return (amount * requestWithdrawalFee) / FEE_PRECISION;
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  REDEMPTION ASSETS  -------------------------------
    //--------------------------------------------------------------------------------------

    function surplusRedemptionAssets(IERC20 _asset) public view returns (uint256) {
        uint256 _availableAmount = redemptionAssetsVault.availableRedemptionAssets(address(_asset));
        uint256 _pendingRequestedAmount = pendingRequestedRedemptionAmount[_asset];
        if (_availableAmount > _pendingRequestedAmount) return _availableAmount - _pendingRequestedAmount;
        return 0;
    }

    function deficitRedemptionAssets(IERC20 _asset) external view returns (uint256) {
        uint256 _availableAmount = redemptionAssetsVault.availableRedemptionAssets(address(_asset));
        uint256 _pendingRequestedAmount = pendingRequestedRedemptionAmount[_asset];
        if (_pendingRequestedAmount > _availableAmount) return _pendingRequestedAmount - _availableAmount;
        return 0;
    }

    function withdrawSurplusRedemptionAssets(IERC20 _asset, uint256 _amount) external onlyRole(REDEMPTION_ASSET_WITHDRAWER_ROLE) {
        uint256 _surplus = surplusRedemptionAssets(_asset);
        if (_amount > _surplus) revert AmountExceedsSurplus(_amount, _surplus);
        redemptionAssetsVault.withdrawRedemptionAssets(_asset, _amount);
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  FINALITY  ----------------------------------------
    //--------------------------------------------------------------------------------------

    /**
     * @notice Checks if a withdrawal request with a given index is finalized.
     * @param index The index of the withdrawal request.
     * @return True if the request is finalized, false otherwise.
     */
    function withdrawalRequestIsFinalized(IERC20 asset, uint256 index) public view returns (bool) {
        return index < lastFinalizedIndex[asset];
    }

    function finalizeRequestsUpToIndex(
        IERC20 _asset,
        uint256 _lastFinalizedIndex
    ) external onlyRole(REQUEST_FINALIZER_ROLE) returns (uint256 _finalizationIndex) {

        uint256 _currentRate = redemptionAssetsVault.redemptionRate(_asset);
        
        // Create a new Finalization struct
        Finalization memory _newFinalization = Finalization({
            startIndex: SafeCast.toUint64(lastFinalizedIndex[_asset]),
            endIndex: SafeCast.toUint64(_lastFinalizedIndex),
            redemptionRate: SafeCast.toUint96(_currentRate)
        });

        _finalizationIndex = finalizations[_asset].length;
        
        // Add the new Finalization to the array
        finalizations[_asset].push(_newFinalization);

        if (_lastFinalizedIndex > _tokenIdCounter[_asset]) revert IndexExceedsTokenCount(_lastFinalizedIndex, _tokenIdCounter[_asset]);
        if (_lastFinalizedIndex <= lastFinalizedIndex[_asset]) revert IndexNotAdvanced(_lastFinalizedIndex, lastFinalizedIndex[_asset]);

        emit RequestsFinalized(_finalizationIndex, _lastFinalizedIndex, lastFinalizedIndex[_asset], _currentRate);

        lastFinalizedIndex[_asset] = _lastFinalizedIndex;
    }

    function findFinalizationForTokenId(IERC20 _asset, uint256 tokenId) public view returns (uint256 finalizationId) {

        uint256 finalizationsLength = finalizations[_asset].length;
        if (finalizationsLength == 0) {
            revert NotFinalized(tokenId);
        }

        uint256 left = 0;
        uint256 right = finalizationsLength - 1;

        while (left <= right) {
            uint256 mid = (left + right) / 2;
            Finalization memory finalization = finalizations[_asset][mid];

            if (tokenId >= finalization.startIndex && tokenId < finalization.endIndex) {
                return mid;
            } else if (tokenId < finalization.startIndex) {
                right = mid - 1;
            } else {
                left = mid + 1;
            }
        }

        revert NotFinalized(tokenId);
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  VIEWS  -------------------------------------------
    //--------------------------------------------------------------------------------------

    function withdrawalRequest(IERC20 _asset, uint256 tokenId) public view returns (WithdrawalRequest memory request) {
        request = withdrawalRequests[_asset][tokenId];
        if (!withdrawalRequestExists(request)) {
            revert WithdrawalRequestDoesNotExist(tokenId);
        }
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(AccessControlUpgradeable, ERC721EnumerableUpgradeable) returns (bool) {
        return interfaceId == type(IERC721).interfaceId || super.supportsInterface(interfaceId);
    }

    /**
     * @notice Checks if a withdrawal request exists.
     * @param request The withdrawal request to check.
     * @return True if the request exists, false otherwise.
     * @dev Reverts with WithdrawalRequestDoesNotExist if the request does not exist.
     */
    function withdrawalRequestExists(WithdrawalRequest memory request) internal view returns (bool) {
        return request.creationTimestamp > 0;
    }

    function withdrawalRequestsForOwner(IERC20 asset, address owner) public view returns (
        uint256[] memory withdrawalIndexes,
        WithdrawalRequest[] memory requests
    ) {

        uint256 tokenCount = balanceOf(owner);
        if (tokenCount == 0) {
            return (new uint256[](0), new WithdrawalRequest[](0));
        } else {
            
            withdrawalIndexes = new uint256[](tokenCount);
            requests = new WithdrawalRequest[](tokenCount);
            for (uint256 i = 0; i < tokenCount; i++) {
                uint256 tokenId = tokenOfOwnerByIndex(owner, i);
                withdrawalIndexes[i] = tokenId;
                requests[i] = withdrawalRequests[asset][tokenId];
            }
            return (withdrawalIndexes, requests);
        }
    }

    /**
     * @notice Returns the details of a finalization.
     * @param finalizationId The ID of the finalization.
     * @return finalization The finalization details.
     */
    function getFinalization(IERC20 _asset, uint256 finalizationId) public view returns (Finalization memory finalization) {
        if (finalizationId >= finalizations[_asset].length) {
            revert InvalidFinalizationId(finalizationId);
        }
        finalization = finalizations[_asset][finalizationId];
    }

    /**
     * @notice Returns the total number of finalizations.
     * @return count The number of finalizations.
     */
    function finalizationsCount(IERC20 _asset) public view returns (uint256 count) {
        return finalizations[_asset].length;
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  MODIFIERS  ---------------------------------------
    //--------------------------------------------------------------------------------------

    /**
     * @notice Ensure that the given address is not the zero address.
     * @param _address The address to check.
     */
    modifier notZeroAddress(address _address) {
        if (_address == address(0)) {
            revert ZeroAddress();
        }
        _;
    }
}

