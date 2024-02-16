import { BeaconChainProofs } from "../../interfaces/eigenlayer-init-mainnet/BeaconChainProofs.sol";
import "../../interfaces/eigenlayer-init-mainnet/IEigenPodManager.sol";
import "../../interfaces/eigenlayer-init-mainnet/IEigenPod.sol";


contract MainnetEigenPodMock {

     /// @notice The single EigenPodManager for EigenLayer
    IEigenPodManager public immutable eigenPodManager;

        /// @notice The amount of eth, in wei, that is restaked per ETH validator into EigenLayer
    uint256 public immutable REQUIRED_BALANCE_WEI;

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

        // virtually deposit REQUIRED_BALANCE_WEI for new ETH validator
        eigenPodManager.restakeBeaconChainETH(podOwner, REQUIRED_BALANCE_WEI);
    }

    function sethasRestaked(bool v) public {
        hasRestaked = v;
    }
}
