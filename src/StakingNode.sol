pragma solidity ^0.8.0;

import "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";
import "./interfaces/eigenlayer/IEigenPodManager.sol";
import "./interfaces/IStakingNode.sol";
import "./interfaces/IStakingNodesManager.sol";
import "./interfaces/eigenlayer/IDelegationManager.sol";
import "./external/eigenlayer/BeaconChainProofs.sol";


interface StakingNodeEvents {
     event EigenPodCreated(address indexed nodeAddress, address indexed podAddress);   
     event Delegated(address indexed operator, ISignatureUtils.SignatureWithExpiry approverSignatureAndExpiry, bytes32 approverSalt);
}

contract StakingNode is IStakingNode, StakingNodeEvents {

    // Errors.
    error NotStakingNodesAdmin();

    IStrategy public constant beaconChainETHStrategy = IStrategy(0xbeaC0eeEeeeeEEeEeEEEEeeEEeEeeeEeeEEBEaC0);
    uint256 public constant GWEI_TO_WEI = 1e9;

    IStakingNodesManager public stakingNodesManager;
    IStrategyManager public strategyManager;
    IEigenPod public eigenPod;
    uint public nodeId;

    /// @dev Monitors the ETH balance that was committed to validators allocated to this StakingNode
    uint256 public totalETHNotRestaked;


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

    function initialize(Init memory init) external {
        require(address(stakingNodesManager) == address(0), "already initialized");
        require(address(init.stakingNodesManager) != address(0), "No zero addresses");

        stakingNodesManager = init.stakingNodesManager;
        strategyManager = init.strategyManager;
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
    /// This activates the activation of the staked funds within EigenLayer
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

        for (uint i = 0; i < validatorIndices.length; i++) {

            // TODO: check if this is correct
            uint64 validatorCurrentBalanceGwei = BeaconChainProofs.getEffectiveBalanceGwei(validatorFields[i]);

            totalETHNotRestaked -= (validatorCurrentBalanceGwei * 1e9);
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
        queuedWithdrawalParams[0].strategies[0] = beaconChainETHStrategy;
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
        uint shares,
        uint32 startBlock
    ) external onlyAdmin {

        IDelegationManager delegationManager = stakingNodesManager.delegationManager();

        uint[] memory sharesArray = new uint[](1);
        sharesArray[0] = shares;

        IStrategy[] memory strategiesArray = new IStrategy[](1);
        strategiesArray[0] = beaconChainETHStrategy;

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

    /// @dev Record total staked ETH for this StakingNode
    function allocateStakedETH( uint amount) external payable onlyStakingNodesManager {
        totalETHNotRestaked += amount;
    }

    function getETHBalance() public view returns (uint) {

        // 1 Beacon Chain ETH strategy share = 1 ETH
        // TODO: handle the withdrawal situation - this means that ETH will reside in the eigenpod at some point
        uint consensusLayerRewards = address(eigenPod).balance;
        return totalETHNotRestaked + consensusLayerRewards + strategyManager.stakerStrategyShares(address(this), beaconChainETHStrategy);
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
