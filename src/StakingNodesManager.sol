pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "./StakingNode.sol";
import "./libraries/DepositRootGenerator.sol";
import "./interfaces/IDepositContract.sol";
import "./interfaces/IStakingNode.sol";
import "./interfaces/IDepositPool.sol";
import "./interfaces/IynETH.sol";
import "./interfaces/eigenlayer/IDelegationManager.sol";
import "./interfaces/eigenlayer/IEigenPodManager.sol";

interface StakingNodesManagerEvents {
     event StakingNodeCreated(address indexed nodeAddress, address indexed podAddress);   
     event ValidatorRegistered(uint nodeId, bytes signature, bytes pubKey, bytes32 depositRoot);
}


contract StakingNodesManager is
    IStakingNodesManager,
    Initializable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    StakingNodesManagerEvents {

    address public implementationContract;
    UpgradeableBeacon private upgradableBeacon;
    IEigenPodManager public eigenPodManager;
    IDepositContract public depositContractEth2;
    IDelegationManager public delegationManager;
    IynETH public ynETH;

    bytes[] public validators;


    uint128 public maxBatchDepositSize;
    uint128 public stakeAmount;

    address[] public nodes;
    uint public maxNodeCount;

    uint constant DEFAULT_NODE_INDEX  = 0;
    uint constant DEFAULT_VALIDATOR_STAKE = 32 ether;

     //--------------------------------------------------------------------------------------
    //----------------------------------  CONSTRUCTOR   ------------------------------------
    //--------------------------------------------------------------------------------------

    /// @notice Configuration for contract initialization.
    struct Init {
        address admin;
        uint maxNodeCount;
        IDepositContract depositContract;
        IEigenPodManager eigenPodManager;
        IynETH ynETH;
    }
    
    function initialize(Init memory init) external initializer {
        __AccessControl_init();
       __ReentrancyGuard_init();

        _grantRole(DEFAULT_ADMIN_ROLE, init.admin);
        depositContractEth2 = init.depositContract;
        maxNodeCount = init.maxNodeCount;
        eigenPodManager = init.eigenPodManager;
        ynETH = init.ynETH;
    }

    function registerValidators(
        bytes32 _depositRoot,
        DepositData[] calldata _depositData
    ) public onlyRole(DEFAULT_ADMIN_ROLE) nonReentrant verifyDepositState(_depositRoot) {

        uint totalDepositAmount = _depositData.length * DEFAULT_VALIDATOR_STAKE;

        ynETH.withdrawETH(totalDepositAmount); // Withdraw ETH from depositPool

        for (uint x = 0; x < _depositData.length; ++x) {
            _registerValidator(_depositData[x], DEFAULT_VALIDATOR_STAKE);
        }
    }

    /// @notice Creates validator object and deposits into beacon chain
    /// @param _depositData Data structure to hold all data needed for depositing to the beacon chain
    /// however, instead of the validator key, it will include the IPFS hash
    /// containing the validator key encrypted by the corresponding node operator's public key
    function _registerValidator(
        DepositData calldata _depositData, 
        uint256 _depositAmount
    ) internal {

        uint256 nodeId = getNextNodeIdToUse();
        bytes memory withdrawalCredentials = getWithdrawalCredentials(nodeId);
        bytes32 depositDataRoot = depositRootGenerator.generateDepositRoot(_depositData.publicKey, _depositData.signature, withdrawalCredentials, _depositAmount);
        require(depositDataRoot == _depositData.depositDataRoot, "Deposit data root mismatch");

        // Deposit to the Beacon Chain
        depositContractEth2.deposit{value: _depositAmount}(_depositData.publicKey, withdrawalCredentials, _depositData.signature, depositDataRoot);

        validators.push(_depositData.publicKey);

        emit ValidatorRegistered(
            nodeId,
            _depositData.signature,
            _depositData.publicKey,
            depositDataRoot
        );
    }

    function getNextNodeIdToUse() public pure returns (uint) {
        // Use only 1 node with eigenpod to start with
        // TODO: create logic for selecting from a set of N
        return DEFAULT_NODE_INDEX;
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

    function createStakingNode() public returns (IStakingNode) {

        require(nodes.length < maxNodeCount, "StakingNodesManager: nodes.length >= maxNodeCount");

        BeaconProxy proxy = new BeaconProxy(address(upgradableBeacon), "");
        StakingNode node = StakingNode(payable(proxy));

        uint nodeId = nodes.length;

        node.initialize(
            IStakingNode.Init(IStakingNodesManager(address(this)), nodeId)
        );
 
        IEigenPod eigenPod = node.createEigenPod();

        nodes.push(address(node));

        emit StakingNodeCreated(address(node), address(eigenPod));

        return node;
    }

    function registerStakingNodeImplementationContract(address _implementationContract) onlyRole(DEFAULT_ADMIN_ROLE) public {
        require(implementationContract == address(0), "Address already set");
        require(_implementationContract != address(0), "No zero addresses");

        implementationContract = _implementationContract;
        upgradableBeacon = new UpgradeableBeacon(implementationContract, address(this));      
    }

    function processWithdrawnETH(uint nodeId) external payable {
        require(nodes[nodeId] == msg.sender, "msg.sender does not match nodeId");

        ynETH.processWithdrawnETH{value: msg.value}();
    }

    function getAllValidators() public view returns (bytes[] memory) {
        return validators;
    }

    function nodesLength() public view returns (uint256) {
        return nodes.length;
    }

    function isStakingNodesAdmin(address _address) public view returns (bool) {
        // TODO: define specific admin
        return hasRole(DEFAULT_ADMIN_ROLE, _address);
    }


    // Receive
    receive() external payable {
        require(msg.sender == address(ynETH));
    }

    //--------------------------------------------------------------------------------------
    //-----------------------------------  MODIFIERS  --------------------------------------
    //--------------------------------------------------------------------------------------
    
    modifier verifyDepositState(bytes32 _depositRoot) {
        // disable deposit root check if none provided
        if (_depositRoot != 0x0000000000000000000000000000000000000000000000000000000000000000) {
            bytes32 onchainDepositRoot = depositContractEth2.get_deposit_root();
            require(_depositRoot == onchainDepositRoot, "deposit root changed");
        }
        _;
    }
}
