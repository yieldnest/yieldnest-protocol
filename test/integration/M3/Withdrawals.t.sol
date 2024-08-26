// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

// import {EigenPod} from "lib/eigenlayer-contracts/src/contracts/pods/EigenPod.sol";

import {IStakingNode} from "../../../src/interfaces/IStakingNode.sol";
import {IStakingNodesManager} from "../../../src/interfaces/IStakingNodesManager.sol";

import "./Base.t.sol";

interface IPod {
    function verifyWithdrawalCredentials(
        uint64 beaconTimestamp,
        BeaconChainProofs.StateRootProof calldata stateRootProof,
        uint40[] calldata validatorIndices,
        bytes[] calldata validatorFieldsProofs,
        bytes32[][] calldata validatorFields
    ) external;
}

contract M3WithdrawalsTest is Base {

    uint256 AMOUNT = 32 ether;
    uint256 NODE_ID = 0;
    bytes constant ZERO_PUBLIC_KEY = hex"000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"; 
    // bytes constant ONE_PUBLIC_KEY = hex"000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001";
    // bytes constant TWO_PUBLIC_KEY = hex"000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002";
    bytes constant  ZERO_SIGNATURE = hex"000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";
    bytes32 constant ZERO_DEPOSIT_ROOT = bytes32(0);

    function setUp() public override {
        super.setUp();

        // deposit 32 ETH into ynETH
        address _user = vm.addr(420);
        vm.deal(_user, AMOUNT);
        vm.prank(_user);
        yneth.depositETH{value: AMOUNT}(_user);
    }

    // todo - mock the BEACON_ROOTS_ADDRESS and update it's address in the EL eigenpod contract
    function testVerifyWithdrawalCredentials() public {
        bytes memory _withdrawalCredentials = stakingNodesManager.getWithdrawalCredentials(NODE_ID);
        uint40 _validatorIndex = beaconChain.newValidator{ value: AMOUNT }(_withdrawalCredentials);
        beaconChain.advanceEpoch_NoRewards();

        uint40[] memory _validators = new uint40[](1);
        _validators[0] = _validatorIndex;
        CredentialProofs memory proofs = beaconChain.getCredentialProofs(_validators);

        IStakingNode _node = stakingNodesManager.nodes(NODE_ID);
        {
            vm.prank(address(_node.stakingNodesManager()));
            _node.initializeV2(AMOUNT);
        }

        vm.prank(actors.ops.STAKING_NODES_OPERATOR);
        IPod(address(_node)).verifyWithdrawalCredentials({
            beaconTimestamp: proofs.beaconTimestamp,
            stateRootProof: proofs.stateRootProof,
            validatorIndices: _validators,
            validatorFieldsProofs: proofs.validatorFieldsProofs,
            validatorFields: proofs.validatorFields
        });

        // if (block.chainid != 17000) return;

        // // register a new validator
        // {
        //     IStakingNodesManager.ValidatorData[] memory _validatorData = new IStakingNodesManager.ValidatorData[](1);
        //     _validatorData[0] = IStakingNodesManager.ValidatorData({
        //         publicKey: ZERO_PUBLIC_KEY,
        //         signature: ZERO_SIGNATURE,
        //         nodeId: NODE_ID,
        //         depositDataRoot: ZERO_DEPOSIT_ROOT
        //     });

        //     bytes memory _withdrawalCredentials = stakingNodesManager.getWithdrawalCredentials(NODE_ID);
        //     bytes32 _depositDataRoot = stakingNodesManager.generateDepositRoot(ZERO_PUBLIC_KEY, ZERO_SIGNATURE, _withdrawalCredentials, 32 ether);
        //     _validatorData[0].depositDataRoot = _depositDataRoot;
            
        //     vm.prank(actors.ops.VALIDATOR_MANAGER);
        //     stakingNodesManager.registerValidators(_validatorData);
        // }


        // // verify its withdrawal credentials
        // {
        //     IStakingNode[] memory _node = stakingNodesManager.nodes(NODE_ID);
        //     // uint64 beaconTimestamp,
        //     // BeaconChainProofs.StateRootProof calldata stateRootProof,
        //     // uint40[] calldata validatorIndices,
        //     // bytes[] calldata validatorFieldsProofs,
        //     // bytes32[][] calldata validatorFields

        //     vm.prank(actors.ops.STAKING_NODES_OPERATOR);
        //     _node.verifyWithdrawalCredentials(
        //         0, // beaconTimestamp
        //         BeaconChainProofs.StateRootProof({
        //             stateRoot: bytes32(0),
        //             proof: new bytes(0)
        //         }),
        //         new uint40[](0), // validatorIndices
        //         new bytes[](0), // validatorFieldsProofs
        //         new bytes32[][](0) // validatorFields
        //     );
        // }

        // -------------
        // /**
        // * @dev Validates the withdrawal credentials for a withdrawal.
        // * This activates the staked funds within EigenLayer as shares.
        // * verifyWithdrawalCredentials MUST be called for all validators BEFORE they
        // * are exited from the beacon chain to keep the getETHBalance return value consistent.
        // * If a validator is exited without this call, TVL is double counted for its principal.
        // * @param beaconTimestamp The timestamp of the oracle that signed the block.
        // * @param stateRootProof The state root proof.
        // * @param validatorIndices The indices of the validators.
        // * @param validatorFieldsProofs The validator fields proofs.
        // * @param validatorFields The validator fields.
        // */
        // function verifyWithdrawalCredentials(
        //     uint64 beaconTimestamp,
        //     BeaconChainProofs.StateRootProof calldata stateRootProof,
        //     uint40[] calldata validatorIndices,
        //     bytes[] calldata validatorFieldsProofs,
        //     bytes32[][] calldata validatorFields
        // ) external onlyOperator {

        // -------------
    }
    // function setupVerifyWithdrawalCredentialsForProofFileForForeignValidator(
    //     string memory path
    // ) public returns(VerifyWithdrawalCredentialsCallParams memory params) {

    //     // test/data/ValidatorFieldsProof_1293592_8746783.json
    //     setJSON(path);

    //     uint256 depositAmount = 32 ether;
    //     (IStakingNode stakingNodeInstance,) = setupStakingNode(depositAmount);

    //     uint64 oracleTimestamp = uint64(block.timestamp);
    //     MockEigenLayerBeaconOracle mockBeaconOracle = new MockEigenLayerBeaconOracle();

    //     address eigenPodManagerOwner = OwnableUpgradeable(address(eigenPodManager)).owner();
    //     vm.prank(eigenPodManagerOwner);
    //     eigenPodManager.updateBeaconChainOracle(IBeaconChainOracle(address(mockBeaconOracle)));
        
    //     // set existing EigenPod to be the EigenPod of the StakingNode for the 
    //     // purpose of testing verifyWithdrawalCredentials
    //     address eigenPodAddress = getWithdrawalAddress();

    //     MockStakingNode(payable(address(stakingNodeInstance)))
    //         .setEigenPod(IEigenPod(eigenPodAddress));

    //     {
    //         // Upgrade the implementation of EigenPod to be able to alter its owner
    //         EigenPod existingEigenPod = EigenPod(payable(address(stakingNodeInstance.eigenPod())));

    //         MockEigenPod mockEigenPod = new MockEigenPod(
    //             IETHPOSDeposit(existingEigenPod.ethPOS()),
    //             IDelayedWithdrawalRouter(address(delayedWithdrawalRouter)),
    //             IEigenPodManager(address(eigenPodManager)),
    //             existingEigenPod.MAX_RESTAKED_BALANCE_GWEI_PER_VALIDATOR(),
    //             existingEigenPod.GENESIS_TIME()
    //         );

    //         address mockEigenPodAddress = address(mockEigenPod);
    //         IEigenPodManager eigenPodManagerInstance = IEigenPodManager(eigenPodManager);
    //         address eigenPodBeaconAddress = address(eigenPodManagerInstance.eigenPodBeacon());
    //         UpgradeableBeacon eigenPodBeacon = UpgradeableBeacon(eigenPodBeaconAddress);
    //         address eigenPodBeaconOwner = Ownable(eigenPodBeaconAddress).owner();
    //         vm.prank(eigenPodBeaconOwner);
    //         eigenPodBeacon.upgradeTo(mockEigenPodAddress);
    //     }

    //     MockEigenPod mockEigenPodInstance = MockEigenPod(payable(address(stakingNodeInstance.eigenPod())));
    //     mockEigenPodInstance.setPodOwner(address(stakingNodeInstance));


    //     ValidatorProofs memory validatorProofs = getWithdrawalCredentialParams();
    //     bytes32 validatorPubkeyHash = BeaconChainProofs.getPubkeyHash(validatorProofs.validatorFields[0]);
    //     IEigenPod.ValidatorInfo memory zeroedValidatorInfo = IEigenPod.ValidatorInfo({
    //         validatorIndex: 0,
    //         restakedBalanceGwei: 0,
    //         mostRecentBalanceUpdateTimestamp: 0,
    //         status: IEigenPod.VALIDATOR_STATUS.INACTIVE
    //     });
    //     mockEigenPodInstance.setValidatorInfo(validatorPubkeyHash, zeroedValidatorInfo);

    //     {
    //         // Upgrade the implementation of EigenPod to be able to alter the owner of the pod being tested
    //         MockEigenPodManager mockEigenPodManager = new MockEigenPodManager(EigenPodManager(address(eigenPodManager)));
    //         address payable eigenPodManagerPayable = payable(address(eigenPodManager));
    //         ITransparentUpgradeableProxy eigenPodManagerProxy = ITransparentUpgradeableProxy(eigenPodManagerPayable);

    //         address proxyAdmin = Utils.getTransparentUpgradeableProxyAdminAddress(eigenPodManagerPayable);
    //         vm.prank(proxyAdmin);
    //         eigenPodManagerProxy.upgradeTo(address(mockEigenPodManager));
    //     }

    //     {
    //         // mock latest blockRoot
    //         MockEigenPodManager mockEigenPodManagerInstance = MockEigenPodManager(address(eigenPodManager));
    //         mockEigenPodManagerInstance.setHasPod(address(stakingNodeInstance), stakingNodeInstance.eigenPod());

    //         bytes32 latestBlockRoot = _getLatestBlockRoot();
    //         mockBeaconOracle.setOracleBlockRootAtTimestamp(latestBlockRoot);
    //     }


    //     params.oracleTimestamp = oracleTimestamp;
    //     params.stakingNodeInstance = stakingNodeInstance;
    //     params.validatorProofs = validatorProofs;
    // }

    // function testStartCheckpoint
    // function testVerifyCheckpointProofs
    // function todo - start withdrawal flow using `testVerifyCheckpointProofs`
}