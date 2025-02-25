// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import "./ynEigenIntegrationBaseTest.sol";
import {ProxyAdmin} from "lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {UpgradeableBeacon} from "lib/openzeppelin-contracts/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {ITransparentUpgradeableProxy} from "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ITokenStakingNode} from "src/interfaces/ITokenStakingNode.sol";
import {ynBase} from "src/ynBase.sol";
import {IwstETH} from "src/external/lido/IwstETH.sol";
import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {EigenStrategyManager} from "src/ynEIGEN/EigenStrategyManager.sol";
import {MockAVSRegistrar} from "lib/eigenlayer-contracts/src/test/mocks/MockAVSRegistrar.sol";
import {IAllocationManagerTypes} from "lib/eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {ISignatureUtils} from "lib/eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";
import {AllocationManagerStorage} from "lib/eigenlayer-contracts/src/contracts/core/AllocationManagerStorage.sol";
import {OperatorSet} from "lib/eigenlayer-contracts/src/contracts/libraries/OperatorSetLib.sol";


contract EigenStrategyManagerTest is ynEigenIntegrationBaseTest {

    TestAssetUtils testAssetUtils;
    address[10] public depositors;
    address private avs;
    IStrategy private wstETHStrategy;
    ITokenStakingNode private tokenStakingNode;



    constructor() {
        testAssetUtils = new TestAssetUtils();
        for (uint i = 0; i < 10; i++) {
            depositors[i] = address(uint160(uint256(keccak256(abi.encodePacked("depositor", i)))));
        }
    }
    
    
    function _waitForAllocationDelay() private {
        AllocationManagerStorage allocationManager = AllocationManagerStorage(address(eigenLayer.allocationManager));
        vm.roll(block.number + allocationManager.ALLOCATION_CONFIGURATION_DELAY() + 1);
    }
    
    function _slash(uint256 _wadsToSlash) private {
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
    
    
    function _allocate() private {
        _allocate(1 ether);
    }

    
    function _allocate(uint64 _newMagnitude) private {
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
    
    
    function setUp() public override {
        super.setUp();

        // Create token staking node
        // TODO: Use TOKEN_STAKING_NODE_CREATOR_ROLE instead of STAKING_NODE_CREATOR
        vm.prank(actors.ops.STAKING_NODE_CREATOR);
        tokenStakingNode = tokenStakingNodesManager.createTokenStakingNode();

        // Deposit assets to ynEigen
        uint256 stakeAmount = 100 ether;
        IERC20 wstETH = IERC20(chainAddresses.lsd.WSTETH_ADDRESS);
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
        ISignatureUtils.SignatureWithExpiry memory signature;
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

    function testStakeAssetsToNodeSuccessFuzz(
        uint256 wstethAmount,
        uint256 woethAmount,
        uint256 rethAmount,
        uint256 sfrxethAmount
    ) public {

        // cannot call stakeAssetsToNode with any amount == 0. all must be non-zero.
        vm.assume(
            wstethAmount < 100 ether && wstethAmount >= 2 wei &&
            woethAmount < 100 ether && woethAmount >= 2 wei &&
            rethAmount < 100 ether && rethAmount >= 2 wei &&
            sfrxethAmount < 100 ether && sfrxethAmount >= 2 wei
        );

        // Setup: Create a token staking node and prepare assetsToDeposit
        vm.prank(actors.ops.STAKING_NODE_CREATOR);
        tokenStakingNodesManager.createTokenStakingNode();
        ITokenStakingNode tokenStakingNode = tokenStakingNodesManager.nodes(0);

        // uint256 wstethAmount = 18446744073709551616; // 1.844e19
        // uint256 woethAmount = 4918;
        // uint256 rethAmount = 5018;
        // uint256 sfrxethAmount = 17119; // 1.711e4

        uint256 assetCount = _isHolesky() ? 3 : 4;

        // Call with arrays and from controller
        IERC20[] memory assetsToDeposit = new IERC20[](assetCount);
        assetsToDeposit[0] = IERC20(chainAddresses.lsd.WSTETH_ADDRESS);
        assetsToDeposit[1] = IERC20(chainAddresses.lsd.SFRXETH_ADDRESS);
        assetsToDeposit[2] = IERC20(chainAddresses.lsd.RETH_ADDRESS);
        if (!_isHolesky()) assetsToDeposit[3] = IERC20(chainAddresses.lsd.WOETH_ADDRESS);

        uint256[] memory amounts = new uint256[](assetCount);
        amounts[0] = wstethAmount;
        amounts[1] = sfrxethAmount;
        amounts[2] = rethAmount;
        if (!_isHolesky()) amounts[3] = woethAmount;

        for (uint256 i = 0; i < assetCount; i++) {
            address prankedUser = depositors[i];
            if (amounts[i] == 0) {
                // no deposits
                continue;
            }
            testAssetUtils.depositAsset(ynEigenToken, address(assetsToDeposit[i]), amounts[i], prankedUser);
        }

        uint256[] memory initialBalances = new uint256[](assetsToDeposit.length);
        for (uint256 i = 0; i < assetsToDeposit.length; i++) {
            initialBalances[i] = assetsToDeposit[i].balanceOf(address(ynEigenToken));
        }

        uint256 totalAssetsBefore = ynEigenToken.totalAssets();

        vm.startPrank(actors.ops.STRATEGY_CONTROLLER);
        eigenStrategyManager.stakeAssetsToNode(tokenStakingNode.nodeId(), assetsToDeposit, amounts);
        vm.stopPrank();

        for (uint256 i = 0; i < assetsToDeposit.length; i++) {
            uint256 initialBalance = initialBalances[i];
            uint256 finalBalance = assetsToDeposit[i].balanceOf(address(ynEigenToken));
            assertEq(initialBalance - finalBalance, amounts[i], "Balance of ynEigen did not decrease by the staked amount for asset");
            assertEq(compareWithThreshold(eigenStrategyManager.getStakedAssetBalance(assetsToDeposit[i]), initialBalance, 3), true, "Staked asset balance does not match initial balance within threshold");
            uint256 userUnderlyingView = eigenStrategyManager.strategies(assetsToDeposit[i]).userUnderlyingView(address(tokenStakingNode));

            uint256 expectedUserUnderlyingView = initialBalance;
            if (address(assetsToDeposit[i]) == chainAddresses.lsd.WSTETH_ADDRESS || address(assetsToDeposit[i]) == chainAddresses.lsd.WOETH_ADDRESS) {

                // TODO: come back to this to see why the reverse operation of converting the
                // userUnderlyingView to the wrapped asset using the Rate Provider does not give the same result

                //expectedUserUnderlyingView = expectedUserUnderlyingView * wrappedAssetRate / 1e18;
                //userUnderlyingView = userUnderlyingView * 1e18 / wrappedAssetRate;
                if (address(assetsToDeposit[i]) == chainAddresses.lsd.WSTETH_ADDRESS) {
                    IwstETH wstETH = IwstETH(chainAddresses.lsd.WSTETH_ADDRESS);
                    userUnderlyingView = wstETH.getWstETHByStETH(userUnderlyingView);
                } else if (address(assetsToDeposit[i]) == chainAddresses.lsd.WOETH_ADDRESS) {
                    IERC4626 woETH = IERC4626(chainAddresses.lsd.WOETH_ADDRESS);
                    userUnderlyingView = woETH.previewDeposit(userUnderlyingView);
                }
            }

            uint256 comparisonTreshold = 3;
            assertEq(compareWithThreshold(expectedUserUnderlyingView, userUnderlyingView, comparisonTreshold), true, "Initial balance does not match user underlying view within threshold");
        }

        uint256 totalAssetsAfter = ynEigenToken.totalAssets();
        assertEq(compareWithThreshold(totalAssetsBefore, totalAssetsAfter, 100), true, "Total assets before and after staking do not match within a threshold of 3");
    }


    function testStakeAssetsToMultipleNodes(
        uint256 wstethAmount,
        uint256 woethAmount
    ) public skipOnHolesky {

        vm.assume(
            wstethAmount < 1000 ether && wstethAmount >= 2 wei &&
            woethAmount < 1000 ether && woethAmount >= 2 wei
        );

        vm.startPrank(actors.ops.STAKING_NODE_CREATOR);
        tokenStakingNodesManager.createTokenStakingNode();
        tokenStakingNodesManager.createTokenStakingNode();
        vm.stopPrank();

        EigenStrategyManager.NodeAllocation[] memory allocations = new EigenStrategyManager.NodeAllocation[](2);
        IERC20[] memory assets1 = new IERC20[](1);
        uint256[] memory amounts1 = new uint256[](1);
        assets1[0] = IERC20(chainAddresses.lsd.WSTETH_ADDRESS);
        amounts1[0] = wstethAmount;

        testAssetUtils.depositAsset(ynEigenToken, address(assets1[0]), amounts1[0], depositors[0]);

        IERC20[] memory assets2 = new IERC20[](1);
        uint256[] memory amounts2 = new uint256[](1);
        assets2[0] = IERC20(chainAddresses.lsd.WOETH_ADDRESS);
        amounts2[0] = woethAmount;

        testAssetUtils.depositAsset(ynEigenToken, address(assets2[0]), amounts2[0], depositors[1]);

        allocations[0] = EigenStrategyManager.NodeAllocation(0, assets1, amounts1);
        allocations[1] = EigenStrategyManager.NodeAllocation(1, assets2, amounts2);

        uint256 totalAssetsBefore = ynEigenToken.totalAssets();

        vm.startPrank(actors.ops.STRATEGY_CONTROLLER);
        eigenStrategyManager.stakeAssetsToNodes(allocations);
        vm.stopPrank();

        {
            uint256 totalAssetsAfter = ynEigenToken.totalAssets();
            assertEq(compareWithThreshold(totalAssetsBefore, totalAssetsAfter, 100), true, "Total assets before and after staking to multiple nodes do not match within a threshold of 100");
        }

        {
            uint256 userUnderlyingViewNode0 = eigenStrategyManager.strategies(assets1[0]).userUnderlyingView(address(tokenStakingNodesManager.nodes(0)));
            IwstETH wstETH = IwstETH(chainAddresses.lsd.WSTETH_ADDRESS);
            uint256 wstETHAmountNode0 = wstETH.getWstETHByStETH(userUnderlyingViewNode0);
            assertEq(
                compareWithThreshold(wstETHAmountNode0, wstethAmount, 3), true,
                string.concat("Unwrapped stETH amount does not match expected for node 0. Expected: ", vm.toString(wstethAmount), ", Got: ", vm.toString(wstETHAmountNode0))
            );
        }

        {
            uint256 userUnderlyingViewNode1 = eigenStrategyManager.strategies(assets2[0]).userUnderlyingView(address(tokenStakingNodesManager.nodes(1)));
            IERC4626 woETH = IERC4626(chainAddresses.lsd.WOETH_ADDRESS);
            uint256 woETHAmountNode1 =  woETH.previewDeposit(userUnderlyingViewNode1);
            assertEq(
                compareWithThreshold(woETHAmountNode1, woethAmount, 3), true,
                string.concat("Unwrapped oETH amount does not match expected for node 1. Expected: ", vm.toString(woethAmount), ", Got: ", vm.toString(woETHAmountNode1))
            );
        }

    }
    
    
    function testStakeNodesAndSlash() public {
        (uint256 stakeBefore,) = eigenStrategyManager.strategiesBalance(wstETHStrategy);

        {
            // slash 50%
            _slash(0.5 ether);
            
            // update balances after slashing
            ITokenStakingNode[] memory nodes = new ITokenStakingNode[](1);
            nodes[0] = tokenStakingNode;
            eigenStrategyManager.synchronizeNodesAndUpdateBalances(nodes);
            
            (uint256 stakeAfter,) = eigenStrategyManager.strategiesBalance(wstETHStrategy);
            
            assertApproxEqRel(stakeAfter, stakeBefore / 2, 1, "Assets should have been staked by half");
        }
    }

    function testExpectedStrategiesForAssets() public {
        address wstethAsset = chainAddresses.lsd.WSTETH_ADDRESS;
        address woethAsset = chainAddresses.lsd.WOETH_ADDRESS;
        address rethAsset = chainAddresses.lsd.RETH_ADDRESS;
        address sfrxethAsset = chainAddresses.lsd.SFRXETH_ADDRESS;
        address expectedStrategyForWSTETH = chainAddresses.lsdStrategies.STETH_STRATEGY_ADDRESS;
        address expectedStrategyForWOETH = chainAddresses.lsdStrategies.OETH_STRATEGY_ADDRESS;
        address expectedStrategyForRETH = chainAddresses.lsdStrategies.RETH_STRATEGY_ADDRESS;
        address expectedStrategyForSFRXETH = chainAddresses.lsdStrategies.SFRXETH_STRATEGY_ADDRESS;

        assertEq(address(eigenStrategyManager.strategies(IERC20(wstethAsset))), expectedStrategyForWSTETH, "Incorrect strategy for WSTETH");
        if (!_isHolesky()) {
            assertEq(address(eigenStrategyManager.strategies(IERC20(woethAsset))), expectedStrategyForWOETH, "Incorrect strategy for WOETH");
        }
        assertEq(address(eigenStrategyManager.strategies(IERC20(rethAsset))), expectedStrategyForRETH, "Incorrect strategy for RETH");
        assertEq(address(eigenStrategyManager.strategies(IERC20(sfrxethAsset))), expectedStrategyForSFRXETH, "Incorrect strategy for SFRXETH");
    }

    function testAddStrategySuccess() public {
        IERC20 newAsset = IERC20(chainAddresses.lsd.CBETH_ADDRESS); // Using CBETH as the new asset
        IStrategy newStrategy = IStrategy(chainAddresses.lsdStrategies.CBETH_STRATEGY_ADDRESS); // Using CBETH strategy

        // Initially, there should be no strategy set for newAsset
        assertEq(address(eigenStrategyManager.strategies(newAsset)), address(0), "Strategy already set for new asset");

        // Add strategy for newAsset
        vm.prank(actors.admin.EIGEN_STRATEGY_ADMIN);
        eigenStrategyManager.setStrategy(newAsset, newStrategy);

        // Verify that the strategy has been set
        assertEq(address(eigenStrategyManager.strategies(newAsset)), address(newStrategy), "Strategy not set correctly");
    }

    function testAddStrategyTwice() public {
        IERC20 existingAsset = IERC20(chainAddresses.lsd.CBETH_ADDRESS);
        IStrategy existingStrategy = IStrategy(chainAddresses.lsdStrategies.CBETH_STRATEGY_ADDRESS);

        // Setup: Add a strategy initially
        vm.prank(actors.admin.EIGEN_STRATEGY_ADMIN);
        eigenStrategyManager.setStrategy(existingAsset, existingStrategy);


        vm.prank(actors.admin.EIGEN_STRATEGY_ADMIN);
        eigenStrategyManager.setStrategy(existingAsset, existingStrategy);
    }

    function testAddStrategyWithMismatchedUnderlyingToken() public {
        IERC20 asset = IERC20(chainAddresses.lsd.CBETH_ADDRESS); // Using CBETH as the asset
        IStrategy mismatchedStrategy = IStrategy(chainAddresses.lsdStrategies.METH_STRATEGY_ADDRESS); // Incorrect strategy for CBETH

        // Setup: Ensure the underlying token of the mismatched strategy is not CBETH
        assertNotEq(address(mismatchedStrategy.underlyingToken()), address(asset), "Underlying token should not match asset");

        // Attempt to add a strategy with a mismatched underlying token
        vm.startPrank(actors.admin.EIGEN_STRATEGY_ADMIN);
        vm.expectRevert(
            abi.encodeWithSelector(EigenStrategyManager.AssetDoesNotMatchStrategyUnderlyingToken.selector, address(asset), address(mismatchedStrategy.underlyingToken())));
        eigenStrategyManager.setStrategy(asset, mismatchedStrategy);
        vm.stopPrank();
    }

    function testAddStrategyFailureZeroAsset() public {
        IStrategy newStrategy = IStrategy(address(0x456)); // Example new strategy address

        vm.prank(actors.admin.EIGEN_STRATEGY_ADMIN);
        // Test with zero address for asset
        vm.expectRevert(abi.encodeWithSelector(EigenStrategyManager.ZeroAddress.selector));
        eigenStrategyManager.setStrategy(IERC20(address(0)), newStrategy);
    }

    function testAddStrategyFailureZeroStrategy() public {
        IERC20 newAsset = IERC20(address(0x123)); // Example new asset address

        vm.prank(actors.admin.EIGEN_STRATEGY_ADMIN);
        vm.expectRevert(abi.encodeWithSelector(EigenStrategyManager.ZeroAddress.selector));
        eigenStrategyManager.setStrategy(newAsset, IStrategy(address(0)));
    }
}
