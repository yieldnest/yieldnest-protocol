pragma solidity ^0.8.0;

import "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";
import "./interfaces/eigenlayer/IEigenPodManager.sol";
import "./interfaces/IStakingNode.sol";
import "./interfaces/IStakingNodesManager.sol";
import "./interfaces/eigenlayer/IDelegationManager.sol";
import "hardhat/console.sol";
import "./external/eigenlayer/BeaconChainProofs.sol";


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
    uint256 public unverifiedStakedETH;


    /// @dev Allows only a whitelisted address to configure the contract
    modifier onlyAdmin() {
        if(!stakingNodesManager.isStakingNodesAdmin(msg.sender)) revert NotStakingNodesAdmin();
        _;
    }

    modifier onlyStakingNodesManager() {
        require(msg.sender == address(stakingNodesManager), "Only StakingNodesManager can call this function");
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
    //----------------------------------  EIGENPOD CREATION   ------------------------------
    //--------------------------------------------------------------------------------------

    function createEigenPod() public returns (IEigenPod) {
        if (address(eigenPod) != address(0x0)) return IEigenPod(address(0)); // already have pod

        IEigenPodManager eigenPodManager = IEigenPodManager(IStakingNodesManager(stakingNodesManager).eigenPodManager());
        eigenPodManager.createPod();
        eigenPod = eigenPodManager.getPod(address(this));
        emit EigenPodCreated(address(this), address(eigenPod));

        return eigenPod;
    }


    //--------------------------------------------------------------------------------------
    //----------------------------------  EXPEDITED WITHDRAWAL   --------------------
    //--------------------------------------------------------------------------------------

     /**
     * @notice  Kicks off a delayed withdraw of the ETH before any restaking has been done (EigenPod.hasRestaked() == false)
     * @dev    To initiate the withdrawal process before any restaking actions have been taken
     * you will need to execute claimQueuedWithdrawals after the necessary time has passed as per the requirements of EigenLayer's
     * DelayedWithdrawalRouter. The funds will reside in the DelayedWithdrawalRouter once they are queued for withdrawal.
     */
    function withdrawBeforeRestaking() external onlyAdmin {
        eigenPod.withdrawBeforeRestaking();
    }

    /// @notice Retrieves and processes withdrawals that have been queued in the EigenPod, transferring them to the StakingNode.
    /// @param maxNumWithdrawals the upper limit of queued withdrawals to process in a single transaction.
    /// @dev Ideally, you should call this with "maxNumWithdrawals" set to the total number of unclaimed withdrawals.
    ///      However, if the queue becomes too large to handle in one transaction, you can specify a smaller number.
    function claimDelayedWithdrawals(uint256 maxNumWithdrawals) public {

        // only claim if we have active unclaimed withdrawals
        IDelayedWithdrawalRouter delayedWithdrawalRouter = stakingNodesManager.delayedWithdrawalRouter();
        if (delayedWithdrawalRouter.getUserDelayedWithdrawals(address(this)).length > 0) {
            delayedWithdrawalRouter.claimDelayedWithdrawals(address(this), maxNumWithdrawals);
        }
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  DEPOSIT AND DELEGATION   -------------------------
    //--------------------------------------------------------------------------------------

    function delegate(address operator) public onlyAdmin {

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

        for (uint i = 0; i < validatorIndices.length; i++) {
            
            uint40 validatorIndex = validatorIndices[i];

            // TODO: check if this is correct
            uint64 validatorCurrentBalanceGwei = BeaconChainProofs.getBalanceAtIndex(stateRootProof.beaconStateRoot, validatorIndex);

            unverifiedStakedETH -= (validatorCurrentBalanceGwei * 1e9);
        }

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

        console.log("queuedWithdrawalParams[0].strategies[0]", address(queuedWithdrawalParams[0].strategies[0]));
        console.log("queuedWithdrawalParams[0].withdrawer", queuedWithdrawalParams[0].withdrawer);

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
        uint shares,
        uint32 startBlock
    ) external onlyAdmin {

        IDelegationManager delegationManager = stakingNodesManager.delegationManager();

        uint[] memory sharesArray = new uint[](1);
        sharesArray[0] = shares;

        IStrategy[] memory strategiesArray = new IStrategy[](1);
        strategiesArray[0] = delegationManager.beaconChainETHStrategy();

        IDelegationManager.Withdrawal memory withdrawal = IDelegationManager.Withdrawal({
            staker: address(this),
            delegatedTo: delegationManager.delegatedTo(address(this)),
            withdrawer: address(this),
            nonce: 0, // TODO: fix
            startBlock: startBlock,
            strategies: strategiesArray,
            shares:  sharesArray
        });

        uint256 balanceBefore = address(this).balance;

        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = IERC20(0x0000000000000000000000000000000000000000);

        // middlewareTimesIndexes is 0, since it's unused
        // https://github.com/Layr-Labs/eigenlayer-contracts/blob/5fd029069b47bf1632ec49b71533045cf00a45cd/src/contracts/core/DelegationManager.sol#L556
        delegationManager.completeQueuedWithdrawal(withdrawal, tokens, 0, true);

        uint256 balanceAfter = address(this).balance;
        uint256 fundsWithdrawn = balanceAfter - balanceBefore;

        stakingNodesManager.processWithdrawnETH{value: fundsWithdrawn}(nodeId);
    }


    /// @dev Gets the amount of ETH staked in the EigenLayer
    function getStakedETHBalance() external view returns (uint256) {
        // TODO: Once withdrawals are enabled, allow this to handle pending withdraws and a potential negative share balance in the EigenPodManager ownershares
        // TODO: Once upgraded to M2, add back in staked verified ETH, e.g. + uint256(strategyManager.stakerStrategyShares(address(this), strategyManager.beaconChainETHStrategy()))
        return unverifiedStakedETH + address(eigenPod).balance;
    }

    /// @dev Record staked ETH 
    function stakeEth( uint amount) external payable onlyStakingNodesManager {
        unverifiedStakedETH += amount;
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
