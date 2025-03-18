// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {ynEigenIntegrationBaseTest} from "test/integration/ynEIGEN/ynEigenIntegrationBaseTest.sol";
import {TestAssetUtils} from "test/utils/TestAssetUtils.sol";
import {IStrategy} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {ITokenStakingNode} from "src/interfaces/ITokenStakingNode.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {ISignatureUtilsMixinTypes} from "lib/eigenlayer-contracts/src/contracts/interfaces/ISignatureUtilsMixin.sol";
import {MockAVSRegistrar} from "lib/eigenlayer-contracts/src/test/mocks/MockAVSRegistrar.sol";
import {IAllocationManagerTypes} from "lib/eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {AllocationManagerStorage} from "lib/eigenlayer-contracts/src/contracts/core/AllocationManagerStorage.sol";
import {OperatorSet} from "lib/eigenlayer-contracts/src/contracts/libraries/OperatorSetLib.sol";

contract WithSlashingBase is ynEigenIntegrationBaseTest {
    TestAssetUtils internal testAssetUtils;
    ITokenStakingNode internal tokenStakingNode;
    address internal avs;
    IERC20 internal wstETH;
    IStrategy internal wstETHStrategy;

    event QueuedSharesSynced();

    constructor() {
        testAssetUtils = new TestAssetUtils();
    }

    function setUp() public override {
        super.setUp();

        // Create token staking node
        // TODO: Use TOKEN_STAKING_NODE_CREATOR_ROLE instead of STAKING_NODE_CREATOR
        vm.prank(actors.ops.STAKING_NODE_CREATOR);
        tokenStakingNode = tokenStakingNodesManager.createTokenStakingNode();

        wstETH = IERC20(chainAddresses.lsd.WSTETH_ADDRESS);

        // Deposit assets to ynEigen
        uint256 stakeAmount = 100 ether;
        testAssetUtils.depositAsset(ynEigenToken, address(wstETH), stakeAmount, address(this));

        // Stake assets into the token staking node
        uint256 nodeId = tokenStakingNode.nodeId();
        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(wstETH));
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = stakeAmount;
        vm.prank(actors.ops.STRATEGY_CONTROLLER);
        eigenStrategyManager.stakeAssetsToNode(nodeId, assets, amounts);

        // Register operator
        vm.prank(actors.ops.TOKEN_STAKING_NODE_OPERATOR);
        eigenLayer.delegationManager.registerAsOperator(address(0), 0, "ipfs://some-ipfs-hash");

        // Delegate to operator
        ISignatureUtilsMixinTypes.SignatureWithExpiry memory signature;
        bytes32 approverSalt;
        vm.prank(actors.admin.TOKEN_STAKING_NODES_DELEGATOR);
        tokenStakingNode.delegate(actors.ops.TOKEN_STAKING_NODE_OPERATOR, signature, approverSalt);

        // Create AVS
        avs = address(new MockAVSRegistrar());

        // Update metadata URI
        vm.prank(avs);
        eigenLayer.allocationManager.updateAVSMetadataURI(avs, "ipfs://some-metadata-uri");

        wstETHStrategy = eigenStrategyManager.strategies(wstETH);

        // Create operator set
        IAllocationManagerTypes.CreateSetParams[] memory createSetParams = new IAllocationManagerTypes.CreateSetParams[](1);
        createSetParams[0] = IAllocationManagerTypes.CreateSetParams({ 
            operatorSetId: 1, 
            strategies: new IStrategy[](1) 
        });
        createSetParams[0].strategies[0] = wstETHStrategy;
        vm.prank(avs);
        eigenLayer.allocationManager.createOperatorSets(avs, createSetParams);

        // Register for operator set
        IAllocationManagerTypes.RegisterParams memory registerParams = IAllocationManagerTypes.RegisterParams({
            avs: avs,
            operatorSetIds: new uint32[](1),
            data: new bytes(0)
        });
        registerParams.operatorSetIds[0] = 1;
        vm.prank(actors.ops.TOKEN_STAKING_NODE_OPERATOR);
        eigenLayer.allocationManager.registerForOperatorSets(actors.ops.TOKEN_STAKING_NODE_OPERATOR, registerParams);

        _waitForAllocationDelay();

        // Make all delegated shares slashable
        _allocate();
    }

    function _waitForAllocationDelay() internal {
        AllocationManagerStorage allocationManager = AllocationManagerStorage(address(eigenLayer.allocationManager));
        vm.roll(block.number + allocationManager.ALLOCATION_CONFIGURATION_DELAY() + 1);
    }

    function _waitForDeallocationDelay() internal {
        AllocationManagerStorage allocationManager = AllocationManagerStorage(address(eigenLayer.allocationManager));
        vm.roll(block.number + allocationManager.DEALLOCATION_DELAY() + 1);
    }

    function _waitForWithdrawalDelay() internal {
        vm.roll(block.number + eigenLayer.delegationManager.minWithdrawalDelayBlocks() + 1);
    }
    
    function _allocate() internal {
        _allocate(1 ether);
    }

    function _allocate(uint64 _newMagnitude) internal {
        IAllocationManagerTypes.AllocateParams[] memory allocateParams = new IAllocationManagerTypes.AllocateParams[](1);
        allocateParams[0] = IAllocationManagerTypes.AllocateParams({
            operatorSet: OperatorSet({
                avs: avs,
                id: 1
            }),
            strategies: new IStrategy[](1),
            newMagnitudes: new uint64[](1)
        });
        allocateParams[0].strategies[0] = wstETHStrategy;
        allocateParams[0].newMagnitudes[0] = _newMagnitude;
        vm.prank(actors.ops.TOKEN_STAKING_NODE_OPERATOR);
        eigenLayer.allocationManager.modifyAllocations(actors.ops.TOKEN_STAKING_NODE_OPERATOR, allocateParams);
    }

    function _slash() internal {
        _slash(1 ether);
    }

    function _slash(uint256 _wadsToSlash) internal {
        IAllocationManagerTypes.SlashingParams memory slashingParams = IAllocationManagerTypes.SlashingParams({
            operator: actors.ops.TOKEN_STAKING_NODE_OPERATOR,
            operatorSetId: 1,
            strategies: new IStrategy[](1),
            wadsToSlash: new uint256[](1),
            description: "test"
        });
        slashingParams.strategies[0] = wstETHStrategy;
        slashingParams.wadsToSlash[0] = _wadsToSlash;
        vm.prank(avs);
        eigenLayer.allocationManager.slashOperator(avs, slashingParams);
    }

    function _getWithdrawableShares() internal view returns (uint256, uint256) {
        IStrategy[] memory strategies = new IStrategy[](1);
        strategies[0] = wstETHStrategy;
        (uint256[] memory withdrawableShares, uint256[] memory depositShares) = eigenLayer.delegationManager.getWithdrawableShares(address(tokenStakingNode), strategies);
        return (withdrawableShares[0], depositShares[0]);
    }

    function _queueWithdrawal(uint256 depositShares) internal returns (bytes32) {
        // TODO: Use TOKEN_STAKING_NODES_WITHDRAWER instead of STAKING_NODES_WITHDRAWER
        vm.prank(actors.ops.STAKING_NODES_WITHDRAWER);
        return tokenStakingNode.queueWithdrawals(wstETHStrategy, depositShares)[0];
    }

    function _queuedShares() internal view returns (uint256) {
        return tokenStakingNode.queuedShares(wstETHStrategy);
    }
}