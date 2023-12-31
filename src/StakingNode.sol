pragma solidity ^0.8.0;

import "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";
import "./interfaces/eigenlayer/IEigenPodManager.sol";
import "./interfaces/IStakingNode.sol";
import "./interfaces/IStakingNodesManager.sol";
import "./interfaces/eigenlayer/IDelegationManager.sol";


interface StakingNodeEvents {
     event EigenPodCreated(address indexed nodeAddress, address indexed podAddress);   
}

contract StakingNode is IStakingNode, StakingNodeEvents {

    // Errors.
    error NotStakingNodesAdmin();

    IStakingNodesManager public stakingNodesManager;
    IEigenPod public eigenPod;

    /// @dev Monitors the balance that was committed to validators but hasn't been re-committed to EigenLayer yet
    //uint256 public stakedButNotVerifiedEth;


    /// @dev Allows only a whitelisted address to configure the contract
    modifier onlyAdmin() {
        if(!stakingNodesManager.isStakingNodesAdmin(msg.sender)) revert NotStakingNodesAdmin();
        _;
    }

     //--------------------------------------------------------------------------------------
    //----------------------------------  CONSTRUCTOR   ------------------------------------
    //--------------------------------------------------------------------------------------

    constructor() {
    }

    ///  To receive the rewards from the execution layer, it should have 'receive()' function.
    receive() external payable {}

    function initialize(Init memory init) external {
        require(address(stakingNodesManager) == address(0), "already initialized");
        require(address(init.stakingNodesManager) != address(0), "No zero addresses");

        stakingNodesManager = init.stakingNodesManager;
    }

    function createEigenPod() public returns (IEigenPod) {
        if (address(eigenPod) != address(0x0)) return IEigenPod(address(0)); // already have pod

        IEigenPodManager eigenPodManager = IEigenPodManager(IStakingNodesManager(stakingNodesManager).eigenPodManager());
        eigenPodManager.createPod();
        eigenPod = eigenPodManager.getPod(address(this));
        emit EigenPodCreated(address(this), address(eigenPod));

        return eigenPod;
    }

    function delegate() public {

        IDelegationManager delegationManager = stakingNodesManager.delegationManager();

        // Only supports empty approverSignatureAndExpiry and approverSalt
        // this applies when no IDelegationManager.OperatorDetails.delegationApprover is specified by operator
        // TODO: add support for operators that require signatures
        ISignatureUtils.SignatureWithExpiry memory approverSignatureAndExpiry;
        bytes32 approverSalt;

        delegationManager.delegateTo(msg.sender, approverSignatureAndExpiry, approverSalt);
    }

    function queueWithdrawals(uint shares) public onlyAdmin {
    
        IDelegationManager delegationManager = stakingNodesManager.delegationManager();

        IDelegationManager.QueuedWithdrawalParams[] memory queuedWithdrawalParams = new IDelegationManager.QueuedWithdrawalParams[](1);
        queuedWithdrawalParams[0] = IDelegationManager.QueuedWithdrawalParams({
            strategies: new IStrategy[](1),
            shares: new uint256[](1),
            withdrawer: address(this)
        });
        queuedWithdrawalParams[0].strategies[0] = delegationManager.beaconChainETHStrategy();
        queuedWithdrawalParams[0].shares[0] = shares;
        delegationManager.queueWithdrawals(queuedWithdrawalParams);
    }

    /// @dev Validates the withdrawal credentials for a withdrawal
    /// This enables the EigenPodManager to validate the withdrawal credentials and allocate the OD with shares
    function verifyWithdrawalCredentials(
        uint64 oracleTimestamp,
        IEigenPod.StateRootProof calldata stateRootProof,
        uint40[] calldata validatorIndices,
        bytes[] calldata withdrawalCredentialProofs,
        bytes32[][] calldata validatorFields
    ) external onlyAdmin {
        eigenPod.verifyWithdrawalCredentials(
            oracleTimestamp,
            stateRootProof,
            validatorIndices,
            withdrawalCredentialProofs,
            validatorFields
        );

        // Decrement the staked but not verified ETH
        // uint64 validatorCurrentBalanceGwei = BeaconChainProofs.getBalanceFromBalanceRoot(validatorIndex, proofs.balanceRoot);
        //stakedButNotVerifiedEth -= (validatorCurrentBalanceGwei * GWEI_TO_WEI);
    }

    /**
      Beacons slot value is defined here:
      https://github.com/OpenZeppelin/openzeppelin-contracts/blob/afb20119b33072da041c97ea717d3ce4417b5e01/contracts/proxy/ERC1967/ERC1967Upgrade.sol#L142
     */
    function implementation() public view returns (address) {
        bytes32 slot = bytes32(uint256(keccak256('eip1967.proxy.beacon')) - 1);
        address implementationVariable;
        assembly {
            implementationVariable := sload(slot)
        }

        IBeacon beacon = IBeacon(implementationVariable);
        return beacon.implementation();
    }
}
