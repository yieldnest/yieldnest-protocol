pragma solidity ^0.8.0;

import "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";
import "./interfaces/eigenlayer-init-mainnet/IEigenPodManager.sol";
import "./interfaces/IStakingNode.sol";
import "./interfaces/IStakingNodesManager.sol";
import "./interfaces/eigenlayer-init-mainnet/IDelegationManager.sol";
import "./interfaces/eigenlayer-init-mainnet/BeaconChainProofs.sol";
import "forge-std/console.sol";


interface StakingNodeEvents {
     event EigenPodCreated(address indexed nodeAddress, address indexed podAddress);   
     event Delegated(address indexed operator, bytes32 approverSalt);
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

    function delegate(address operator) public virtual onlyAdmin {

        IDelegationManager delegationManager = stakingNodesManager.delegationManager();

        delegationManager.delegateTo(operator);

        emit Delegated(operator, 0);
    }

    function verifyWithdrawalCredentials(
        uint64[] calldata oracleBlockNumber,
        uint40[] calldata validatorIndex,
        BeaconChainProofs.ValidatorFieldsAndBalanceProofs[] calldata proofs,
        bytes32[][] calldata validatorFields
    ) external virtual onlyAdmin {

        require(oracleBlockNumber.length == validatorIndex.length, "Mismatched oracleBlockNumber and validatorIndex lengths");
        require(validatorIndex.length == proofs.length, "Mismatched validatorIndex and proofs lengths");
        require(validatorIndex.length == validatorFields.length, "Mismatched proofs and validatorFields lengths");

        for (uint i = 0; i < validatorIndex.length; i++) {
            eigenPod.verifyWithdrawalCredentialsAndBalance(
                oracleBlockNumber[i],
                validatorIndex[i],
                proofs[i],
                validatorFields[i]
            );

            // Decrement the staked but not verified ETH
            uint64 validatorBalanceGwei = BeaconChainProofs.getBalanceFromBalanceRoot(validatorIndex[i], proofs[i].balanceRoot);
             
            totalETHNotRestaked -= (validatorBalanceGwei * 1e9);
        }
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
