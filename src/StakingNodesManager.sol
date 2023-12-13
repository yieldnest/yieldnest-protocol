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

interface StakingNodesManagerEvents {
     event EigenPodCreated(address indexed nodeAddress, address indexed podAddress);   
     event ValidatorRegistered();
}


contract StakingNodesManager is
    IStakingNodesManager,
    Initializable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    StakingNodesManagerEvents {

    UpgradeableBeacon private upgradableBeacon;
    address public eigenPodManager;
    IDepositContract public depositContractEth2;

    uint128 public maxBatchDepositSize;
    uint128 public stakeAmount;

    address[] nodes;


    function registerValidators(
        bytes32 _depositRoot,
        uint256[] calldata _validatorId,
        DepositData[] calldata _depositData
    ) public nonReentrant verifyDepositState(_depositRoot) {
        require(_validatorId.length <= maxBatchDepositSize, "Too many validators");
        require(_validatorId.length == _depositData.length, "Array lengths must match");

        for (uint256 x; x < _validatorId.length; ++x) {
            _registerValidator(_validatorId[x], _depositData[x], 32 ether);
        }
    }

    /// @notice Creates validator object, mints NFTs, sets NB variables and deposits into beacon chain
    /// @param nodeId ID of the validator to register
    /// @param _depositData Data structure to hold all data needed for depositing to the beacon chain
    /// however, instead of the validator key, it will include the IPFS hash
    /// containing the validator key encrypted by the corresponding node operator's public key
    function _registerValidator(
        uint256 nodeId, 
        DepositData calldata _depositData, 
        uint256 _depositAmount
    ) internal {
        // require(bidIdToStakerInfo[_validatorId].staker == _staker, "Not deposit owner");
        bytes memory withdrawalCredentials = getWithdrawalCredentials(nodeId);
        bytes32 depositDataRoot = depositRootGenerator.generateDepositRoot(_depositData.publicKey, _depositData.signature, withdrawalCredentials, _depositAmount);
        require(depositDataRoot == _depositData.depositDataRoot, "Deposit data root mismatch");

        // Deposit to the Beacon Chain
        depositContractEth2.deposit{value: _depositAmount}(_depositData.publicKey, withdrawalCredentials, _depositData.signature, depositDataRoot);


        emit ValidatorRegistered();
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


    function createStakingNode(bool _createEigenPod) internal returns (address) {
        BeaconProxy proxy = new BeaconProxy(address(upgradableBeacon), "");
        StakingNode node = StakingNode(payable(proxy));
        node.initialize(address(this));
        if (_createEigenPod) {
            node.createEigenPod();
        }

        return address(node);
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
