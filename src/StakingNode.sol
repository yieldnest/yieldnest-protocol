pragma solidity ^0.8.0;

import "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";
import "./interfaces/eigenlayer/IEigenPodManager.sol";
import "./interfaces/IStakingNode.sol";
import "./interfaces/IStakingNodesManager.sol";
import "./interfaces/eigenlayer/IDelegationManager.sol";

interface StakingNodeEvents {
     event EigenPodCreated(address indexed nodeAddress, address indexed podAddress);   

     event Delegated(address indexed operator, ISignatureUtils.SignatureWithExpiry approverSignatureAndExpiry, bytes32 approverSalt);
}

contract StakingNode is IStakingNode, StakingNodeEvents {

    // Errors.
    error NotStakingNodesAdmin();

    IStakingNodesManager public stakingNodesManager;
    IEigenPod public eigenPod;
    uint public nodeId;

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
        nodeId = init.nodeId;
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  DEPOSIT AND DELEGATION   -------------------------
    //--------------------------------------------------------------------------------------


    function createEigenPod() public returns (IEigenPod) {
        if (address(eigenPod) != address(0x0)) return IEigenPod(address(0)); // already have pod

        IEigenPodManager eigenPodManager = IEigenPodManager(IStakingNodesManager(stakingNodesManager).eigenPodManager());
        eigenPodManager.createPod();
        eigenPod = eigenPodManager.getPod(address(this));
        emit EigenPodCreated(address(this), address(eigenPod));

        return eigenPod;
    }

    function delegate(address operator) public {

        IDelegationManager delegationManager = stakingNodesManager.delegationManager();

        // Only supports empty approverSignatureAndExpiry and approverSalt
        // this applies when no IDelegationManager.OperatorDetails.delegationApprover is specified by operator
        // TODO: add support for operators that require signatures
        ISignatureUtils.SignatureWithExpiry memory approverSignatureAndExpiry;
        bytes32 approverSalt;

        delegationManager.delegateTo(operator, approverSignatureAndExpiry, approverSalt);

        emit Delegated(operator, approverSignatureAndExpiry, approverSalt);
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

        // TODO: reenable this using the contract's new functions from the latest version

        // Decrement the staked but not verified ETH
        // uint64 validatorCurrentBalanceGwei = BeaconChainProofs.getBalanceFromBalanceRoot(validatorIndex, proofs.balanceRoot);
        //stakedButNotVerifiedEth -= (validatorCurrentBalanceGwei * GWEI_TO_WEI);
    }

    function testFoo() public view returns (uint) {
        return 12412515;
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  WITHDRAWAL AND UNDELEGATION   --------------------
    //--------------------------------------------------------------------------------------


    /*
    *  Withdrawal Flow:
    *
    *  1. queueWithdrawals() - Admin queues withdrawals
    *  2. undelegate() - Admin undelegates
    *  3. verifyAndProcessWithdrawals() - Admin verifies and processes withdrawals
    *  4. completeWithdrawal() - Admin completes withdrawal
    *
    */


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

    function undelegate() public onlyAdmin {
        
        IDelegationManager delegationManager = stakingNodesManager.delegationManager();
        delegationManager.undelegate(address(this));
    }

    function verifyAndProcessWithdrawals(
        uint64 oracleTimestamp,
        IEigenPod.StateRootProof calldata stateRootProof,
        IEigenPod.WithdrawalProof[] calldata withdrawalProofs,
        bytes[] calldata validatorFieldsProofs,
        bytes32[][] calldata validatorFields,
        bytes32[][] calldata withdrawalFields
    ) external onlyAdmin {
    
        eigenPod.verifyAndProcessWithdrawals(
            oracleTimestamp,
            stateRootProof,
            withdrawalProofs,
            validatorFieldsProofs,
            validatorFields,
            withdrawalFields
        );
    }

    function completeWithdrawal(
        IDelegationManager.Withdrawal[] calldata withdrawals,
        IERC20[][] calldata tokens,
        uint256[] calldata middlewareTimesIndexes,
        bool[] calldata receiveAsTokens
    ) external onlyAdmin {

        IDelegationManager delegationManager = stakingNodesManager.delegationManager();

        uint256 balanceBefore = address(this).balance;

        delegationManager.completeQueuedWithdrawals(withdrawals, tokens, middlewareTimesIndexes, receiveAsTokens);

        uint256 balanceAfter = address(this).balance;
        uint256 fundsWithdrawn = balanceAfter - balanceBefore;

        stakingNodesManager.processWithdrawnETH{value: fundsWithdrawn}(nodeId);
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
