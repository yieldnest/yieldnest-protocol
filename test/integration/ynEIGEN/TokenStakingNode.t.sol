// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {ynEigenIntegrationBaseTest} from "test/integration/ynEIGEN/ynEigenIntegrationBaseTest.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {IStrategyManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IynEigen} from "src/interfaces/IynEigen.sol";
import {IPausable} from "lib/eigenlayer-contracts/src/contracts/interfaces/IPausable.sol";
import {IDelegationManager, IDelegationManagerTypes} from "lib/eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {ISignatureUtils} from "lib/eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";
import {AllocationManagerStorage} from "lib/eigenlayer-contracts/src/contracts/core/AllocationManagerStorage.sol";
import {IAllocationManagerTypes} from "lib/eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {TestAssetUtils} from "test/utils/TestAssetUtils.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";
import {BytesLib} from "lib/eigenlayer-contracts/src/contracts/libraries/BytesLib.sol";
import {ITokenStakingNode} from "src/interfaces/ITokenStakingNode.sol";
import {IwstETH} from "src/external/lido/IwstETH.sol";
import {EigenStrategyManager} from "src/ynEIGEN/EigenStrategyManager.sol";
import {IAssetRegistry} from "src/interfaces/IAssetRegistry.sol";
import {IStrategy} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IRewardsCoordinator} from "lib/eigenlayer-contracts/src/contracts/interfaces/IRewardsCoordinator.sol";
import {TokenStakingNode} from "src/ynEIGEN/TokenStakingNode.sol";
import {ContractAddresses} from "script/ContractAddresses.sol";
import {MockAVSRegistrar} from "lib/eigenlayer-contracts/src/test/mocks/MockAVSRegistrar.sol";
import {OperatorSet} from "lib/eigenlayer-contracts/src/contracts/libraries/OperatorSetLib.sol";
import {ERC1967Proxy} from "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

interface ITestState {

    function ynEigenToken() external view returns (IynEigen);
    function tokenStakingNodesManager() external view returns (ITokenStakingNodesManager);
    function assetRegistry() external view returns (IAssetRegistry);
    function eigenStrategyManager() external view returns (EigenStrategyManager);
    function eigenLayerStrategyManager() external view returns (IStrategyManager);
    function eigenLayerDelegationManager() external view returns (IDelegationManager);

}

interface ITokenStakingNodesManager {

    function nodes(
        uint256 nodeId
    ) external view returns (ITokenStakingNode);
    function createTokenStakingNode() external returns (ITokenStakingNode);

}

struct StateSnapshot {
    uint256 totalAssets;
    uint256 totalSupply;
    mapping(IStrategy => uint256) strategyQueuedShares;
    mapping(address => uint256) withdrawnByToken;
    mapping(address => uint256) stakedAssetBalanceForNode;
    mapping(address => uint256) strategySharesForNode;
}

contract NodeStateSnapshot {

    StateSnapshot public snapshot;
    ContractAddresses public contractAddresses;
    ContractAddresses.ChainAddresses public chainAddresses;
    
    bool public isHolesky;
    constructor() {
        contractAddresses = new ContractAddresses();
        chainAddresses = contractAddresses.getChainAddresses(block.chainid);
        (, uint256 holeskyId) = contractAddresses.chainIds();
        isHolesky = block.chainid == holeskyId;
    }

    function takeSnapshot(address testAddress, uint256 nodeId) external {
        ITestState state = ITestState(testAddress);
        ITokenStakingNode node = state.tokenStakingNodesManager().nodes(nodeId);

        snapshot.totalAssets = state.ynEigenToken().totalAssets();
        snapshot.totalSupply = state.ynEigenToken().totalSupply();

        IERC20[] memory assets = state.assetRegistry().getAssets();

        for (uint256 i = 0; i < assets.length; i++) {
            if (isHolesky && (
                address(assets[i]) == chainAddresses.lsd.OETH_ADDRESS ||
                address(assets[i]) == chainAddresses.lsd.WOETH_ADDRESS ||
                address(assets[i]) == chainAddresses.lsd.SWELL_ADDRESS
            ) ) {
                continue;
            }
            IERC20 asset = assets[i];
            IStrategy strategy = state.eigenStrategyManager().strategies(asset);

            // Store queued shares for each strategy
            snapshot.strategyQueuedShares[strategy] = node.queuedShares(strategy);

            // Store withdrawn amount for each token
            snapshot.withdrawnByToken[address(asset)] = node.withdrawn(asset);

            // Store staked asset balance for each token
            snapshot.stakedAssetBalanceForNode[address(asset)] =
                state.eigenStrategyManager().getStakedAssetBalanceForNode(asset, nodeId);

            // Store strategy shares for each token
            snapshot.strategySharesForNode[address(asset)] =
                state.eigenStrategyManager().strategyManager().stakerDepositShares(address(node), strategy); // FIXME double check
        }
    }

    function totalAssets() external view returns (uint256) {
        return snapshot.totalAssets;
    }

    function totalSupply() external view returns (uint256) {
        return snapshot.totalSupply;
    }

    function getStrategyQueuedShares(
        IStrategy strategy
    ) external view returns (uint256) {
        return snapshot.strategyQueuedShares[strategy];
    }

    function getWithdrawnByToken(
        address token
    ) external view returns (uint256) {
        return snapshot.withdrawnByToken[token];
    }

    function getStakedAssetBalanceForNode(
        address token
    ) external view returns (uint256) {
        return snapshot.stakedAssetBalanceForNode[token];
    }

    function getStrategySharesForNode(
        address token
    ) external view returns (uint256) {
        return snapshot.strategySharesForNode[token];
    }

}

contract TokenStakingNodeTest is ynEigenIntegrationBaseTest {

    ITokenStakingNode tokenStakingNode;
    TestAssetUtils testAssetUtils;

    constructor() {
        testAssetUtils = new TestAssetUtils();
    }

    function setUp() public override {
        super.setUp();
        vm.prank(actors.ops.STAKING_NODE_CREATOR);
        tokenStakingNode = tokenStakingNodesManager.createTokenStakingNode();
    }

    function testNodeIdView() public {
        uint256 _nodeId = tokenStakingNode.nodeId();
        assertEq(_nodeId, 0);
    }

    function testImplementationView() public {
        address _implementation = tokenStakingNode.implementation();
        vm.prank(actors.ops.STAKING_NODE_CREATOR);
        tokenStakingNodesManager.createTokenStakingNode();
        ITokenStakingNode _newTokenStakingNode = tokenStakingNodesManager.nodes(0);
        assertEq(_implementation, address(_newTokenStakingNode.implementation()));
    }

    function testDepositAssetsToEigenlayerSuccessFuzz(
        uint256 wstethAmount
    ) public {
        vm.assume(wstethAmount < 10_000 ether && wstethAmount >= 2 wei);
        
        testAssetUtils.assumeEnoughStakeLimit(wstethAmount);

        // 1. Obtain wstETH and Deposit assets to ynEigen by User
        IERC20 wstETH = IERC20(chainAddresses.lsd.WSTETH_ADDRESS);
        testAssetUtils.depositAsset(ynEigenToken, address(wstETH), wstethAmount, address(this));

        // 2. Deposit assets to Eigenlayer by Token Staking Node

        IERC20[] memory assets = new IERC20[](1);
        assets[0] = wstETH;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = wstethAmount;
        uint256 nodeId = tokenStakingNode.nodeId();
        vm.prank(actors.ops.STRATEGY_CONTROLLER);
        eigenStrategyManager.stakeAssetsToNode(nodeId, assets, amounts);

        uint256 expectedStETHAmount = IwstETH(address(wstETH)).stEthPerToken() * amounts[0] / 1e18;

        // TODO: figure out why this doesn't match.
        // assertTrue(
        //     compareWithThreshold(deposits[0], expectedStETHAmount, 2),
        //     "Strategy user underlying view does not match expected stETH amount within threshold"
        // );

        uint256 treshold = wstethAmount / 1e17 + 3;
        uint256 expectedBalance = eigenStrategyManager.getStakedAssetBalance(assets[0]);
        assertTrue(
            compareWithThreshold(expectedBalance, amounts[0], treshold),
            "Staked asset balance does not match expected deposits"
        );

        uint256 strategyUserUnderlyingView =
            eigenStrategyManager.strategies(assets[0]).userUnderlyingView(address(tokenStakingNode));

        assertTrue(
            compareWithThreshold(strategyUserUnderlyingView, expectedStETHAmount, treshold),
            "Strategy user underlying view does not match expected stETH amount within threshold"
        );
    }

    function testDepositAssetsToEigenlayerFail() public {
        // 1. Obtain wstETH and Deposit assets to ynEigen by User
        IERC20 wstETH = IERC20(chainAddresses.lsd.WSTETH_ADDRESS);
        uint256 balance = testAssetUtils.get_wstETH(address(this), 10 ether);
        wstETH.approve(address(ynEigenToken), balance);
        ynEigenToken.deposit(wstETH, balance, address(this));
        uint256 nodeId = tokenStakingNode.nodeId();

        // 2. Deposit should fail when paused
        IStrategyManager strategyManager = eigenStrategyManager.strategyManager();
        vm.prank(chainAddresses.eigenlayer.STRATEGY_MANAGER_PAUSER_ADDRESS);
        IPausable(address(strategyManager)).pause(1);
		IERC20[] memory assets = new IERC20[](1);
		assets[0] = wstETH;
		uint256[] memory amounts = new uint256[](1);
		amounts[0] = balance;
		vm.prank(actors.ops.STRATEGY_CONTROLLER);
		vm.expectRevert(IPausable.CurrentlyPaused.selector);
		eigenStrategyManager.stakeAssetsToNode(nodeId, assets, amounts);
	}


    function testTokenQueueWithdrawals() public {
        uint256 wstethAmount = 100 ether;
        IERC20 wstETH = IERC20(chainAddresses.lsd.WSTETH_ADDRESS);
        uint256 nodeId = tokenStakingNode.nodeId();
        {
            // 1. Obtain wstETH and Deposit assets to ynEigen by User
            testAssetUtils.depositAsset(ynEigenToken, address(wstETH), wstethAmount, address(this));

            // 2. Deposit assets to Eigenlayer by Token Staking Node

            IERC20[] memory assets = new IERC20[](1);
            assets[0] = wstETH;
            uint256[] memory amounts = new uint256[](1);
            amounts[0] = wstethAmount;
            vm.prank(actors.ops.STRATEGY_CONTROLLER);
            eigenStrategyManager.stakeAssetsToNode(nodeId, assets, amounts);
        }

        NodeStateSnapshot before = new NodeStateSnapshot();
        before.takeSnapshot(address(this), nodeId);

        uint256 withdrawnShares = 50 ether;

        // 3. Queue withdrawals
        vm.startPrank(actors.ops.STAKING_NODES_WITHDRAWER);
        tokenStakingNode.queueWithdrawals(eigenStrategyManager.strategies(wstETH), withdrawnShares);
        vm.stopPrank();

        NodeStateSnapshot afterQueued = new NodeStateSnapshot();
        afterQueued.takeSnapshot(address(this), nodeId);

        // Assert queuedShares increased
        assertEq(
            afterQueued.getStrategyQueuedShares(eigenStrategyManager.strategies(wstETH)),
            before.getStrategyQueuedShares(eigenStrategyManager.strategies(wstETH)) + withdrawnShares,
            "Queued shares should have increased"
        );

        // Assert everything else stayed the same
        assertEq(afterQueued.totalAssets(), before.totalAssets(), "Total assets should not have changed");
        assertEq(afterQueued.totalSupply(), before.totalSupply(), "Total supply should not have changed");
        assertEq(
            afterQueued.getWithdrawnByToken(address(wstETH)),
            before.getWithdrawnByToken(address(wstETH)),
            "Withdrawn amount should not have changed"
        );

        // Assert staked asset balance decreased
        assertApproxEqAbs(
            afterQueued.getStakedAssetBalanceForNode(address(wstETH)),
            before.getStakedAssetBalanceForNode(address(wstETH)),
            10,
            "Staked asset balance should have decreased by withdrawn shares"
        );

        // Assert strategy shares decreased
        assertEq(
            afterQueued.getStrategySharesForNode(address(wstETH)),
            before.getStrategySharesForNode(address(wstETH)) - withdrawnShares,
            "Strategy shares should have decreased by withdrawn shares"
        );
    }

    function testQueueAndCompleteWithdrawals() public {
        // Stake some wstETH to the node
        uint256 stakeAmount = 100 ether;
        uint256 nodeId = tokenStakingNode.nodeId();
        uint256 sharesToWithdraw;
        uint256 withdrawAmount;
        IERC20 wstETH = IERC20(chainAddresses.lsd.WSTETH_ADDRESS);

        IStrategy wstETHStrategy = eigenStrategyManager.strategies(wstETH);
        uint32 _startBlock;

        // 1. Obtain wstETH and Deposit assets to ynEigen by User
        testAssetUtils.depositAsset(ynEigenToken, address(wstETH), stakeAmount, address(this));

        IERC20[] memory assets = new IERC20[](1);
        assets[0] = IERC20(address(wstETH));
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = stakeAmount;

        vm.prank(actors.ops.STRATEGY_CONTROLLER);
        eigenStrategyManager.stakeAssetsToNode(nodeId, assets, amounts);

        // Prepare for withdrawal
        withdrawAmount = stakeAmount / 2;
        sharesToWithdraw = wstETHStrategy.underlyingToShares(IwstETH(address(wstETH)).getStETHByWstETH(withdrawAmount));

        // Queue withdrawal
        vm.prank(actors.ops.STAKING_NODES_WITHDRAWER);
        tokenStakingNode.queueWithdrawals(wstETHStrategy, sharesToWithdraw);

        _startBlock = uint32(block.number);

        IStrategy[] memory _strategies = new IStrategy[](1);
        _strategies[0] = wstETHStrategy;
        vm.roll(block.number + eigenLayer.delegationManager.minWithdrawalDelayBlocks() + 1);

        {
            // Capture state before completing withdrawal
            NodeStateSnapshot before = new NodeStateSnapshot();
            before.takeSnapshot(address(this), nodeId);

            uint256[] memory _shares = new uint256[](1);
            _shares[0] = sharesToWithdraw;

            // Complete queued withdrawal
            vm.startPrank(actors.ops.STAKING_NODES_WITHDRAWER);
            IDelegationManagerTypes.Withdrawal memory withdrawal = IDelegationManagerTypes.Withdrawal({
                staker: address(tokenStakingNode),
                delegatedTo: eigenLayer.delegationManager.delegatedTo(address(tokenStakingNode)),
                withdrawer: address(tokenStakingNode),
                nonce: 0,
                startBlock: _startBlock,
                strategies: _strategies,
                scaledShares: _shares
            });
            tokenStakingNode.completeQueuedWithdrawals(
                withdrawal,
                false
            );
            vm.stopPrank();

            NodeStateSnapshot afterCompletion = new NodeStateSnapshot();
            afterCompletion.takeSnapshot(address(this), nodeId);

            // Assert withdrawn amount increased
            assertApproxEqAbs(
                afterCompletion.getWithdrawnByToken(address(wstETH)),
                before.getWithdrawnByToken(address(wstETH)) + withdrawAmount,
                3,
                "Withdrawn amount should have increased by withdrawAmount"
            );

            // Assert queued shares decreased
            assertEq(
                afterCompletion.getStrategyQueuedShares(wstETHStrategy),
                before.getStrategyQueuedShares(wstETHStrategy) - sharesToWithdraw,
                "Queued shares should have decreased by sharesToWithdraw"
            );

            // Assert total supply remained unchanged
            assertEq(afterCompletion.totalSupply(), before.totalSupply(), "Total supply should remain unchanged");

            // Assert total assets remained approximately unchanged
            assertApproxEqAbs(
                afterCompletion.totalAssets(),
                before.totalAssets(),
                3,
                "Total assets should remain approximately unchanged"
            );

            eigenStrategyManager.updateTokenStakingNodesBalances(wstETH);

            assertApproxEqAbs(
                afterCompletion.totalAssets(),
                ynEigenToken.totalAssets(),
                3,
                "Total assets should have decreased by approximately the withdraw amount"
            );
        }
    }
}

contract TokenStakingNodeDelegate is ynEigenIntegrationBaseTest {

    using stdStorage for StdStorage;
    using BytesLib for bytes;

    ITokenStakingNode tokenStakingNodeInstance;
    uint256 nodeId;

    TestAssetUtils testAssetUtils;

    address user = vm.addr(156_737);

    address operator1 = address(0x9999);
    address operator2 = address(0x8888);

    function setUp() public override {
        super.setUp();

        address[] memory operators = new address[](2);
        operators[0] = operator1;
        operators[1] = operator2;

        for (uint256 i = 0; i < operators.length; i++) {
            vm.prank(operators[i]);
            eigenLayer.delegationManager.registerAsOperator(address(0),0, "ipfs://some-ipfs-hash");
        }

        vm.prank(actors.ops.STAKING_NODE_CREATOR);
        tokenStakingNodeInstance = tokenStakingNodesManager.createTokenStakingNode();
        nodeId = tokenStakingNodeInstance.nodeId();
    }

    constructor() {
        testAssetUtils = new TestAssetUtils();
    }

    struct QueuedWithdrawalInfo {
        uint256 withdrawnAmount;
        IStrategy strategy;
        address operator;
    }

    function _getWithdrawals(
        QueuedWithdrawalInfo[] memory queuedWithdrawals,
        uint256 nodeId
    ) internal returns (IDelegationManager.Withdrawal[] memory _withdrawals) {
        _withdrawals = new IDelegationManager.Withdrawal[](queuedWithdrawals.length);
        address _stakingNode = address(tokenStakingNodesManager.nodes(nodeId));
        uint256 indexStartForWithdrawalRoots =
            eigenLayer.delegationManager.cumulativeWithdrawalsQueued(_stakingNode) - queuedWithdrawals.length;

        for (uint256 i = 0; i < queuedWithdrawals.length; i++) {
            uint256[] memory _shares = new uint256[](1);
            _shares[0] = queuedWithdrawals[i].withdrawnAmount;
            IStrategy[] memory _strategies = new IStrategy[](1);
            _strategies[0] = queuedWithdrawals[i].strategy;
            _withdrawals[i] = IDelegationManagerTypes.Withdrawal({
                staker: _stakingNode,
                delegatedTo: queuedWithdrawals[i].operator,
                withdrawer: _stakingNode,
                nonce: indexStartForWithdrawalRoots + i,
                startBlock: uint32(block.number),
                strategies: _strategies,
                scaledShares: _shares
            });
        }
    }

    function testTokenStakingNodeDelegate() public {
        ISignatureUtils.SignatureWithExpiry memory signature;
        bytes32 approverSalt;

        vm.prank(actors.admin.STAKING_NODES_DELEGATOR);
        tokenStakingNodeInstance.delegate(operator1, signature, approverSalt);
        address delegatedTo = eigenLayer.delegationManager.delegatedTo(address(tokenStakingNodeInstance));
        assertEq(delegatedTo, operator1, "Delegation did not occur as expected.");

        // Verify delegatedTo is set correctly in the TokenStakingNode contract
        assertEq(tokenStakingNodeInstance.delegatedTo(), operator1, "TokenStakingNode delegatedTo not set correctly");
    }

    function testTokenStakingNodeUndelegate() public {
        ISignatureUtils.SignatureWithExpiry memory signature;
        bytes32 approverSalt;

        vm.prank(actors.admin.STAKING_NODES_DELEGATOR);
        tokenStakingNodeInstance.delegate(operator1, signature, approverSalt);

        // Attempt to undelegate
        vm.expectRevert();
        tokenStakingNodeInstance.undelegate();

        IStrategyManager strategyManager = tokenStakingNodesManager.strategyManager();
        uint256 stakerStrategyListLength = strategyManager.stakerStrategyListLength(address(tokenStakingNodeInstance));
        assertEq(stakerStrategyListLength, 0, "Staker strategy list length should be 0.");

        // Now actually undelegate with the correct role
        vm.prank(actors.admin.STAKING_NODES_DELEGATOR);
        tokenStakingNodeInstance.undelegate();

        // Verify undelegation
        address delegatedAddress = eigenLayer.delegationManager.delegatedTo(address(tokenStakingNodeInstance));
        assertEq(delegatedAddress, address(0), "Delegation should be cleared after undelegation.");

        // Verify delegatedTo is set to zero in the TokenStakingNode contract
        assertEq(
            tokenStakingNodeInstance.delegatedTo(),
            address(0),
            "TokenStakingNode delegatedTo not cleared after undelegation"
        );
    }

    function testDelegateUndelegateAndDelegateAgain() public {
        IDelegationManager delegationManager = tokenStakingNodesManager.delegationManager();

        // Delegate to operator1
        vm.prank(actors.admin.STAKING_NODES_DELEGATOR);
        tokenStakingNodeInstance.delegate(
            operator1, ISignatureUtils.SignatureWithExpiry({signature: "", expiry: 0}), bytes32(0)
        );

        address delegatedOperator1 = delegationManager.delegatedTo(address(tokenStakingNodeInstance));
        assertEq(delegatedOperator1, operator1, "Delegation is not set to operator1.");

        // Undelegate
        vm.prank(actors.admin.STAKING_NODES_DELEGATOR);
        tokenStakingNodeInstance.undelegate();

        address undelegatedAddress = delegationManager.delegatedTo(address(tokenStakingNodeInstance));
        assertEq(undelegatedAddress, address(0), "Delegation should be cleared after undelegation.");

        // Delegate to operator2
        vm.prank(actors.admin.STAKING_NODES_DELEGATOR);
        tokenStakingNodeInstance.delegate(
            operator2, ISignatureUtils.SignatureWithExpiry({signature: "", expiry: 0}), bytes32(0)
        );

        address delegatedOperator2 = delegationManager.delegatedTo(address(tokenStakingNodeInstance));
        assertEq(delegatedOperator2, operator2, "Delegation is not set to operator2.");
    }

    function testDelegateUndelegateWithExistingStake() public {
        uint256 wstethAmount = 100 ether;
        uint256 sfrxethAmount = 100 ether;

        // 1. Obtain wstETH and sfrxETH and deposit assets to ynEigen by User
        IERC20 wstETH = IERC20(chainAddresses.lsd.WSTETH_ADDRESS);
        IERC20 sfrxETH = IERC20(chainAddresses.lsd.SFRXETH_ADDRESS);
        testAssetUtils.depositAsset(ynEigenToken, address(wstETH), wstethAmount, address(this));
        testAssetUtils.depositAsset(ynEigenToken, address(sfrxETH), sfrxethAmount, address(this));

        // 2. Deposit assets to Eigenlayer by Token Staking Node
        IERC20[] memory assets = new IERC20[](2);
        assets[0] = wstETH;
        assets[1] = sfrxETH;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = wstethAmount;
        amounts[1] = sfrxethAmount;
        uint256 nodeId = tokenStakingNodeInstance.nodeId();
        vm.prank(actors.ops.STRATEGY_CONTROLLER);
        eigenStrategyManager.stakeAssetsToNode(nodeId, assets, amounts);

        IStrategyManager strategyManager = tokenStakingNodesManager.strategyManager();
        uint256 initialStrategyListLength = strategyManager.stakerStrategyListLength(address(tokenStakingNodeInstance));
        assertEq(initialStrategyListLength, 2, "Initial strategy list length should be 2.");

        // Delegate to operator
        ISignatureUtils.SignatureWithExpiry memory signature;
        bytes32 approverSalt;
        vm.prank(actors.admin.STAKING_NODES_DELEGATOR);
        tokenStakingNodeInstance.delegate(operator1, signature, approverSalt);

        // Build array of strategies based on assets
        IStrategy[] memory strategies = new IStrategy[](2);
        for (uint256 i = 0; i < assets.length; i++) {
            strategies[i] = eigenStrategyManager.strategies(assets[i]);
        }

        // Verify delegation
        assertEq(tokenStakingNodeInstance.delegatedTo(), operator1, "TokenStakingNode not delegated correctly");

        IDelegationManager delegationManager = tokenStakingNodesManager.delegationManager();

        // Get initial operator shares for each strategy
        uint256[] memory initialShares = delegationManager.getOperatorShares(operator1, strategies);

        for (uint256 i = 0; i < strategies.length; i++) {
            assertGt(initialShares[i], 0, "Operator should have shares");
        }

        // Get initial queued shares
        uint256[] memory initialQueuedShares = new uint256[](2);
        for (uint256 i = 0; i < strategies.length; i++) {
            initialQueuedShares[i] = tokenStakingNodeInstance.queuedShares(strategies[i]);
        }

        // Undelegate
        vm.prank(actors.admin.STAKING_NODES_DELEGATOR);
        bytes32[] memory withdrawalRoots = tokenStakingNodeInstance.undelegate();

        // Verify undelegation state
        assertEq(tokenStakingNodeInstance.delegatedTo(), address(0), "TokenStakingNode delegatedTo not cleared");
        assertEq(
            delegationManager.delegatedTo(address(tokenStakingNodeInstance)),
            address(0),
            "Delegation not cleared in DelegationManager"
        );

        // Verify queued shares increased by the correct amount
        for (uint256 i = 0; i < strategies.length; i++) {
            uint256 finalQueuedShares = tokenStakingNodeInstance.queuedShares(strategies[i]);
            assertEq(
                finalQueuedShares - initialQueuedShares[i],
                initialShares[i],
                "Queued shares should increase by operator shares amount"
            );
        }

        // Verify withdrawal roots were created
        assertGt(withdrawalRoots.length, 0, "Should have withdrawal roots");
    }

    function testDelegateUndelegateAndDelegateAgainWithExistingStake() public {
        uint256 wstethAmount = 100 ether;
        uint256 sfrxethAmount = 100 ether;

        // 1. Obtain wstETH and sfrxETH and deposit assets to ynEigen by User
        IERC20 wstETH = IERC20(chainAddresses.lsd.WSTETH_ADDRESS);
        IERC20 sfrxETH = IERC20(chainAddresses.lsd.SFRXETH_ADDRESS);
        testAssetUtils.depositAsset(ynEigenToken, address(wstETH), wstethAmount, address(this));
        testAssetUtils.depositAsset(ynEigenToken, address(sfrxETH), sfrxethAmount, address(this));

        // 2. Deposit assets to Eigenlayer by Token Staking Node
        IERC20[] memory assets = new IERC20[](2);
        assets[0] = wstETH;
        assets[1] = sfrxETH;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = wstethAmount;
        amounts[1] = sfrxethAmount;
        uint256 nodeId = tokenStakingNodeInstance.nodeId();
        vm.prank(actors.ops.STRATEGY_CONTROLLER);
        eigenStrategyManager.stakeAssetsToNode(nodeId, assets, amounts);

        IStrategyManager strategyManager = tokenStakingNodesManager.strategyManager();
        uint256 initialStrategyListLength = strategyManager.stakerStrategyListLength(address(tokenStakingNodeInstance));
        assertEq(initialStrategyListLength, 2, "Initial strategy list length should be 2.");

        // Delegate to operator
        ISignatureUtils.SignatureWithExpiry memory signature;
        bytes32 approverSalt;
        vm.prank(actors.admin.STAKING_NODES_DELEGATOR);
        tokenStakingNodeInstance.delegate(operator1, signature, approverSalt);

        // Build array of strategies based on assets
        IStrategy[] memory strategies = new IStrategy[](2);
        for (uint256 i = 0; i < assets.length; i++) {
            strategies[i] = eigenStrategyManager.strategies(assets[i]);
        }

        // Verify delegation
        assertEq(tokenStakingNodeInstance.delegatedTo(), operator1, "TokenStakingNode not delegated correctly");

        // Get initial operator shares for each strategy
        uint256[] memory initialShares = eigenLayer.delegationManager.getOperatorShares(operator1, strategies);
        for (uint256 i = 0; i < strategies.length; i++) {
            assertGt(initialShares[i], 0, "Operator should have shares");
        }

        // Undelegate
        vm.prank(actors.admin.STAKING_NODES_DELEGATOR);
        tokenStakingNodeInstance.undelegate();

        vm.prank(actors.admin.STAKING_NODES_DELEGATOR);
        tokenStakingNodeInstance.delegate(operator2, signature, approverSalt);

        // Verify delegation
        assertEq(tokenStakingNodeInstance.delegatedTo(), operator2, "TokenStakingNode not delegated correctly");

        IDelegationManager delegationManager = tokenStakingNodesManager.delegationManager();

        // Get final operator shares for each strategy
        uint256[] memory finalShares = delegationManager.getOperatorShares(operator2, strategies);

        for (uint256 i = 0; i < strategies.length; i++) {
            finalShares[i] += tokenStakingNodeInstance.queuedShares(strategies[i]);
            assertEq(finalShares[i], initialShares[i], "Operator should have same shares");
        }
    }

    function testDelegateUndelegateAndDelegateAgainWithoutExistingStake() public {
        uint256 wstethAmount = 100 ether;
        uint256 sfrxethAmount = 100 ether;

        // 1. Obtain wstETH and sfrxETH and deposit assets to ynEigen by User
        IERC20 wstETH = IERC20(chainAddresses.lsd.WSTETH_ADDRESS);
        IERC20 sfrxETH = IERC20(chainAddresses.lsd.SFRXETH_ADDRESS);
        testAssetUtils.depositAsset(ynEigenToken, address(wstETH), wstethAmount, address(this));
        testAssetUtils.depositAsset(ynEigenToken, address(sfrxETH), sfrxethAmount, address(this));

        // 2. Deposit assets to Eigenlayer by Token Staking Node
        IERC20[] memory assets = new IERC20[](2);
        assets[0] = wstETH;
        assets[1] = sfrxETH;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = wstethAmount;
        amounts[1] = sfrxethAmount;
        uint256 nodeId = tokenStakingNodeInstance.nodeId();
        vm.prank(actors.ops.STRATEGY_CONTROLLER);
        eigenStrategyManager.stakeAssetsToNode(nodeId, assets, amounts);

        IStrategyManager strategyManager = tokenStakingNodesManager.strategyManager();
        uint256 initialStrategyListLength = strategyManager.stakerStrategyListLength(address(tokenStakingNodeInstance));
        assertEq(initialStrategyListLength, 2, "Initial strategy list length should be 2.");

        // Delegate to operator
        ISignatureUtils.SignatureWithExpiry memory signature;
        bytes32 approverSalt;
        vm.prank(actors.admin.STAKING_NODES_DELEGATOR);
        tokenStakingNodeInstance.delegate(operator1, signature, approverSalt);

        // Build array of strategies based on assets
        IStrategy[] memory strategies = new IStrategy[](2);
        for (uint256 i = 0; i < assets.length; i++) {
            strategies[i] = eigenStrategyManager.strategies(assets[i]);
        }

        // Verify delegation
        assertEq(tokenStakingNodeInstance.delegatedTo(), operator1, "TokenStakingNode not delegated correctly");

        // Get initial operator shares for each strategy
        uint256[] memory initialShares = eigenLayer.delegationManager.getOperatorShares(operator1, strategies);
        for (uint256 i = 0; i < strategies.length; i++) {
            assertGt(initialShares[i], 0, "Operator should have shares");
        }

        // Get initial queued shares
        uint256[] memory initialQueuedShares = new uint256[](2);
        for (uint256 i = 0; i < strategies.length; i++) {
            initialQueuedShares[i] = tokenStakingNodeInstance.queuedShares(strategies[i]);
        }

        // Undelegate
        vm.prank(actors.admin.STAKING_NODES_DELEGATOR);
        tokenStakingNodeInstance.undelegate();

        // Create array of queued withdrawals based on strategies
        QueuedWithdrawalInfo[] memory queuedWithdrawals = new QueuedWithdrawalInfo[](strategies.length);

        for (uint256 i = 0; i < strategies.length; i++) {
            queuedWithdrawals[i] =
                QueuedWithdrawalInfo({withdrawnAmount: initialShares[i], strategy: strategies[i], operator: operator1});
        }

        IDelegationManager delegationManager = tokenStakingNodesManager.delegationManager();

        assertEq(tokenStakingNodeInstance.delegatedTo(), address(0), "TokenStakingNode delegatedTo is cleared");
        assertEq(
            delegationManager.delegatedTo(address(tokenStakingNodeInstance)),
            address(0),
            "Delegation not cleared in DelegationManager"
        );

        assertEq(tokenStakingNodeInstance.isSynchronized(), true, "TokenStakingNode should be synchronized");

        // Verify queued shares increased by the correct amount
        for (uint256 i = 0; i < strategies.length; i++) {
            uint256 finalQueuedShares = tokenStakingNodeInstance.queuedShares(strategies[i]);
            assertEq(
                finalQueuedShares - initialQueuedShares[i],
                initialShares[i],
                "Queued shares should increase by operator shares amount"
            );
        }

        {
            IDelegationManager.Withdrawal[] memory _withdrawals = _getWithdrawals(queuedWithdrawals, nodeId);

            {
                // advance time to allow completion
                vm.roll(block.number + delegationManager.minWithdrawalDelayBlocks() + 1);
            }

            // complete queued withdrawals
            {
                vm.startPrank(actors.admin.STAKING_NODES_DELEGATOR);
                tokenStakingNodesManager.nodes(nodeId).completeQueuedWithdrawalsAsShares(
                    _withdrawals
                );
                vm.stopPrank();
            }

            vm.prank(actors.admin.STAKING_NODES_DELEGATOR);
            tokenStakingNodeInstance.delegate(operator2, signature, approverSalt);

            assertEq(tokenStakingNodeInstance.delegatedTo(), operator2, "TokenStakingNode not delegated correctly");

            {
                // Verify queued shares decreased by the correct amount
                for (uint256 i = 0; i < strategies.length; i++) {
                    uint256 finalQueuedShares = tokenStakingNodeInstance.queuedShares(strategies[i]);
                    assertEq(finalQueuedShares, 0, "Queued shares should decrease to 0");
                }
            }

            {
                uint256 stakerStrategyListLength =
                    strategyManager.stakerStrategyListLength(address(tokenStakingNodeInstance));
                assertEq(
                    stakerStrategyListLength, initialStrategyListLength, "Staker strategy list length should be 0."
                );
                for (uint256 i = 0; i < strategies.length; i++) {
                    assertEq(
                        strategyManager.stakerDepositShares(address(tokenStakingNodeInstance), strategies[i]),
                        initialShares[i],
                        "Shares are not restaked correctly after undelegation"
                    );
                }
            }
        }

        // vm.prank(actors.admin.STAKING_NODES_DELEGATOR);
        // tokenStakingNodeInstance.delegate(operator2, signature, approverSalt);

        // // Verify delegation
        // assertEq(tokenStakingNodeInstance.delegatedTo(), operator2, "TokenStakingNode not delegated correctly");

        // // Get initial operator shares for each strategy
        // uint256[] memory finalShares = new uint256[](2);
        // for (uint256 i = 0; i < strategies.length; i++) {
        //     finalShares[i] = eigenLayer.delegationManager.operatorShares(operator2, strategies[i]);
        //     assertEq(finalShares[i], initialShares[i], "Operator should have same shares");
        // }
    }

    function testOperatorUndelegateTokenStakingNode() public {
        ISignatureUtils.SignatureWithExpiry memory signature;
        bytes32 approverSalt;

        vm.prank(actors.admin.STAKING_NODES_DELEGATOR);
        tokenStakingNodeInstance.delegate(operator1, signature, approverSalt);

        // Now actually undelegate with the correct role
        vm.prank(operator1);
        eigenLayer.delegationManager.undelegate(address(tokenStakingNodeInstance));

        // Verify undelegation
        address delegatedAddress = eigenLayer.delegationManager.delegatedTo(address(tokenStakingNodeInstance));
        assertEq(delegatedAddress, address(0), "Delegation should be cleared in DelegationManager after undelegation.");

        // Verify delegatedTo is set to operator1 in the TokenStakingNode contract
        assertEq(
            tokenStakingNodeInstance.delegatedTo(),
            operator1,
            "TokenStakingNode delegatedTo not set to operator1 after undelegation even if state is not synchronized"
        );

        assertEq(tokenStakingNodeInstance.isSynchronized(), false, "TokenStakingNode should not be synchronized");

        IStrategy[] memory strategies = new IStrategy[](1);
        uint256[] memory initialShares = new uint256[](1);

        // Since delegatedTo is not synchronized, the functions which require synchronization will revert
        vm.expectRevert(TokenStakingNode.NotSynchronized.selector);
        vm.prank(address(eigenStrategyManager));
        tokenStakingNodeInstance.depositAssetsToEigenlayer(assets, new uint256[](0), new IStrategy[](0));

        vm.expectRevert(TokenStakingNode.NotSynchronized.selector);
        vm.prank(actors.ops.STAKING_NODES_WITHDRAWER);
        tokenStakingNodeInstance.queueWithdrawals(strategies[0], initialShares[0]);

        vm.expectRevert(TokenStakingNode.NotSynchronized.selector);
        vm.prank(actors.ops.STAKING_NODES_WITHDRAWER);
        tokenStakingNodeInstance.completeQueuedWithdrawals(
            IDelegationManagerTypes.Withdrawal({
                staker: address(tokenStakingNodeInstance),
                delegatedTo: address(0),
                withdrawer: address(tokenStakingNodeInstance),
                nonce: 0,
                startBlock: uint32(block.number),
                strategies: new IStrategy[](0),
                scaledShares: new uint256[](0)
            }),
            true
        );

        vm.expectRevert(TokenStakingNode.NotSynchronized.selector);
        vm.prank(actors.admin.STAKING_NODES_DELEGATOR);
        tokenStakingNodeInstance.completeQueuedWithdrawalsAsShares(
            new IDelegationManager.Withdrawal[](0)
        );

        vm.expectRevert(TokenStakingNode.NotSynchronized.selector);
        vm.prank(actors.admin.STAKING_NODES_DELEGATOR);
        tokenStakingNodeInstance.delegate(operator1, signature, approverSalt);

        vm.expectRevert(TokenStakingNode.NotSynchronized.selector);
        vm.prank(actors.admin.STAKING_NODES_DELEGATOR);
        tokenStakingNodeInstance.undelegate();
    }

    function testOperatorUndelegateSynchronizeAndCompleteWithdrawals() public {
        uint256 wstethAmount = 100 ether;
        uint256 sfrxethAmount = 100 ether;

        // 1. Obtain wstETH and sfrxETH and deposit assets to ynEigen by User
        IERC20 wstETH = IERC20(chainAddresses.lsd.WSTETH_ADDRESS);
        IERC20 sfrxETH = IERC20(chainAddresses.lsd.SFRXETH_ADDRESS);
        testAssetUtils.depositAsset(ynEigenToken, address(wstETH), wstethAmount, address(this));
        testAssetUtils.depositAsset(ynEigenToken, address(sfrxETH), sfrxethAmount, address(this));

        // 2. Deposit assets to Eigenlayer by Token Staking Node
        IERC20[] memory assets = new IERC20[](2);
        assets[0] = wstETH;
        assets[1] = sfrxETH;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = wstethAmount;
        amounts[1] = sfrxethAmount;
        uint256 nodeId = tokenStakingNodeInstance.nodeId();
        vm.prank(actors.ops.STRATEGY_CONTROLLER);
        eigenStrategyManager.stakeAssetsToNode(nodeId, assets, amounts);

        IStrategyManager strategyManager = tokenStakingNodesManager.strategyManager();
        uint256 initialStrategyListLength = strategyManager.stakerStrategyListLength(address(tokenStakingNodeInstance));
        assertEq(initialStrategyListLength, 2, "Initial strategy list length should be 2.");

        // Delegate to operator
        ISignatureUtils.SignatureWithExpiry memory signature;
        bytes32 approverSalt;
        vm.prank(actors.admin.STAKING_NODES_DELEGATOR);
        tokenStakingNodeInstance.delegate(operator1, signature, approverSalt);

        // Build array of strategies based on assets
        IStrategy[] memory strategies = new IStrategy[](2);
        for (uint256 i = 0; i < assets.length; i++) {
            strategies[i] = eigenStrategyManager.strategies(assets[i]);
        }

        // Verify delegation
        assertEq(tokenStakingNodeInstance.delegatedTo(), operator1, "TokenStakingNode not delegated correctly");

        // Get initial operator shares for each strategy
        IDelegationManager delegationManager = tokenStakingNodesManager.delegationManager();
        uint256[] memory initialShares = delegationManager.getOperatorShares(operator1, strategies);
        for (uint256 i = 0; i < strategies.length; i++) {
            assertGt(initialShares[i], 0, "Operator should have shares");
        }

        // Get initial queued shares
        uint256[] memory initialQueuedShares = new uint256[](2);
        for (uint256 i = 0; i < strategies.length; i++) {
            initialQueuedShares[i] = tokenStakingNodeInstance.queuedShares(strategies[i]);
        }

        // Create array of queued withdrawals based on strategies
        QueuedWithdrawalInfo[] memory queuedWithdrawals = new QueuedWithdrawalInfo[](strategies.length);

        for (uint256 i = 0; i < strategies.length; i++) {
            queuedWithdrawals[i] =
                QueuedWithdrawalInfo({withdrawnAmount: initialShares[i], strategy: strategies[i], operator: operator1});
        }

        // Undelegate by operator
        vm.prank(operator1);
        bytes32[] memory withdrawalRoots = eigenLayer.delegationManager.undelegate(address(tokenStakingNodeInstance));

        assertEq(tokenStakingNodeInstance.delegatedTo(), address(operator1), "TokenStakingNode delegatedTo not cleared");
        assertEq(
            delegationManager.delegatedTo(address(tokenStakingNodeInstance)),
            address(0),
            "Delegation not cleared in DelegationManager"
        );

        vm.prank(actors.admin.STAKING_NODES_DELEGATOR);
        tokenStakingNodeInstance.synchronize();

        assertEq(tokenStakingNodeInstance.isSynchronized(), true, "TokenStakingNode should be synchronized");

        // Verify queued shares increased by the correct amount
        for (uint256 i = 0; i < strategies.length; i++) {
            uint256 finalQueuedShares = tokenStakingNodeInstance.queuedShares(strategies[i]);
            assertEq(
                finalQueuedShares - initialQueuedShares[i],
                initialShares[i],
                "Queued shares should increase by operator shares amount"
            );
        }

        {
            IDelegationManager.Withdrawal[] memory _withdrawals = _getWithdrawals(queuedWithdrawals, nodeId);

            {
                // advance time to allow completion
                vm.roll(block.number + delegationManager.minWithdrawalDelayBlocks() + 1);
            }

            // complete queued withdrawals
            {
                vm.startPrank(actors.admin.STAKING_NODES_DELEGATOR);
                tokenStakingNodesManager.nodes(nodeId).completeQueuedWithdrawalsAsShares(
                    _withdrawals
                );
                vm.stopPrank();
            }

            {
                // Verify queued shares decreased by the correct amount
                for (uint256 i = 0; i < strategies.length; i++) {
                    uint256 finalQueuedShares = tokenStakingNodeInstance.queuedShares(strategies[i]);
                    assertEq(finalQueuedShares, 0, "Queued shares should decrease to 0");
                }
            }

            {
                uint256 stakerStrategyListLength =
                    strategyManager.stakerStrategyListLength(address(tokenStakingNodeInstance));
                assertEq(
                    stakerStrategyListLength, initialStrategyListLength, "Staker strategy list length should be 0."
                );
                for (uint256 i = 0; i < strategies.length; i++) {
                    assertEq(
                        strategyManager.stakerDepositShares(address(tokenStakingNodeInstance), strategies[i]),
                        initialShares[i],
                        "Shares are not restaked correctly after undelegation"
                    );
                }
            }
        }
    }

    function testOperatorUndelegateSynchronizeDelegateAndCompleteWithdrawals() public {
        uint256 wstethAmount = 100 ether;
        uint256 sfrxethAmount = 100 ether;

        // 1. Obtain wstETH and sfrxETH and deposit assets to ynEigen by User
        IERC20 wstETH = IERC20(chainAddresses.lsd.WSTETH_ADDRESS);
        IERC20 sfrxETH = IERC20(chainAddresses.lsd.SFRXETH_ADDRESS);
        testAssetUtils.depositAsset(ynEigenToken, address(wstETH), wstethAmount, address(this));
        testAssetUtils.depositAsset(ynEigenToken, address(sfrxETH), sfrxethAmount, address(this));

        // 2. Deposit assets to Eigenlayer by Token Staking Node
        IERC20[] memory assets = new IERC20[](2);
        assets[0] = wstETH;
        assets[1] = sfrxETH;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = wstethAmount;
        amounts[1] = sfrxethAmount;
        uint256 nodeId = tokenStakingNodeInstance.nodeId();
        vm.prank(actors.ops.STRATEGY_CONTROLLER);
        eigenStrategyManager.stakeAssetsToNode(nodeId, assets, amounts);

        IStrategyManager strategyManager = tokenStakingNodesManager.strategyManager();
        uint256 initialStrategyListLength = strategyManager.stakerStrategyListLength(address(tokenStakingNodeInstance));
        assertEq(initialStrategyListLength, 2, "Initial strategy list length should be 2.");

        // Delegate to operator
        ISignatureUtils.SignatureWithExpiry memory signature;
        bytes32 approverSalt;
        vm.prank(actors.admin.STAKING_NODES_DELEGATOR);
        tokenStakingNodeInstance.delegate(operator1, signature, approverSalt);

        // Build array of strategies based on assets
        IStrategy[] memory strategies = new IStrategy[](2);
        for (uint256 i = 0; i < assets.length; i++) {
            strategies[i] = eigenStrategyManager.strategies(assets[i]);
        }

        // Verify delegation
        assertEq(tokenStakingNodeInstance.delegatedTo(), operator1, "TokenStakingNode not delegated correctly");

        // Get initial operator shares for each strategy
        IDelegationManager delegationManager = tokenStakingNodesManager.delegationManager();
        uint256[] memory initialShares = delegationManager.getOperatorShares(operator1, strategies);
        for (uint256 i = 0; i < strategies.length; i++) {
            assertGt(initialShares[i], 0, "Operator should have shares");
        }

        // Get initial queued shares
        uint256[] memory initialQueuedShares = new uint256[](3);
        for (uint256 i = 0; i < strategies.length; i++) {
            initialQueuedShares[i] = tokenStakingNodeInstance.queuedShares(strategies[i]);
        }

        // Create array of queued withdrawals based on strategies
        QueuedWithdrawalInfo[] memory queuedWithdrawals = new QueuedWithdrawalInfo[](strategies.length);

        for (uint256 i = 0; i < strategies.length; i++) {
            queuedWithdrawals[i] =
                QueuedWithdrawalInfo({withdrawnAmount: initialShares[i], strategy: strategies[i], operator: operator1});
        }

        // Undelegate by operator
        vm.prank(operator1);
        bytes32[] memory withdrawalRoots = eigenLayer.delegationManager.undelegate(address(tokenStakingNodeInstance));

        assertEq(tokenStakingNodeInstance.delegatedTo(), address(operator1), "TokenStakingNode delegatedTo not cleared");
        assertEq(
            delegationManager.delegatedTo(address(tokenStakingNodeInstance)),
            address(0),
            "Delegation not cleared in DelegationManager"
        );

        vm.prank(actors.admin.STAKING_NODES_DELEGATOR);
        tokenStakingNodeInstance.synchronize();

        assertEq(tokenStakingNodeInstance.isSynchronized(), true, "TokenStakingNode should be synchronized");

        vm.prank(actors.admin.STAKING_NODES_DELEGATOR);
        tokenStakingNodeInstance.delegate(operator2, signature, approverSalt);

        // Verify queued shares increased by the correct amount
        for (uint256 i = 0; i < strategies.length; i++) {
            uint256 finalQueuedShares = tokenStakingNodeInstance.queuedShares(strategies[i]);
            assertEq(
                finalQueuedShares - initialQueuedShares[i],
                initialShares[i],
                "Queued shares should increase by operator shares amount"
            );
        }

        {
            IDelegationManager.Withdrawal[] memory _withdrawals = _getWithdrawals(queuedWithdrawals, nodeId);

            {
                // advance time to allow completion
                vm.roll(block.number + delegationManager.minWithdrawalDelayBlocks() + 1);
            }

            // complete queued withdrawals
            {
                vm.startPrank(actors.admin.STAKING_NODES_DELEGATOR);
                tokenStakingNodesManager.nodes(nodeId).completeQueuedWithdrawalsAsShares(
                    _withdrawals
                );
                vm.stopPrank();
            }

            {
                // Verify queued shares decreased by the correct amount
                for (uint256 i = 0; i < strategies.length; i++) {
                    uint256 finalQueuedShares = tokenStakingNodeInstance.queuedShares(strategies[i]);
                    assertEq(finalQueuedShares, 0, "Queued shares should decrease to 0");
                }
            }

            {
                uint256 stakerStrategyListLength =
                    strategyManager.stakerStrategyListLength(address(tokenStakingNodeInstance));
                assertEq(
                    stakerStrategyListLength, initialStrategyListLength, "Staker strategy list length should be 0."
                );
                for (uint256 i = 0; i < strategies.length; i++) {
                    assertEq(
                        strategyManager.stakerDepositShares(address(tokenStakingNodeInstance), strategies[i]),
                        initialShares[i],
                        "Shares are not restaked correctly after undelegation"
                    );
                }
            }
        }
    }

    function testOperatorUndelegateSynchronizeAndCompleteWithdrawalsAndDelegateAgain() public {
        uint256 wstethAmount = 100 ether;
        uint256 sfrxethAmount = 100 ether;

        // 1. Obtain wstETH and sfrxETH and deposit assets to ynEigen by User
        IERC20 wstETH = IERC20(chainAddresses.lsd.WSTETH_ADDRESS);
        IERC20 sfrxETH = IERC20(chainAddresses.lsd.SFRXETH_ADDRESS);
        testAssetUtils.depositAsset(ynEigenToken, address(wstETH), wstethAmount, address(this));
        testAssetUtils.depositAsset(ynEigenToken, address(sfrxETH), sfrxethAmount, address(this));

        // 2. Deposit assets to Eigenlayer by Token Staking Node
        IERC20[] memory assets = new IERC20[](2);
        assets[0] = wstETH;
        assets[1] = sfrxETH;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = wstethAmount;
        amounts[1] = sfrxethAmount;
        uint256 nodeId = tokenStakingNodeInstance.nodeId();
        vm.prank(actors.ops.STRATEGY_CONTROLLER);
        eigenStrategyManager.stakeAssetsToNode(nodeId, assets, amounts);

        IStrategyManager strategyManager = tokenStakingNodesManager.strategyManager();
        uint256 initialStrategyListLength = strategyManager.stakerStrategyListLength(address(tokenStakingNodeInstance));
        assertEq(initialStrategyListLength, 2, "Initial strategy list length should be 2.");

        // Delegate to operator
        ISignatureUtils.SignatureWithExpiry memory signature;
        bytes32 approverSalt;
        vm.prank(actors.admin.STAKING_NODES_DELEGATOR);
        tokenStakingNodeInstance.delegate(operator1, signature, approverSalt);

        // Build array of strategies based on assets
        IStrategy[] memory strategies = new IStrategy[](2);
        for (uint256 i = 0; i < assets.length; i++) {
            strategies[i] = eigenStrategyManager.strategies(assets[i]);
        }

        // Verify delegation
        assertEq(tokenStakingNodeInstance.delegatedTo(), operator1, "TokenStakingNode not delegated correctly");

        // Get initial operator shares for each strategy
        uint256[] memory initialShares = eigenLayer.delegationManager.getOperatorShares(operator1, strategies);
        for (uint256 i = 0; i < strategies.length; i++) {
            assertGt(initialShares[i], 0, "Operator should have shares");
        }

        // Get initial queued shares
        uint256[] memory initialQueuedShares = new uint256[](3);
        for (uint256 i = 0; i < strategies.length; i++) {
            initialQueuedShares[i] = tokenStakingNodeInstance.queuedShares(strategies[i]);
        }

        // Create array of queued withdrawals based on strategies
        QueuedWithdrawalInfo[] memory queuedWithdrawals = new QueuedWithdrawalInfo[](strategies.length);

        for (uint256 i = 0; i < strategies.length; i++) {
            queuedWithdrawals[i] =
                QueuedWithdrawalInfo({withdrawnAmount: initialShares[i], strategy: strategies[i], operator: operator1});
        }

        // Undelegate by operator
        vm.prank(operator1);
        bytes32[] memory withdrawalRoots = eigenLayer.delegationManager.undelegate(address(tokenStakingNodeInstance));

        assertEq(tokenStakingNodeInstance.delegatedTo(), address(operator1), "TokenStakingNode delegatedTo not cleared");
        assertEq(
            eigenLayer.delegationManager.delegatedTo(address(tokenStakingNodeInstance)),
            address(0),
            "Delegation not cleared in DelegationManager"
        );

        vm.prank(actors.admin.STAKING_NODES_DELEGATOR);
        tokenStakingNodeInstance.synchronize();

        assertEq(tokenStakingNodeInstance.isSynchronized(), true, "TokenStakingNode should be synchronized");

        // Verify queued shares increased by the correct amount
        for (uint256 i = 0; i < strategies.length; i++) {
            uint256 finalQueuedShares = tokenStakingNodeInstance.queuedShares(strategies[i]);
            assertEq(
                finalQueuedShares - initialQueuedShares[i],
                initialShares[i],
                "Queued shares should increase by operator shares amount"
            );
        }

        {
            IDelegationManager.Withdrawal[] memory _withdrawals = _getWithdrawals(queuedWithdrawals, nodeId);

            {
                // advance time to allow completion
                vm.roll(block.number + eigenLayer.delegationManager.minWithdrawalDelayBlocks() + 1);
            }

            // complete queued withdrawals
            {
                vm.startPrank(actors.admin.STAKING_NODES_DELEGATOR);
                tokenStakingNodesManager.nodes(nodeId).completeQueuedWithdrawalsAsShares(
                    _withdrawals
                );
                vm.stopPrank();
            }

            {
                // Verify queued shares decreased by the correct amount
                for (uint256 i = 0; i < strategies.length; i++) {
                    uint256 finalQueuedShares = tokenStakingNodeInstance.queuedShares(strategies[i]);
                    assertEq(finalQueuedShares, 0, "Queued shares should decrease to 0");
                }
            }

            {
                uint256 stakerStrategyListLength =
                    strategyManager.stakerStrategyListLength(address(tokenStakingNodeInstance));
                assertEq(
                    stakerStrategyListLength, initialStrategyListLength, "Staker strategy list length should be 0."
                );
                for (uint256 i = 0; i < strategies.length; i++) {
                    assertEq(
                        strategyManager.stakerDepositShares(address(tokenStakingNodeInstance), strategies[i]),
                        initialShares[i],
                        "Shares are not restaked correctly after undelegation"
                    );
                }
            }
        }

        vm.prank(actors.admin.STAKING_NODES_DELEGATOR);
        tokenStakingNodeInstance.delegate(operator2, signature, approverSalt);
        address delegatedAddress = eigenLayer.delegationManager.delegatedTo(address(tokenStakingNodeInstance));
        assertEq(
            delegatedAddress,
            operator2,
            "Delegation should be set to operator2 after undelegation and delegation again."
        );

        {
            uint256 stakerStrategyListLength =
                strategyManager.stakerStrategyListLength(address(tokenStakingNodeInstance));
            assertEq(stakerStrategyListLength, initialStrategyListLength, "Staker strategy list length should be 0.");
            for (uint256 i = 0; i < strategies.length; i++) {
                assertEq(
                    strategyManager.stakerDepositShares(address(tokenStakingNodeInstance), strategies[i]),
                    initialShares[i],
                    "Shares are not restaked correctly after undelegation"
                );
            }
        }
    }

    function testSetClaimerOnTokenStakingNode() public {
        // Create token staking node
        vm.prank(actors.ops.STAKING_NODE_CREATOR);
        ITokenStakingNode tokenStakingNodeInstance = tokenStakingNodesManager.createTokenStakingNode();

        // Create a claimer address
        address claimer = vm.addr(12_345);

        // Set claimer should fail from non-delegator
        vm.expectRevert(TokenStakingNode.NotTokenStakingNodeDelegator.selector);
        tokenStakingNodeInstance.setClaimer(claimer);

        // Set claimer from delegator
        vm.prank(actors.admin.STAKING_NODES_DELEGATOR);
        tokenStakingNodeInstance.setClaimer(claimer);

        // Verify claimer is set correctly in rewards coordinator
        IRewardsCoordinator rewardsCoordinator = tokenStakingNodesManager.rewardsCoordinator();
        assertEq(rewardsCoordinator.claimerFor(address(tokenStakingNodeInstance)), claimer, "Claimer not set correctly");
    }

}

contract TokenStakingNodeSlashing is ynEigenIntegrationBaseTest {
    TestAssetUtils private testAssetUtils;
    ITokenStakingNode private tokenStakingNode;
    address private avs;
    IStrategy private wstETHStrategy;

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

    function _waitForAllocationDelay() private {
        AllocationManagerStorage allocationManager = AllocationManagerStorage(address(eigenLayer.allocationManager));
        vm.roll(block.number + allocationManager.ALLOCATION_CONFIGURATION_DELAY() + 1);
    }

    function _waitForDeallocationDelay() private {
        AllocationManagerStorage allocationManager = AllocationManagerStorage(address(eigenLayer.allocationManager));
        vm.roll(block.number + allocationManager.DEALLOCATION_DELAY() + 1);
    }

    function _waitForWithdrawalDelay() private {
        vm.roll(block.number + eigenLayer.delegationManager.minWithdrawalDelayBlocks() + 1);
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

    function _slash() private {
        _slash(1 ether);
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

    function _getWithdrawableShares() private view returns (uint256, uint256) {
        IStrategy[] memory strategies = new IStrategy[](1);
        strategies[0] = wstETHStrategy;
        (uint256[] memory withdrawableShares, uint256[] memory depositShares) = eigenLayer.delegationManager.getWithdrawableShares(address(tokenStakingNode), strategies);
        return (withdrawableShares[0], depositShares[0]);
    }

    function _queueWithdrawal(uint256 depositShares) private returns (bytes32) {
        // TODO: Use TOKEN_STAKING_NODES_WITHDRAWER instead of STAKING_NODES_WITHDRAWER
        vm.prank(actors.ops.STAKING_NODES_WITHDRAWER);
        return tokenStakingNode.queueWithdrawals(wstETHStrategy, depositShares)[0];
    }

    function _queuedShares() private view returns (uint256) {
        return tokenStakingNode.queuedShares(wstETHStrategy);
    }

    function testQueuedSharesAreNotUpdatedIfSynchronizeIsNotCalled_FullSlashed() public {
        (uint256 withdrawableShares, uint256 depositShares) = _getWithdrawableShares();
        assertEq(withdrawableShares, depositShares);

        _queueWithdrawal(depositShares);

        assertEq(_queuedShares(), withdrawableShares, "Queued shares should be equal to withdrawable shares");

        _slash();

        assertEq(_queuedShares(), withdrawableShares, "Queued shares should be the same if it has not been synchronized after a slash");
    }

    function testQueuedSharesAreUpdatedAfterSynchronize_FullSlashed() public {
        (uint256 withdrawableShares, uint256 depositShares) = _getWithdrawableShares();
        assertEq(withdrawableShares, depositShares);

        _queueWithdrawal(depositShares);

        _slash();

        tokenStakingNode.synchronize();

        assertEq(_queuedShares(), 0, "After a complete slash, queued shares should be 0");
    }

    function testQueuedSharesAreDecreasedByHalf_HalfSlashed() public {
        (uint256 withdrawableShares, uint256 depositShares) = _getWithdrawableShares();
        assertEq(withdrawableShares, depositShares);

        _queueWithdrawal(depositShares);

        _slash(0.5 ether);

        tokenStakingNode.synchronize();

        assertEq(_queuedShares(), withdrawableShares / 2, "After half is slashed queued shares should be half of the previous withdrawable shares");
    }

    function testQueuedSharesAreDecreasedByHalf_FullSlashed_HalfAllocated() public {
        _allocate(0.5 ether);

        _waitForDeallocationDelay();

        (uint256 withdrawableShares, uint256 depositShares) = _getWithdrawableShares();
        assertEq(withdrawableShares, depositShares);

        _queueWithdrawal(depositShares);

        _slash();

        tokenStakingNode.synchronize();

        assertEq(_queuedShares(), withdrawableShares / 2, "After half is slashed queued shares should be half of the previous withdrawable shares");
    }

    function testQueuedSharesAreDecreasedToQuarter_HalfSlashed_HalfAllocated() public {
        _allocate(0.5 ether);

        _waitForDeallocationDelay();

        (uint256 withdrawableShares, uint256 depositShares) = _getWithdrawableShares();
        assertEq(withdrawableShares, depositShares);

        _queueWithdrawal(depositShares);

        _slash(0.5 ether);

        tokenStakingNode.synchronize();

        assertApproxEqAbs(_queuedShares(), withdrawableShares - withdrawableShares / 4, 1, "After half is slashed and half is allocated, queued shares should be a quarter of the previous withdrawable shares");
    }

    function testCompleteFailsIfNotSynchronized() public {
        (,uint256 depositShares) = _getWithdrawableShares();

        bytes32 queuedWithdrawalRoot = _queueWithdrawal(depositShares);

        (IDelegationManager.Withdrawal[] memory queuedWithdrawals,) = eigenLayer.delegationManager.getQueuedWithdrawals(address(tokenStakingNode));

        _slash();

        _waitForWithdrawalDelay();

        vm.expectRevert(abi.encodeWithSelector(TokenStakingNode.NotSyncedAfterSlashing.selector, queuedWithdrawalRoot, 1 ether, 0));
        vm.prank(actors.ops.STAKING_NODES_WITHDRAWER);
        tokenStakingNode.completeQueuedWithdrawals(queuedWithdrawals, false);
    }

    function testCompleteFailsOnFullSlash() public {
        (,uint256 depositShares) = _getWithdrawableShares();

        _queueWithdrawal(depositShares);

        (IDelegationManager.Withdrawal[] memory queuedWithdrawals,) = eigenLayer.delegationManager.getQueuedWithdrawals(address(tokenStakingNode));

        _slash();

        _waitForWithdrawalDelay();

        tokenStakingNode.synchronize();

        vm.expectRevert("wstETH: can't wrap zero stETH");
        vm.prank(actors.ops.STAKING_NODES_WITHDRAWER);
        tokenStakingNode.completeQueuedWithdrawals(queuedWithdrawals, false);
    }

    function testQueuedSharesStorageVariablesAreUpdatedOnSynchronize() public {
        (uint256 withdrawableShares, uint256 depositShares) = _getWithdrawableShares();

        bytes32 queuedWithdrawalRoot = _queueWithdrawal(depositShares);

        assertEq(tokenStakingNode.queuedShares(wstETHStrategy), withdrawableShares, "Queued shares should be equal to withdrawable shares");
        assertEq(tokenStakingNode.maxMagnitudeByWithdrawalRoot(queuedWithdrawalRoot), 1 ether, "Max magnitude should be WAD");
        assertEq(tokenStakingNode.withdrawableSharesByWithdrawalRoot(queuedWithdrawalRoot), withdrawableShares, "Queued withdrawable shares for withdrawalshould be equal to withdrawable shares");

        _slash(0.5 ether);

        tokenStakingNode.synchronize();

        assertEq(tokenStakingNode.queuedShares(wstETHStrategy), withdrawableShares / 2, "Queued shares should be half of the previous withdrawable shares");
        assertEq(tokenStakingNode.maxMagnitudeByWithdrawalRoot(queuedWithdrawalRoot), 0.5 ether, "Max magnitude should be half of the previous withdrawable shares");
        assertEq(tokenStakingNode.withdrawableSharesByWithdrawalRoot(queuedWithdrawalRoot), withdrawableShares / 2, "Queued withdrawable shares for withdrawalshould be equal to half of the previous withdrawable shares");
    }

    function testSyncWithMultipleQueuedWithdrawals() public {
        (uint256 withdrawableShares, uint256 depositShares) = _getWithdrawableShares();

        uint256 thirdOfDepositShares = depositShares / 3;

        bytes32 queuedWithdrawalRoot1 = _queueWithdrawal(thirdOfDepositShares);
        bytes32 queuedWithdrawalRoot2 = _queueWithdrawal(thirdOfDepositShares);
        bytes32 queuedWithdrawalRoot3 = _queueWithdrawal(thirdOfDepositShares);

        assertApproxEqAbs(tokenStakingNode.queuedShares(wstETHStrategy), withdrawableShares, 2, "Queued shares should be equal to withdrawable shares");

        assertEq(tokenStakingNode.maxMagnitudeByWithdrawalRoot(queuedWithdrawalRoot1), 1 ether, "Max magnitude for withdrawal 1 should be WAD");
        assertEq(tokenStakingNode.maxMagnitudeByWithdrawalRoot(queuedWithdrawalRoot2), 1 ether, "Max magnitude for withdrawal 2 should be WAD");
        assertEq(tokenStakingNode.maxMagnitudeByWithdrawalRoot(queuedWithdrawalRoot3), 1 ether, "Max magnitude for withdrawal 3 should be WAD");

        assertEq(tokenStakingNode.withdrawableSharesByWithdrawalRoot(queuedWithdrawalRoot1), withdrawableShares / 3, "Queued withdrawable for withdrawal 1 should be equal to withdrawable shares / 3");
        assertEq(tokenStakingNode.withdrawableSharesByWithdrawalRoot(queuedWithdrawalRoot2), withdrawableShares / 3, "Queued withdrawable for withdrawal 2 should be equal to withdrawable shares / 3");
        assertEq(tokenStakingNode.withdrawableSharesByWithdrawalRoot(queuedWithdrawalRoot3), withdrawableShares / 3, "Queued withdrawable for withdrawal 3 should be equal to withdrawable shares / 3");

        _slash(0.5 ether);

        tokenStakingNode.synchronize();

        assertApproxEqAbs(tokenStakingNode.queuedShares(wstETHStrategy), withdrawableShares / 2, 2, "Queued shares should be half of the previous withdrawable shares");

        assertEq(tokenStakingNode.maxMagnitudeByWithdrawalRoot(queuedWithdrawalRoot1), 0.5 ether, "Max magnitude for withdrawal 1 should be half of the previous withdrawable shares");
        assertEq(tokenStakingNode.maxMagnitudeByWithdrawalRoot(queuedWithdrawalRoot2), 0.5 ether, "Max magnitude for withdrawal 2 should be half of the previous withdrawable shares");
        assertEq(tokenStakingNode.maxMagnitudeByWithdrawalRoot(queuedWithdrawalRoot3), 0.5 ether, "Max magnitude for withdrawal 3 should be half of the previous withdrawable shares");

        assertEq(tokenStakingNode.withdrawableSharesByWithdrawalRoot(queuedWithdrawalRoot1), withdrawableShares / 2 / 3, "Queued withdrawable for withdrawal 1 should be equal to withdrawable shares / 2 / 3");
        assertEq(tokenStakingNode.withdrawableSharesByWithdrawalRoot(queuedWithdrawalRoot2), withdrawableShares / 2 / 3, "Queued withdrawable for withdrawal 2 should be equal to withdrawable shares / 2 / 3");
        assertEq(tokenStakingNode.withdrawableSharesByWithdrawalRoot(queuedWithdrawalRoot3), withdrawableShares / 2 / 3, "Queued withdrawable for withdrawal 3 should be equal to withdrawable shares / 2 / 3");
    }

    function testSyncWithMultipleQueuedWithdrawals_NoSlashing() public {
        (uint256 withdrawableShares, uint256 depositShares) = _getWithdrawableShares();

        uint256 thirdOfDepositShares = depositShares / 3;

        bytes32 queuedWithdrawalRoot1 = _queueWithdrawal(thirdOfDepositShares);
        bytes32 queuedWithdrawalRoot2 = _queueWithdrawal(thirdOfDepositShares);
        bytes32 queuedWithdrawalRoot3 = _queueWithdrawal(thirdOfDepositShares);

        assertApproxEqAbs(tokenStakingNode.queuedShares(wstETHStrategy), withdrawableShares, 2, "Queued shares should be equal to withdrawable shares");

        assertEq(tokenStakingNode.maxMagnitudeByWithdrawalRoot(queuedWithdrawalRoot1), 1 ether, "Max magnitude for withdrawal 1 should be WAD");
        assertEq(tokenStakingNode.maxMagnitudeByWithdrawalRoot(queuedWithdrawalRoot2), 1 ether, "Max magnitude for withdrawal 2 should be WAD");
        assertEq(tokenStakingNode.maxMagnitudeByWithdrawalRoot(queuedWithdrawalRoot3), 1 ether, "Max magnitude for withdrawal 3 should be WAD");

        assertEq(tokenStakingNode.withdrawableSharesByWithdrawalRoot(queuedWithdrawalRoot1), withdrawableShares / 3, "Queued withdrawable for withdrawal 1 should be equal to withdrawable shares / 3");
        assertEq(tokenStakingNode.withdrawableSharesByWithdrawalRoot(queuedWithdrawalRoot2), withdrawableShares / 3, "Queued withdrawable for withdrawal 2 should be equal to withdrawable shares / 3");
        assertEq(tokenStakingNode.withdrawableSharesByWithdrawalRoot(queuedWithdrawalRoot3), withdrawableShares / 3, "Queued withdrawable for withdrawal 3 should be equal to withdrawable shares / 3");

        tokenStakingNode.synchronize();

        assertApproxEqAbs(tokenStakingNode.queuedShares(wstETHStrategy), withdrawableShares, 2, "Queued shares should be equal to withdrawable shares");

        assertEq(tokenStakingNode.maxMagnitudeByWithdrawalRoot(queuedWithdrawalRoot1), 1 ether, "Max magnitude for withdrawal 1 should be WAD");
        assertEq(tokenStakingNode.maxMagnitudeByWithdrawalRoot(queuedWithdrawalRoot2), 1 ether, "Max magnitude for withdrawal 2 should be WAD");
        assertEq(tokenStakingNode.maxMagnitudeByWithdrawalRoot(queuedWithdrawalRoot3), 1 ether, "Max magnitude for withdrawal 3 should be WAD");

        assertEq(tokenStakingNode.withdrawableSharesByWithdrawalRoot(queuedWithdrawalRoot1), withdrawableShares / 3, "Queued withdrawable for withdrawal 1 should be equal to withdrawable shares / 3");
        assertEq(tokenStakingNode.withdrawableSharesByWithdrawalRoot(queuedWithdrawalRoot2), withdrawableShares / 3, "Queued withdrawable for withdrawal 2 should be equal to withdrawable shares / 3");
        assertEq(tokenStakingNode.withdrawableSharesByWithdrawalRoot(queuedWithdrawalRoot3), withdrawableShares / 3, "Queued withdrawable for withdrawal 3 should be equal to withdrawable shares / 3");
    }

    function testQueuedSharesSyncedEventIsEmittedOnSynchronize() public {
        vm.expectEmit();
        emit QueuedSharesSynced();
        tokenStakingNode.synchronize();
    }

    function testQueuedSharesStorageVariablesResetOnComplete() public {
        (,uint256 depositShares) = _getWithdrawableShares();

        bytes32 queuedWithdrawalRoot = _queueWithdrawal(depositShares);

        (IDelegationManager.Withdrawal[] memory queuedWithdrawals,) = eigenLayer.delegationManager.getQueuedWithdrawals(address(tokenStakingNode));

        _slash(0.5 ether);

        _waitForWithdrawalDelay();

        tokenStakingNode.synchronize();

        vm.prank(actors.ops.STAKING_NODES_WITHDRAWER);
        tokenStakingNode.completeQueuedWithdrawals(queuedWithdrawals, false);

        assertEq(tokenStakingNode.queuedShares(wstETHStrategy), 0, "Queued shares should be 0");
        assertEq(tokenStakingNode.maxMagnitudeByWithdrawalRoot(queuedWithdrawalRoot), 0, "Max magnitude should be 0");
        assertEq(tokenStakingNode.withdrawableSharesByWithdrawalRoot(queuedWithdrawalRoot), 0, "Queued withdrawable shares should be 0");
    }

    function testQueueAndCompleteWhenUndelegated() public {
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
        
        (uint256 withdrawableShares, uint256 depositShares) = _getWithdrawableShares();

        bytes32 queuedWithdrawalRoot = _queueWithdrawal(depositShares);

        assertEq(tokenStakingNode.queuedShares(wstETHStrategy), withdrawableShares, "Queued shares should be equal to withdrawable shares");
        assertEq(tokenStakingNode.withdrawableSharesByWithdrawalRoot(queuedWithdrawalRoot), withdrawableShares, "Withdrawable shares should be equal to withdrawable shares");
        assertEq(tokenStakingNode.maxMagnitudeByWithdrawalRoot(queuedWithdrawalRoot), 1 ether, "Max magnitude should be WAD");

        _waitForWithdrawalDelay();

        (IDelegationManager.Withdrawal[] memory queuedWithdrawals,) = eigenLayer.delegationManager.getQueuedWithdrawals(address(tokenStakingNode));

        vm.prank(actors.ops.STAKING_NODES_WITHDRAWER);
        tokenStakingNode.completeQueuedWithdrawals(queuedWithdrawals, false);
        
        assertEq(tokenStakingNode.queuedShares(wstETHStrategy), 0, "Queued shares should be 0");
        assertEq(tokenStakingNode.withdrawableSharesByWithdrawalRoot(queuedWithdrawalRoot), 0, "Withdrawable shares should be 0");
        assertEq(tokenStakingNode.maxMagnitudeByWithdrawalRoot(queuedWithdrawalRoot), 0, "Max magnitude should be 0");
    }

    function testInitializeV3AssignsQueuedSharesToLegacyQueuedShares() public {
        IERC20[] memory assets = assetRegistry.getAssets();

        assertGt(assets.length, 0, "There should be at least 1 asset");

        ITokenStakingNode node = ITokenStakingNode(address(new ERC1967Proxy(address(new TokenStakingNode()), "")));

        ITokenStakingNode.Init memory init = ITokenStakingNode.Init({
            tokenStakingNodesManager: tokenStakingNodesManager,
            nodeId: 1337
        });

        node.initialize(init);

        node.initializeV2();

        for (uint256 i = 0; i < assets.length; i++) {
            IStrategy strategy = eigenStrategyManager.strategies(assets[i]);

            vm.store(
                address(node),
                keccak256(abi.encode(strategy, uint256(2))),
                bytes32(100 ether * i)
            );
        }

        node.initializeV3();

        for (uint256 i = 0; i < assets.length; i++) {
            IStrategy strategy = eigenStrategyManager.strategies(assets[i]);

            assertEq(node.queuedShares(strategy), 0, "Queued shares should be 0");
            assertEq(node.legacyQueuedShares(strategy), 100 ether * i, "Legacy queued shares should be equal to the initial amount");
        }
    }
}
