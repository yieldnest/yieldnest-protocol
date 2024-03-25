pragma solidity >=0.8.12;

import { BeaconChainProofs } from "../../../../src/external/eigenlayer/v0.2.1/BeaconChainProofs.sol";
import {IEigenPodManager} from "../../../../src/external/eigenlayer/v0.2.1/interfaces/IEigenPodManager.sol";
import {IEigenPod} from "../../../../src/external/eigenlayer/v0.2.1/interfaces/IEigenPod.sol";

import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

abstract contract TestnetInitializableMock {
    /**
     * @dev Indicates that the contract has been initialized.
     * @custom:oz-retyped-from bool
     */
    uint8 private _initialized;

    /**
     * @dev Indicates that the contract is in the process of being initialized.
     */
    bool private _initializing;

}

abstract contract TestnetReentrancyGuardUpgradeableMock is TestnetInitializableMock {
    // Booleans are more expensive than uint256 or any type that takes up a full
    // word because each write operation emits an extra SLOAD to first read the
    // slot's contents, replace the bits taken up by the boolean, and then write
    // back. This is the compiler's defense against contract upgrades and
    // pointer aliasing, and it cannot be disabled.

    // The values being non-zero value makes deployment a bit more expensive,
    // but in exchange the refund on every call to nonReentrant will be lower in
    // amount. Since refunds are capped to a percentage of the total
    // transaction's gas, it is best to keep them low in cases like this one, to
    // increase the likelihood of the full refund coming into effect.
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    uint256 private _status;

     /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[49] private __gap;
}

contract TestnetEigenPodMock is TestnetReentrancyGuardUpgradeableMock {

    // CONSTANTS + IMMUTABLES
    // @notice Internal constant used in calculations, since the beacon chain stores balances in Gwei rather than wei
    uint256 internal constant GWEI_TO_WEI = 1e9;

    /// @notice Emitted when an ETH validator's withdrawal credentials are successfully verified to be pointed to this eigenPod
    event ValidatorRestaked(uint40 validatorIndex);

    /// @notice Emitted when an ETH validator's  balance is proven to be updated.  Here newValidatorBalanceGwei
    //  is the validator's balance that is credited on EigenLayer.
    event ValidatorBalanceUpdated(uint40 validatorIndex, uint64 balanceTimestamp, uint64 newValidatorBalanceGwei);


    ///@notice The maximum amount of ETH, in gwei, a validator can have restaked in the eigenlayer
    uint64 public immutable MAX_RESTAKED_BALANCE_GWEI_PER_VALIDATOR;
    /// @notice The single EigenPodManager for EigenLayer
    IEigenPodManager public immutable eigenPodManager;

    // STORAGE VARIABLES
    /// @notice The owner of this EigenPod
    address public podOwner;

    /**
     * @notice The latest timestamp at which the pod owner withdrew the balance of the pod, via calling `withdrawBeforeRestaking`.
     * @dev This variable is only updated when the `withdrawBeforeRestaking` function is called, which can only occur before `hasRestaked` is set to true for this pod.
     * Proofs for this pod are only valid against Beacon Chain state roots corresponding to timestamps after the stored `mostRecentWithdrawalTimestamp`.
     */
    uint64 public mostRecentWithdrawalTimestamp;

    /// @notice the amount of execution layer ETH in this contract that is staked in EigenLayer (i.e. withdrawn from the Beacon Chain but not from EigenLayer),
    uint64 public withdrawableRestakedExecutionLayerGwei;

    /// @notice an indicator of whether or not the podOwner has ever "fully restaked" by successfully calling `verifyCorrectWithdrawalCredentials`.
    bool public hasRestaked;

    /// @notice This is a mapping of validatorPubkeyHash to timestamp to whether or not they have proven a withdrawal for that timestamp
    mapping(bytes32 => mapping(uint64 => bool)) public provenWithdrawal;

    /// @notice This is a mapping that tracks a validator's information by their pubkey hash
    mapping(bytes32 => IEigenPod.ValidatorInfo) internal _validatorPubkeyHashToInfo;

    /// @notice This variable tracks any ETH deposited into this contract via the `receive` fallback function
    uint256 public nonBeaconChainETHBalanceWei;

    /// @notice This variable tracks the total amount of partial withdrawals claimed via merkle proofs prior to a switch to ZK proofs for claiming partial withdrawals
    uint64 public sumOfPartialWithdrawalsClaimedGwei;

    /// @notice Number of validators with proven withdrawal credentials, who do not have proven full withdrawals
    uint256 activeValidatorCount;


    constructor(IEigenPodManager _eigenPodManager) {
        eigenPodManager = _eigenPodManager;
        MAX_RESTAKED_BALANCE_GWEI_PER_VALIDATOR = 32e9;
    }

    function verifyWithdrawalCredentials(
        uint64 oracleTimestamp,
        BeaconChainProofs.StateRootProof calldata stateRootProof,
        uint40[] calldata validatorIndices,
        bytes[] calldata validatorFieldsProofs,
        bytes32[][] calldata validatorFields
    )
        external
    {
        require(
            (validatorIndices.length == validatorFieldsProofs.length) &&
                (validatorFieldsProofs.length == validatorFields.length),
            "EigenPod.verifyWithdrawalCredentials: validatorIndices and proofs must be same length"
        );

        uint256 totalAmountToBeRestakedWei;
        for (uint256 i = 0; i < validatorIndices.length; i++) {
            totalAmountToBeRestakedWei += _verifyWithdrawalCredentials(
                oracleTimestamp,
                stateRootProof.beaconStateRoot,
                validatorIndices[i],
                validatorFieldsProofs[i],
                validatorFields[i]
            );
        }

        // Update the EigenPodManager on this pod's new balance
        eigenPodManager.recordBeaconChainETHBalanceUpdate(podOwner, int256(totalAmountToBeRestakedWei));
    }


    function _verifyWithdrawalCredentials(
        uint64 oracleTimestamp,
        bytes32 beaconStateRoot,
        uint40 validatorIndex,
        bytes calldata validatorFieldsProof,
        bytes32[] calldata validatorFields
    ) internal returns (uint256) {
        bytes32 validatorPubkeyHash = BeaconChainProofs.getPubkeyHash(validatorFields);
        IEigenPod.ValidatorInfo memory validatorInfo = _validatorPubkeyHashToInfo[validatorPubkeyHash];


        // Proofs complete - update this validator's status, record its proven balance, and save in state:
        activeValidatorCount++;
        validatorInfo.status = IEigenPod.VALIDATOR_STATUS.ACTIVE;
        validatorInfo.validatorIndex = validatorIndex;
        validatorInfo.mostRecentBalanceUpdateTimestamp = oracleTimestamp;

        validatorInfo.restakedBalanceGwei = MAX_RESTAKED_BALANCE_GWEI_PER_VALIDATOR;

        _validatorPubkeyHashToInfo[validatorPubkeyHash] = validatorInfo;

        emit ValidatorRestaked(validatorIndex);
        emit ValidatorBalanceUpdated(validatorIndex, oracleTimestamp, validatorInfo.restakedBalanceGwei);

        return validatorInfo.restakedBalanceGwei * GWEI_TO_WEI;
    }


    function _podWithdrawalCredentials() internal view returns (bytes memory) {
        return abi.encodePacked(bytes1(uint8(1)), bytes11(0), address(this));
    }

    function sethasRestaked(bool v) public {
        hasRestaked = v;
    }

}
