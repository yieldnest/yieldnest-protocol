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
import "./interfaces/eigenlayer/IDelegationManager.sol";

interface StakingNodesManagerEvents {
     event EigenPodCreated(address indexed nodeAddress, address indexed podAddress);   
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
    address public eigenPodManager;
    IDepositContract public depositContractEth2;
    IDepositPool public depositPool; // Added depositPool variable
    IDelegationManager public delegationManager;

    uint128 public maxBatchDepositSize;
    uint128 public stakeAmount;

    address[] public nodes;
    uint maxNodeCount;

    uint constant DEFAULT_NODE_INDEX  = 0;
    uint DEFAULT_VALIDATOR_STAKE = 32 ether;

     //--------------------------------------------------------------------------------------
    //----------------------------------  CONSTRUCTOR   ------------------------------------
    //--------------------------------------------------------------------------------------

    /// @notice Configuration for contract initialization.
    struct Init {
        address admin;
        uint maxNodeCount;
        IDepositContract depositContract;
        IDepositPool _depositPool; // Added depositPool to Init struct
    }

    constructor() {
    }

    function initialize(Init memory init) external {
        __AccessControl_init();
       __ReentrancyGuard_init();

        _grantRole(DEFAULT_ADMIN_ROLE, init.admin);
        depositContractEth2 = init.depositContract;
        depositPool = init._depositPool; // Initialized depositPool
        maxNodeCount = init.maxNodeCount;
    }

    function registerValidators(
        bytes32 _depositRoot,
        DepositData[] calldata _depositData
    ) public onlyRole(DEFAULT_ADMIN_ROLE) nonReentrant verifyDepositState(_depositRoot) {

        uint totalDepositAmount = _depositData.length * DEFAULT_VALIDATOR_STAKE;
        depositPool.withdrawETH(totalDepositAmount); // Withdraw ETH from depositPool

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


        emit ValidatorRegistered(
            nodeId,
            _depositData.signature,
            _depositData.publicKey,
            depositDataRoot
        );
    }

    function getNextNodeIdToUse() internal view returns (uint) {
        // Use only 1 node with eigenpod to start with
        return DEFAULT_NODE_INDEX;
    }

    function getWithdrawalCredentials(uint256 nodeId) public view returns (bytes memory) {

        address eigenPodAddress = IStakingNode(nodes[nodeId]).eigenPod();
        return generateWithdrawalCredentials(eigenPodAddress);
    }

    /// @notice Generates withdraw credentials for a validator
    /// @param _address associated with the validator for the withdraw credentials
    /// @return the generated withdraw key for the node
    function generateWithdrawalCredentials(address _address) public pure returns (bytes memory) {   
        return abi.encodePacked(bytes1(0x01), bytes11(0x0), _address);
    }


    function createStakingNode() public returns (address) {

        require(nodes.length < maxNodeCount, "StakingNodesManager: nodes.length >= maxNodeCount");

        BeaconProxy proxy = new BeaconProxy(address(upgradableBeacon), "");
        StakingNode node = StakingNode(payable(proxy));

       
        node.initialize(
            IStakingNode.Init(IStakingNodesManager(address(this)))
        );
 
        node.createEigenPod();

        nodes.push(address(node));

        return address(node);
    }


    function registerStakingNodeImplementationContract(address _implementationContract) onlyRole(DEFAULT_ADMIN_ROLE) public {
        require(implementationContract == address(0), "Address already set");
        require(_implementationContract != address(0), "No zero addresses");

        implementationContract = _implementationContract;
        upgradableBeacon = new UpgradeableBeacon(implementationContract, address(this));      
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
