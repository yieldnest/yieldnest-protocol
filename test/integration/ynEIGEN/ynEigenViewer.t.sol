// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity 0.8.24;

import {IERC20, IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {ITokenStakingNodesManager,ITokenStakingNode} from "../../../src/interfaces/ITokenStakingNodesManager.sol";
import {TestAssetUtils} from "test/utils/TestAssetUtils.sol";
import {ynEigenViewer} from "../../../src/ynEIGEN/ynEigenViewer.sol";
import {console} from "forge-std/console.sol";
import "./ynEigenIntegrationBaseTest.sol";



interface IAssetRegistryView {
    function assets() external view returns (IERC20Metadata[] memory);
}

contract ynEigenViewerTest is ynEigenIntegrationBaseTest {

    TestAssetUtils testAssetUtils;
    address[10] public depositors;

    constructor() {
        testAssetUtils = new TestAssetUtils();
        for (uint i = 0; i < 10; i++) {
            depositors[i] = address(uint160(uint256(keccak256(abi.encodePacked("depositor", i)))));
        }
    }

    ynEigenViewer private _ynEigenViewer;

    function setUp() public override {
        super.setUp();
        _ynEigenViewer = new ynEigenViewer(
            address(assetRegistry),
            address(ynEigenToken),
            address(tokenStakingNodesManager),
            address(rateProvider)
        );
    }

    function testGetAllStakingNodes() public {
        ITokenStakingNode[] memory _nodes = _ynEigenViewer.getAllStakingNodes();
        assertEq(_nodes.length, 0, "There should be no nodes");
    }

    function testGetYnEigenAssets() public {
        IERC20[] memory _assets = assetRegistry.getAssets();
        assertTrue(_assets.length > 0, "testGetYnEigenAssets: E0");

        ynEigenViewer.AssetInfo[] memory _assetsInfo = _ynEigenViewer.getYnEigenAssets();
        for (uint256 i = 0; i < _assets.length; ++i) {
            assertEq(_assetsInfo[i].asset, address(_assets[i]), "testGetYnEigenAssets: E1");
            assertEq(_assetsInfo[i].name, IERC20Metadata(address(_assets[i])).name(), "testGetYnEigenAssets: E2");
            assertEq(_assetsInfo[i].symbol, IERC20Metadata(address(_assets[i])).symbol(), "testGetYnEigenAssets: E3");
            assertEq(_assetsInfo[i].ratioOfTotalAssets, 0, "testGetYnEigenAssets: E4");
            assertEq(_assetsInfo[i].totalBalanceInUnitOfAccount, 0, "testGetYnEigenAssets: E5");
            assertEq(_assetsInfo[i].totalBalanceInAsset, 0, "testGetYnEigenAssets: E5");
        }
    }

    function testGetYnEigenAssetsAfterDeposits() public {
        // Define deposit amounts
        uint256 sfrxEthAmount = 1 ether;
        uint256 wstEthAmount = 0.5 ether;
        uint256 rEthAmount = 0.75 ether;

        // Create a user for deposits
        address user = makeAddr("userXYZ");

        // Make deposits to the user
        deal(address(chainAddresses.lsd.SFRXETH_ADDRESS), user, sfrxEthAmount);
        deal(address(chainAddresses.lsd.WSTETH_ADDRESS), user, wstEthAmount);
        deal(address(chainAddresses.lsd.RETH_ADDRESS), user, rEthAmount);

        // Switch to user context
        vm.startPrank(user);

        // Approve and deposit tokens
        IERC20(chainAddresses.lsd.SFRXETH_ADDRESS).approve(address(ynEigenToken), sfrxEthAmount);
        IERC20(chainAddresses.lsd.WSTETH_ADDRESS).approve(address(ynEigenToken), wstEthAmount);
        IERC20(chainAddresses.lsd.RETH_ADDRESS).approve(address(ynEigenToken), rEthAmount);

        ynEigenToken.deposit(IERC20(chainAddresses.lsd.SFRXETH_ADDRESS), sfrxEthAmount, user);
        ynEigenToken.deposit(IERC20(chainAddresses.lsd.WSTETH_ADDRESS), wstEthAmount, user);
        ynEigenToken.deposit(IERC20(chainAddresses.lsd.RETH_ADDRESS), rEthAmount, user);
        
        // End user context
        vm.stopPrank();


        // Get asset info after deposits
        ynEigenViewer.AssetInfo[] memory assetsInfo = _ynEigenViewer.getYnEigenAssets();

        {
            vm.startPrank(actors.ops.STAKING_NODE_CREATOR);
            tokenStakingNodesManager.createTokenStakingNode();
            tokenStakingNodesManager.createTokenStakingNode();
            vm.stopPrank();

            EigenStrategyManager.NodeAllocation[] memory allocations = new EigenStrategyManager.NodeAllocation[](2);
            IERC20[] memory assets1 = new IERC20[](1);
            uint256[] memory amounts1 = new uint256[](1);
            assets1[0] = IERC20(chainAddresses.lsd.WSTETH_ADDRESS);
            amounts1[0] = wstEthAmount / 4;

            testAssetUtils.depositAsset(ynEigenToken, address(assets1[0]), amounts1[0], depositors[0]);

            IERC20[] memory assets2 = new IERC20[](1);
            uint256[] memory amounts2 = new uint256[](1);
            assets2[0] = IERC20(chainAddresses.lsd.RETH_ADDRESS);
            amounts2[0] = rEthAmount / 4;

            testAssetUtils.depositAsset(ynEigenToken, address(assets2[0]), amounts2[0], depositors[1]);

            allocations[0] = EigenStrategyManager.NodeAllocation(0, assets1, amounts1);
            allocations[1] = EigenStrategyManager.NodeAllocation(1, assets2, amounts2);

            uint256 totalAssetsBefore = ynEigenToken.totalAssets();

            vm.startPrank(actors.ops.STRATEGY_CONTROLLER);
            eigenStrategyManager.stakeAssetsToNodes(allocations);
            vm.stopPrank();

            assertApproxEqRel(ynEigenToken.totalAssets(), totalAssetsBefore, 1e16, "Total assets should not change significantly after staking");
        }

        // Calculate total assets
        uint256 totalAssets = ynEigenToken.totalAssets();

        // Calculate the value of each deposit in ETH and its expected ratio
        uint256 sfrxEthValueInEth = assetRegistry.convertToUnitOfAccount(IERC20(chainAddresses.lsd.SFRXETH_ADDRESS), sfrxEthAmount);
        uint256 wstEthValueInEth = assetRegistry.convertToUnitOfAccount(IERC20(chainAddresses.lsd.WSTETH_ADDRESS), wstEthAmount);
        uint256 rEthValueInEth = assetRegistry.convertToUnitOfAccount(IERC20(chainAddresses.lsd.RETH_ADDRESS), rEthAmount);
        
        uint256 totalValueInEth = sfrxEthValueInEth + wstEthValueInEth + rEthValueInEth;
        
        uint256 expectedSfrxEthRatio = (sfrxEthValueInEth * 1e6) / totalValueInEth;
        uint256 expectedWstEthRatio = (wstEthValueInEth * 1e6) / totalValueInEth;
        uint256 expectedREthRatio = (rEthValueInEth * 1e6) / totalValueInEth;

        // Verify asset info
        for (uint256 i = 0; i < assetsInfo.length; i++) {
            if (assetsInfo[i].asset == address(chainAddresses.lsd.SFRXETH_ADDRESS)) {
                assertEq(assetsInfo[i].name, "Staked Frax Ether", "Incorrect sfrxETH name");
                assertEq(assetsInfo[i].symbol, "sfrxETH", "Incorrect sfrxETH symbol");
                assertEq(assetsInfo[i].totalBalanceInUnitOfAccount, sfrxEthValueInEth, "Incorrect sfrxETH balance in unit of account");
                assertEq(assetsInfo[i].totalBalanceInAsset, sfrxEthAmount, "Incorrect sfrxETH balance in asset");
                assertApproxEqRel(assetsInfo[i].ratioOfTotalAssets, expectedSfrxEthRatio, 1e16, "Incorrect sfrxETH ratio");
                assertEq(assetsInfo[i].rate, rateProvider.rate(address(chainAddresses.lsd.SFRXETH_ADDRESS)), "sfrxETH rate mismatch with rateProvider");
            } else if (assetsInfo[i].asset == address(chainAddresses.lsd.WSTETH_ADDRESS)) {
                assertEq(assetsInfo[i].name, "Wrapped liquid staked Ether 2.0", "Incorrect wstETH name");
                assertEq(assetsInfo[i].symbol, "wstETH", "Incorrect wstETH symbol");
                assertEq(assetsInfo[i].totalBalanceInUnitOfAccount, wstEthValueInEth, "Incorrect wstETH balance in unit of account");
                assertEq(assetsInfo[i].totalBalanceInAsset, wstEthAmount, "Incorrect wstETH balance in asset");
                assertApproxEqRel(assetsInfo[i].ratioOfTotalAssets, expectedWstEthRatio, 1e16, "Incorrect wstETH ratio");
                assertEq(assetsInfo[i].rate, rateProvider.rate(address(chainAddresses.lsd.WSTETH_ADDRESS)), "wstETH rate mismatch with rateProvider");
            } else if (assetsInfo[i].asset == address(chainAddresses.lsd.RETH_ADDRESS)) {
                assertEq(assetsInfo[i].name, "Rocket Pool ETH", "Incorrect rETH name");
                assertEq(assetsInfo[i].symbol, "rETH", "Incorrect rETH symbol");
                assertEq(assetsInfo[i].totalBalanceInUnitOfAccount, rEthValueInEth, "Incorrect rETH balance in unit of account");
                assertEq(assetsInfo[i].totalBalanceInAsset, rEthAmount, "Incorrect rETH balance in asset");
                assertApproxEqRel(assetsInfo[i].ratioOfTotalAssets, expectedREthRatio, 1e16, "Incorrect rETH ratio");
                assertEq(assetsInfo[i].rate, rateProvider.rate(address(chainAddresses.lsd.RETH_ADDRESS)), "rETH rate mismatch with rateProvider");
            } else {
                assertEq(assetsInfo[i].totalBalanceInUnitOfAccount, 0, "Non-zero balance for undeposited asset in unit of account");
                assertEq(assetsInfo[i].totalBalanceInAsset, 0, "Non-zero balance for undeposited asset in asset");
                assertEq(assetsInfo[i].ratioOfTotalAssets, 0, "Non-zero ratio for undeposited asset");
                assertEq(assetsInfo[i].rate, rateProvider.rate(assetsInfo[i].asset), "Rate mismatch with rateProvider for undeposited asset");
            }
        }
    }

    function testPreviewDepositStETH() public {
        // Set up test amount
        uint256 testAmount = 1 ether;

        // Log STETH_ADDRESS
        console.log("STETH_ADDRESS:", address(chainAddresses.lsd.STETH_ADDRESS));

        // Call previewDeposit
        uint256 expectedShares = _ynEigenViewer.previewDeposit(IERC20(chainAddresses.lsd.STETH_ADDRESS), testAmount);

        // Verify the result
        assertTrue(expectedShares > 0, "Expected shares should be greater than 0");
    }

    function testGetRate() public {
        // Get rate
        uint256 rate = _ynEigenViewer.getRate();

        // Verify that the rate is not zero
        assertEq(rate, 1e18, "Rate is 1 with no deposits");
    }
}