// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {IStakingNodesManager} from "./interfaces/IStakingNodesManager.sol";
import {IynETH} from "./interfaces/IynETH.sol";
import {
    IWithdrawalRequestQueue,
    IWithdrawalRequestQueueEvents,
    WithdrawalRequest
} from "./interfaces/IWithdrawalRequestQueue.sol";

/// @title WithdrawalRequestQueue
/// @notice Manages withdrawal requests from the staking contract.
contract WithdrawalRequestQueue is
    Initializable,
    AccessControlUpgradeable,
    IWithdrawalRequestQueue,
    IWithdrawalRequestQueueEvents
{
    // Errors.
    error AlreadyClaimed();
    error DoesNotReceiveETH();
    error NotEnoughFunds(uint256 cumulativeETHOnRequest, uint256 allocatedETHForClaims);
    error NotFinalized();
    error NotRequester();
    error NotStakingContract();

    /// @notice Role allowed to set properties of the contract.
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    /// @notice The staking contract to which the withdrawal request queue accepts claims and new withdrawal requests from.
    IStakingNodesManager public stakingContract;
    IynETH public ynETH;


    /// @notice The total amount of ether sent by the staking contract.
    /// @dev This value can be decreased when reclaiming surplus allocatedETHs.
    uint256 public allocatedETHForClaims;

    /// @dev Cache the latest cumulative ETH requested value instead of checking latest element in the array.
    /// This prevents encountering an invalid value if someone claims the request which resets it.
    uint128 public latestCumulativeETHRequested;

    /// @dev The internal queue of withdrawal requests.
    WithdrawalRequest[] internal _withdrawalRequests;

    /// @notice Configuration for contract initialization.
    struct Init {
        address admin;
        address manager;
        IynETH ynETH;
        IStakingNodesManager stakingContract;
    }

    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the contract.
    /// @dev MUST be called during the contract upgrade to set up the proxies state.
    function initialize(Init memory init) external initializer {
        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, init.admin);
        stakingContract = init.stakingContract;
        ynETH = init.ynETH;

        _grantRole(MANAGER_ROLE, init.manager);
    }

    /// @inheritdoc IWithdrawalRequestQueue
    /// @dev Increases the cumulative ETH requested counter and pushes a new withdrawal request to the array. This function
    /// can only be called by the staking contract.
    function create(address requester, uint128 ynETHLocked, uint128 ethRequested)
        external
        onlyStakingContract
        returns (uint256)
    {
        uint128 currentCumulativeETHRequested = latestCumulativeETHRequested + ethRequested;
        uint256 requestID = _withdrawalRequests.length;
        WithdrawalRequest memory withdrawalRequest = WithdrawalRequest({
            id: uint128(requestID),
            requester: requester,
            ynETHLocked: ynETHLocked,
            ethRequested: ethRequested,
            cumulativeETHRequested: currentCumulativeETHRequested,
            blockNumber: uint64(block.number),
            isFinalized: false
        });
        _withdrawalRequests.push(withdrawalRequest);

        latestCumulativeETHRequested = currentCumulativeETHRequested;
        emit WithdrawalRequestCreated(
            requestID, requester, ynETHLocked, ethRequested, currentCumulativeETHRequested, block.number
        );
        return requestID;
    }

    /// @inheritdoc IWithdrawalRequestQueue
    /// @dev Verifies the requester's identity, finality of the request, and availability of funds before transferring
    /// the requested ETH. The withdrawal request is then removed from the array.
    function claim(uint256 requestID, address requester) external onlyStakingContract {
        WithdrawalRequest memory request = _withdrawalRequests[requestID];

        if (request.requester == address(0)) {
            revert AlreadyClaimed();
        }

        if (requester != request.requester) {
            revert NotRequester();
        }

        if (!_isFinalized(request)) {
            revert NotFinalized();
        }

        if (request.cumulativeETHRequested > allocatedETHForClaims) {
            revert NotEnoughFunds(request.cumulativeETHRequested, allocatedETHForClaims);
        }

        delete _withdrawalRequests[requestID];

        emit WithdrawalRequestClaimed({
            id: requestID,
            requester: requester,
            ynETHLocked: request.ynETHLocked,
            ethRequested: request.ethRequested,
            cumulativeETHRequested: request.cumulativeETHRequested,
            blockNumber: request.blockNumber
        });

        // TODO: reenable burn
        // ynETH.burn(request.ynETHLocked);

        Address.sendValue(payable(requester), request.ethRequested);
    }


    /// @inheritdoc IWithdrawalRequestQueue
    /// @dev Handles incoming ether from the staking contract, increasing the allocatedETHForClaims counter by the value
    /// of the incoming allocatedETH.
    function allocateETH() external payable onlyStakingContract {
        allocatedETHForClaims += msg.value;
    }

    /// @notice Returns the ID of the next withdrawal requests to be created.
    function nextRequestId() external view returns (uint256) {
        return _withdrawalRequests.length;
    }

    /// @inheritdoc IWithdrawalRequestQueue
    function requestByID(uint256 requestID) external view returns (WithdrawalRequest memory) {
        return _withdrawalRequests[requestID];
    }

    /// @notice Finalizes a withdrawal request, allowing it to be claimed.
    /// @param requestID The ID of the withdrawal request to finalize.
    function finalize(uint256 requestID) external onlyRole(MANAGER_ROLE) {
        _withdrawalRequests[requestID].isFinalized = true;
    }

    /// @notice Used by the claim function to check whether the request can be claimed (i.e. is finalized).
    /// @dev Finalization relies on the latest record of the oracle.
    /// @return A boolean indicating whether the withdrawal request is finalized or not.
    function _isFinalized(WithdrawalRequest memory request) internal pure returns (bool) {
        return request.isFinalized;
    }

    /// @dev Validates that the caller is the staking contract.
    modifier onlyStakingContract() {
        if (msg.sender != address(stakingContract)) {
            revert NotStakingContract();
        }
        _;
    }

    // Fallbacks.
    receive() external payable {
        revert DoesNotReceiveETH();
    }

    fallback() external payable {
        revert DoesNotReceiveETH();
    }
}
