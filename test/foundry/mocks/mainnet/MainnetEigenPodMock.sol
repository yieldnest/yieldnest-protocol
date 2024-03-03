pragma solidity >=0.8.12;

import { BeaconChainProofs } from "../../../../src/external/eigenlayer/v0.1.0/BeaconChainProofs.sol";
import {IEigenPodManager} from "../../../../src/external/eigenlayer/v0.1.0/interfaces/IEigenPodManager.sol";
import {IEigenPod} from "../../../../src/external/eigenlayer/v0.1.0/interfaces/IEigenPod.sol";

import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

abstract contract MainnetInitializableMock {
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

abstract contract MainnetReentrancyGuardUpgradeableMock is MainnetInitializableMock {
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

contract MainnetEigenPodMock is MainnetInitializableMock, MainnetReentrancyGuardUpgradeableMock {

    /// @notice The owner of this EigenPod
    address public podOwner;

    /**
     * @notice The latest block number at which the pod owner withdrew the balance of the pod.
     * @dev This variable is only updated when the `withdraw` function is called, which can only occur before `hasRestaked` is set to true for this pod.
     * Proofs for this pod are only valid against Beacon Chain state roots corresponding to blocks after the stored `mostRecentWithdrawalBlockNumber`.
     */
    uint64 public mostRecentWithdrawalBlockNumber;

    // STORAGE VARIABLES
    /// @notice the amount of execution layer ETH in this contract that is staked in EigenLayer (i.e. withdrawn from the Beacon Chain but not from EigenLayer), 
    uint64 public restakedExecutionLayerGwei;

    /// @notice an indicator of whether or not the podOwner has ever "fully restaked" by successfully calling `verifyCorrectWithdrawalCredentials`.
    bool public hasRestaked;

    /// @notice this is a mapping of validator indices to a Validator struct containing pertinent info about the validator
    mapping(uint40 => IEigenPod.VALIDATOR_STATUS) public validatorStatus;

        /// @notice This is a mapping of validatorIndex to withdrawalIndex to whether or not they have proven a withdrawal for that index
    mapping(uint40 => mapping(uint64 => bool)) public provenPartialWithdrawal;

         /// @notice The single EigenPodManager for EigenLayer
    IEigenPodManager public immutable eigenPodManager;

        /// @notice The amount of eth, in wei, that is restaked per ETH validator into EigenLayer
    uint256 public immutable REQUIRED_BALANCE_WEI;


    constructor(IEigenPodManager _eigenPodManager) {
        eigenPodManager = _eigenPodManager;
        REQUIRED_BALANCE_WEI = 32 ether;
    }

    function verifyWithdrawalCredentialsAndBalance(
        uint64 oracleBlockNumber,
        uint40 validatorIndex,
        BeaconChainProofs.ValidatorFieldsAndBalanceProofs calldata proofs,
        bytes32[] calldata validatorFields
    )
        external
    {
        // set the status to active
        validatorStatus[validatorIndex] = IEigenPod.VALIDATOR_STATUS.ACTIVE;

        // Sets "hasRestaked" to true if it hasn't been set yet. 
        if (!hasRestaked) {
            hasRestaked = true;
        }
        (oracleBlockNumber,proofs,validatorFields);

        // virtually deposit REQUIRED_BALANCE_WEI for new ETH validator
        eigenPodManager.restakeBeaconChainETH(podOwner, REQUIRED_BALANCE_WEI);
    }

    function sethasRestaked(bool v) public {
        hasRestaked = v;
    }
}
