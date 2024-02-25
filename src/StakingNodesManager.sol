// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "./StakingNode.sol";
import "./libraries/DepositRootGenerator.sol";
import "./interfaces/IDepositContract.sol";
import "./interfaces/IStakingNode.sol";
import "./interfaces/IRewardsDistributor.sol";
import "./interfaces/IDepositPool.sol";
import "./interfaces/IynETH.sol";
import "./interfaces/eigenlayer-init-mainnet/IDelegationManager.sol";
import "./interfaces/eigenlayer-init-mainnet/IEigenPodManager.sol";
import "forge-std/StdMath.sol";
import "forge-std/console.sol";


interface StakingNodesManagerEvents {
     event StakingNodeCreated(address indexed nodeAddress, address indexed podAddress);   
     event ValidatorRegistered(uint nodeId, bytes signature, bytes pubKey, bytes32 depositRoot);
    event MaxNodeCountUpdated(uint maxNodeCount);
}

contract StakingNodesManager is
    IStakingNodesManager,
    Initializable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    StakingNodesManagerEvents {

    //--------------------------------------------------------------------------------------
    //----------------------------------  ERRORS  ------------------------------------------
    //--------------------------------------------------------------------------------------

    error MinimumStakeBoundNotSatisfied();
    error StakeBelowMinimumynETHAmount(uint256 ynETHAmount, uint256 expectedMinimum);
    error DepositAllocationUnbalanced(uint nodeId, uint256 nodeBalance, uint256 averageBalance, uint256 newNodeBalance, uint256 newAverageBalance);
    error DepositRootChanged(bytes32 _depositRoot, bytes32 onchainDepositRoot);
    error ValidatorAlreadyUsed(bytes publicKey);
    error DepositDataRootMismatch(bytes32 depositDataRoot, bytes32 expectedDepositDataRoot);
    error DirectETHDepositsNotAllowed();
    error InvalidNodeId(uint nodeId);

    //--------------------------------------------------------------------------------------
    //----------------------------------  ROLES  -------------------------------------------
    //--------------------------------------------------------------------------------------

    /// @notice  Role is allowed to set system parameters
    bytes32 public constant STAKING_ADMIN_ROLE = keccak256("STAKING_ADMIN_ROLE");

    /// @notice  Role controls all staking nodes
    bytes32 public constant STAKING_NODES_ADMIN_ROLE = keccak256("STAKING_NODES_ADMIN_ROLE");

    /// @notice  Role is able to register validators
    bytes32 public constant VALIDATOR_MANAGER_ROLE = keccak256("VALIDATOR_MANAGER_ROLE");

    //--------------------------------------------------------------------------------------
    //----------------------------------  CONSTANTS  ---------------------------------------
    //--------------------------------------------------------------------------------------

    uint constant DEFAULT_VALIDATOR_STAKE = 32 ether;

    //--------------------------------------------------------------------------------------
    //----------------------------------  VARIABLES  ---------------------------------------
    //--------------------------------------------------------------------------------------

    IEigenPodManager public eigenPodManager;
    IDepositContract public depositContractEth2;
    IDelegationManager public delegationManager;
    IDelayedWithdrawalRouter public delayedWithdrawalRouter;
    IStrategyManager public strategyManager;

    address public implementationContract;
    UpgradeableBeacon private upgradableBeacon;

    IynETH public ynETH;
    IRewardsDistributor rewardsDistributor;

    bytes[] public validators;

    uint128 public maxBatchDepositSize;
    uint128 public stakeAmount;

    /**
    /**
     * @notice Each node in the StakingNodesManager manages an EigenPod. 
     * An EigenPod represents a collection of validators and their associated staking activities within the EigenLayer protocol. 
     * The StakingNode contract, which each node is an instance of, interacts with the EigenPod to perform various operations such as:
     * - Creating the EigenPod upon the node's initialization if it does not already exist.
     * - Delegating staking operations to the EigenPod, including processing rewards and managing withdrawals.
     * - Verifying withdrawal credentials and managing expedited withdrawals before restaking.
     * 
     * This design allows for delegating to multiple operators simultaneously while also being gas efficient.
     * Grouping multuple validators per EigenPod allows delegation of all their stake with 1 delegationManager.delegateTo(operator) call.
     */
    IStakingNode[] public nodes;
    uint public maxNodeCount;

    mapping(bytes pubkey => bool) usedValidators;

    //--------------------------------------------------------------------------------------
    //----------------------------------  INITIALIZATION  ----------------------------------
    //--------------------------------------------------------------------------------------

    /// @notice Configuration for contract initialization.
    struct Init {
        address admin;
        address stakingAdmin;
        address stakingNodesAdmin;
        address validatorManager;
        uint maxNodeCount;
        IDepositContract depositContract;
        IynETH ynETH;
        IEigenPodManager eigenPodManager;
        IDelegationManager delegationManager;
        IDelayedWithdrawalRouter delayedWithdrawalRouter;
        IStrategyManager strategyManager;
        IRewardsDistributor rewardsDistributor; // Added rewardsDistributor dependency
    }
    
    function initialize(Init memory init) external initializer {
        __AccessControl_init();
        __ReentrancyGuard_init();

        _grantRole(DEFAULT_ADMIN_ROLE, init.admin);
        _grantRole(STAKING_ADMIN_ROLE, init.stakingAdmin);
        _grantRole(VALIDATOR_MANAGER_ROLE, init.validatorManager);
        _grantRole(STAKING_NODES_ADMIN_ROLE, init.stakingNodesAdmin);

        depositContractEth2 = init.depositContract;
        maxNodeCount = init.maxNodeCount;
        eigenPodManager = init.eigenPodManager;
        ynETH = init.ynETH;
        delegationManager = init.delegationManager;
        delayedWithdrawalRouter = init.delayedWithdrawalRouter;
        strategyManager = init.strategyManager;
        rewardsDistributor = init.rewardsDistributor;
    }


    receive() external payable {
        require(msg.sender == address(ynETH));
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  VALIDATOR REGISTRATION  --------------------------
    //--------------------------------------------------------------------------------------

    function registerValidators(
        bytes32 _depositRoot,
        ValidatorData[] calldata newValidators
    ) public onlyRole(VALIDATOR_MANAGER_ROLE) nonReentrant {

        if (newValidators.length == 0) {
            return;
        }

        // check deposit root matches the deposit contract deposit root
        // to prevent front-running from rogue operators 
        bytes32 onchainDepositRoot = depositContractEth2.get_deposit_root();
        if (_depositRoot != onchainDepositRoot) {
            revert DepositRootChanged({_depositRoot: _depositRoot, onchainDepositRoot: onchainDepositRoot});
        }

        validateDepositDataAllocation(newValidators);

        uint totalDepositAmount = newValidators.length * DEFAULT_VALIDATOR_STAKE;
        ynETH.withdrawETH(totalDepositAmount); // Withdraw ETH from depositPool

        uint validatorsLength = newValidators.length;
        for (uint i = 0; i < validatorsLength; i++) {

            ValidatorData calldata validator = newValidators[i];
            if (usedValidators[validator.publicKey]) {
                revert ValidatorAlreadyUsed(validator.publicKey);
            }
            usedValidators[validator.publicKey] = true;

            _registerValidator(validator, DEFAULT_VALIDATOR_STAKE);
        }
    }

    /**
     * @notice Validates the allocation of deposit data across nodes to ensure the distribution does not increase the disparity in balances.
     * @dev This function checks if the proposed allocation of deposits (represented by `_depositData`) across the nodes would lead to a more
     * equitable distribution of validator stakes. It calculates the current and new average balances of nodes, and ensures that for each node,
     * the absolute difference between its balance and the average balance does not increase as a result of the new deposits
     * @param newValidators An array of `ValidatorData` structures representing the validator stakes to be allocated across the nodes.
     */
    function validateDepositDataAllocation(ValidatorData[] calldata newValidators) public view {
        uint[] memory nodeBalances = new uint[](nodes.length);
        uint[] memory newNodeBalances = new uint[](nodes.length); // New array with same values as nodeBalances
        uint totalBalance = 0;
        for (uint i = 0; i < nodes.length; i++) {
            nodeBalances[i] = IStakingNode(nodes[i]).getETHBalance();
            newNodeBalances[i] = nodeBalances[i]; // Assigning the value from nodeBalances to newNodeBalances
            totalBalance += nodeBalances[i];
        }

        if (totalBalance == 0) {
            return;
        }
        uint averageBalance = totalBalance / nodes.length;

        uint newTotalBalance = totalBalance;
        for (uint i = 0; i < newValidators.length; i++) {
            uint nodeId = newValidators[i].nodeId;

            if (nodeId >= nodes.length) {
                revert InvalidNodeId(nodeId);
            }
            newNodeBalances[nodeId] += DEFAULT_VALIDATOR_STAKE;
            newTotalBalance += DEFAULT_VALIDATOR_STAKE;
        }
        uint newAverageBalance = newTotalBalance / nodes.length;

        for (uint i = 0; i < nodes.length; i++) {
            if (stdMath.abs(int256(nodeBalances[i]) - int256(averageBalance)) < stdMath.abs(int256(newNodeBalances[i]) - int256(newAverageBalance))) {
                revert DepositAllocationUnbalanced(i, nodeBalances[i], averageBalance, newNodeBalances[i], newAverageBalance);
            }
        }
    }

    /// @notice Creates validator object and deposits into beacon chain
    /// @param validator Data structure to hold all data needed for depositing to the beacon chain
    function _registerValidator(
        ValidatorData calldata validator, 
        uint256 _depositAmount
    ) internal {

        uint256 nodeId = validator.nodeId;
        bytes memory withdrawalCredentials = getWithdrawalCredentials(nodeId);
        bytes32 depositDataRoot = depositRootGenerator.generateDepositRoot(validator.publicKey, validator.signature, withdrawalCredentials, _depositAmount);
        if (depositDataRoot != validator.depositDataRoot) {
            revert DepositDataRootMismatch(depositDataRoot, validator.depositDataRoot);
        }

        // Deposit to the Beacon Chain
        depositContractEth2.deposit{value: _depositAmount}(validator.publicKey, withdrawalCredentials, validator.signature, depositDataRoot);

        validators.push(validator.publicKey);

        // notify node of ETH _depositAmount
        IStakingNode(nodes[nodeId]).allocateStakedETH(_depositAmount);

        emit ValidatorRegistered(
            nodeId,
            validator.signature,
            validator.publicKey,
            depositDataRoot
        );
    }

    function generateDepositRoot(
        bytes calldata publicKey,
        bytes calldata signature,
        bytes memory withdrawalCredentials,
        uint256 depositAmount
    ) public pure returns (bytes32) {
        return depositRootGenerator.generateDepositRoot(publicKey, signature, withdrawalCredentials, depositAmount);
    }

    function getWithdrawalCredentials(uint256 nodeId) public view returns (bytes memory) {

        address eigenPodAddress = address(IStakingNode(nodes[nodeId]).eigenPod());
        return generateWithdrawalCredentials(eigenPodAddress);
    }

    /// @notice Generates withdraw credentials for a validator
    /// @param _address associated with the validator for the withdraw credentials
    /// @return the generated withdraw key for the node
    function generateWithdrawalCredentials(address _address) public pure returns (bytes memory) {   
        return abi.encodePacked(bytes1(0x01), bytes11(0x0), _address);
    }


    //--------------------------------------------------------------------------------------
    //----------------------------------  STAKING NODE CREATION  ---------------------------
    //--------------------------------------------------------------------------------------

    function createStakingNode() public returns (IStakingNode) {

        require(nodes.length < maxNodeCount, "StakingNodesManager: nodes.length >= maxNodeCount");

        BeaconProxy proxy = new BeaconProxy(address(upgradableBeacon), "");
        StakingNode node = StakingNode(payable(proxy));

        uint nodeId = nodes.length;

        node.initialize(
            IStakingNode.Init(IStakingNodesManager(address(this)), strategyManager, nodeId)
        );
 
        IEigenPod eigenPod = node.createEigenPod();

        nodes.push(node);

        emit StakingNodeCreated(address(node), address(eigenPod));

        return node;
    }

    function registerStakingNodeImplementationContract(address _implementationContract) onlyRole(STAKING_ADMIN_ROLE) public {

        require(_implementationContract != address(0), "StakingNodesManager:No zero address");
        require(implementationContract == address(0), "StakingNodesManager: Implementation already exists");

        upgradableBeacon = new UpgradeableBeacon(_implementationContract, address(this));     
        implementationContract = _implementationContract;
    }

    function upgradeStakingNodeImplementation(address _implementationContract, bytes memory callData) public onlyRole(STAKING_ADMIN_ROLE) {

        require(implementationContract != address(0), "StakingNodesManager: A Staking node implementation has never been registered");
        require(_implementationContract != address(0), "StakingNodesManager: Implementation cannot be zero address");
        upgradableBeacon.upgradeTo(_implementationContract);
        implementationContract = _implementationContract;

        if (callData.length == 0) {
            // no function to initialize with
            return;
        }
        // reinitialize all nodes
        for (uint i = 0; i < nodes.length; i++) {
            (bool success, ) = address(nodes[i]).call(callData);
            require(success, "StakingNodesManager: Failed to call method on upgraded node");
        }
    }

    /// @notice Sets the maximum number of staking nodes allowed
    /// @param _maxNodeCount The maximum number of staking nodes
    function setMaxNodeCount(uint _maxNodeCount) public onlyRole(STAKING_ADMIN_ROLE) {
        maxNodeCount = _maxNodeCount;
        emit MaxNodeCountUpdated(_maxNodeCount);
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  WITHDRAWALS  -------------------------------------
    //--------------------------------------------------------------------------------------

    function processWithdrawnETH(uint nodeId, uint withdrawnValidatorPrincipal) external payable {
        require(address(nodes[nodeId]) == msg.sender, "msg.sender does not match nodeId");

        uint rewards = msg.value - withdrawnValidatorPrincipal;

        IRewardsReceiver consensusLayerReceiver = rewardsDistributor.consensusLayerReceiver();
        (bool sent, ) = address(consensusLayerReceiver).call{value: rewards}("");
        require(sent, "Failed to send rewards");

        ynETH.processWithdrawnETH{value: withdrawnValidatorPrincipal}();
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  VIEWS  -------------------------------------------
    //--------------------------------------------------------------------------------------

    function getAllValidators() public view returns (bytes[] memory) {
        return validators;
    }

    function getAllNodes() public view returns (IStakingNode[] memory) {
        return nodes;
    }

    function nodesLength() public view returns (uint256) {
        return nodes.length;
    }

    function isStakingNodesAdmin(address _address) public view returns (bool) {
        // TODO: define specific admin
        return hasRole(STAKING_NODES_ADMIN_ROLE, _address);
    }

}
