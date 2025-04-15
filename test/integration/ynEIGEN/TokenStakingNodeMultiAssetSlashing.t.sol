// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IERC20} from "lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {IDelegationManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {ISignatureUtilsMixinTypes} from "lib/eigenlayer-contracts/src/contracts/interfaces/ISignatureUtilsMixin.sol";
import {TestAssetUtils} from "test/utils/TestAssetUtils.sol";
import {ITokenStakingNode} from "src/interfaces/ITokenStakingNode.sol";
import {IwstETH} from "src/external/lido/IwstETH.sol";
import {EigenStrategyManager} from "src/ynEIGEN/EigenStrategyManager.sol";
import {IStrategy} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {TokenStakingNode} from "src/ynEIGEN/TokenStakingNode.sol";
import {ERC1967Proxy} from "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {WithSlashingBase} from "test/integration/ynEIGEN/WithSlashingBase.t.sol";
import {ynEigenIntegrationBaseTest} from "test/integration/ynEIGEN/ynEigenIntegrationBaseTest.sol";
import {TestAVSUtils} from "test/utils/TestAVSUtils.sol";


contract TokenStakingNodeWithMultiAssetSlashingTest is ynEigenIntegrationBaseTest {
    TestAssetUtils internal testAssetUtils;
    ITokenStakingNode internal tokenStakingNode;
    address internal avs;
    IERC20 internal wstETH;
    IStrategy internal wstETHStrategy;
    TestAVSUtils internal testAVSUtils;
    address[10] public depositors;

    event QueuedSharesSynced();

    constructor() {
        testAssetUtils = new TestAssetUtils();
        testAVSUtils = new TestAVSUtils();
        for (uint256 i = 0; i < 10; i++) {
            depositors[i] = address(uint160(uint256(keccak256(abi.encodePacked("depositor", i)))));
        }
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
        wstETHStrategy = eigenStrategyManager.strategies(wstETH);

        // Setup AVS, register operator, and allocate shares using TestAVSUtils
        IStrategy[] memory strategies = new IStrategy[](1);
        strategies[0] = wstETHStrategy;
        
        uint64[] memory magnitudes = new uint64[](1);
        magnitudes[0] = 1 ether;
        
        TestAVSUtils.AVSSetupParams memory params = TestAVSUtils.AVSSetupParams({
            operator: actors.ops.TOKEN_STAKING_NODE_OPERATOR,
            delegator: actors.admin.TOKEN_STAKING_NODES_DELEGATOR,
            tokenStakingNode: tokenStakingNode,
            strategies: strategies,
            operatorSetId: 1,
            metadataURI: "ipfs://some-metadata-uri",
            magnitudes: magnitudes
        });
        
        avs = testAVSUtils.setupAVSAndRegisterOperator(
            vm,
            eigenLayer.delegationManager,
            eigenLayer.allocationManager,
            params
        );
    }

    function testStakeMultipleAssetsAndSlashAll(
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


        vm.startPrank(actors.ops.STRATEGY_CONTROLLER);
        eigenStrategyManager.stakeAssetsToNode(tokenStakingNode.nodeId(), assetsToDeposit, amounts);
        vm.stopPrank();

        uint256 totalAssetsBefore = ynEigenToken.totalAssets();
        
        // Get balances before slashing
        uint256[] memory stakesBefore = new uint256[](assetsToDeposit.length);
        for (uint256 i = 0; i < assetsToDeposit.length; i++) {
            IStrategy strategy = eigenStrategyManager.strategies(assetsToDeposit[i]);
            (stakesBefore[i],) = eigenStrategyManager.strategiesBalance(strategy);
        }

        (uint256 wstETHStakeBefore,) = eigenStrategyManager.strategiesBalance(wstETHStrategy);
        
        // Use testAVSUtils to perform slashing
        testAVSUtils.slashOperator(
            vm,
            eigenLayer.allocationManager,
            avs,
            actors.ops.TOKEN_STAKING_NODE_OPERATOR,
            1,
            wstETHStrategy,
            0.5 ether
        );
                
        // Update balances after slashing
        ITokenStakingNode[] memory nodes = new ITokenStakingNode[](1);
        nodes[0] = tokenStakingNode;
        eigenStrategyManager.synchronizeNodesAndUpdateBalances(nodes);
        
        // Assert balances were reduced by 50%
        for (uint256 i = 0; i < assetsToDeposit.length; i++) {
            IStrategy strategy = eigenStrategyManager.strategies(assetsToDeposit[i]);
            (uint256 stakeAfter,) = eigenStrategyManager.strategiesBalance(strategy);

            if (wstETHStrategy == strategy) {
                assertApproxEqRel(stakeAfter, stakesBefore[i] * 0.5 ether / 1e18, 1, " should have been reduced by 50%");
            } else {
                assertApproxEqRel(stakeAfter, stakesBefore[i], 1, " should have been reduced by 50%");
            }
        }

        // Assert that total assets after slashing are reduced by the slashing factor (50%)
        uint256 totalAssetsAfter = ynEigenToken.totalAssets();

        uint256 expectedTotalAssetsAfter = 
                totalAssetsBefore -
                wstETHStakeBefore * 0.5 ether / 1e18;

        assertApproxEqRel(
                totalAssetsAfter,
                expectedTotalAssetsAfter,
                1,
                "Total assets should have been reduced by 50% after slashing"
        );
    }
}