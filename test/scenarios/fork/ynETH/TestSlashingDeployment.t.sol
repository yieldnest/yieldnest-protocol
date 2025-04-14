// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {StakingNodesManager} from "src/StakingNodesManager.sol";
import {StakingNode} from "src/StakingNode.sol";
import {WithdrawalsProcessor} from "src/WithdrawalsProcessor.sol";
import {IStakingNode} from "src/interfaces/IStakingNode.sol";
import {IStakingNodesManager} from "src/interfaces/IStakingNodesManager.sol";
import {IStrategy} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {ProxyAdmin} from "lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {
    TransparentUpgradeableProxy,
    ITransparentUpgradeableProxy
} from "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IDelegationManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {DelegationManager} from "lib/eigenlayer-contracts/src/contracts/core/DelegationManager.sol";
import {AllocationManager} from "lib/eigenlayer-contracts/src/contracts/core/AllocationManager.sol";
import {EigenPodManager} from "lib/eigenlayer-contracts/src/contracts/pods/EigenPodManager.sol";
import {IPauserRegistry} from "lib/eigenlayer-contracts/src/contracts/interfaces/IPauserRegistry.sol";
import {IBeacon} from "lib/eigenlayer-contracts/lib/openzeppelin-contracts-v4.9.0/contracts/proxy/beacon/IBeacon.sol";
import {IPermissionController} from "lib/eigenlayer-contracts/src/contracts/interfaces/IPermissionController.sol";
import {IETHPOSDeposit} from "lib/eigenlayer-contracts/src/contracts/interfaces/IETHPOSDeposit.sol";
import {IStrategyManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IEigenPodManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IEigenPodManager.sol";
import {IAllocationManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {IWithdrawalQueueManager} from "src/interfaces/IWithdrawalQueueManager.sol";
import {Base} from "./Base.t.sol";

interface IOldEigenPodManager {

    function podOwnerShares(
        address
    ) external view returns (int256);

}

// Holesky slashing deployment test
contract SlashingDeploymentTest is Base {

    struct YnETHStateSnapshot {
        uint256 totalAssets;
        uint256 totalSupply;
        uint256 totalStakingNodes;
        uint256 totalDepositedInPool;
        uint256 rate;
    }

    struct StakingNodeStateSnapshot {
        uint256 withdrawnETH;
        uint256 unverifiedStakedETH;
        uint256 queuedSharesAmount;
        uint256 preELIP002QueuedSharesAmount;
        int256 podOwnerDepositShares;
        address delegatedTo;
        uint256 ethBalance;
    }

    modifier skipOnHolesky() {
        vm.skip(_isHolesky(), "Impossible to test on Holesky");
        _;
    }
    
     function _isHolesky() internal view returns (bool) {
        return block.chainid == chainIds.holeksy;
    }

    address public user = makeAddr("user");
    IPauserRegistry public pauserRegistry = IPauserRegistry(0x0c431C66F4dE941d089625E5B423D00707977060);
    IStrategyManager public strategyManager = IStrategyManager(0x858646372CC42E1A627fcE94aa7A7033e7CF075A);
    IETHPOSDeposit public ethposDeposit = IETHPOSDeposit(0x00000000219ab540356cBB839Cbe05303d7705Fa);
    IBeacon public eigenPodBeacon = IBeacon(0x5a2a4F2F3C18f09179B6703e63D9eDD165909073);
    string public version = "v1.3.0";

    function setUp() public override {
        super.assignContracts();
        deal(address(user), 100 ether);
    }

    function test_depositAndRequestAndClaimWithdrawalAfterELSlashingDeploymentAndBeforeUpgradeOfYnETH() public skipOnHolesky {

        vm.startPrank(user);

        // reverts because podOwnerShares function is not available due to eigenlayer contracts upgrade
        vm.expectRevert();
        stakingNodesManager.updateTotalETHStaked();

        YnETHStateSnapshot memory ynethStateSnapshotBefore = takeYnETHStateSnapshot();
        StakingNodeStateSnapshot[] memory stakingNodesStateSnapshotBefore = takeStakingNodesStateSnapshot();

        uint256 depositAmount = 1 ether;
        uint256 sharesBefore = yneth.balanceOf(user);
        yneth.depositETH{value: depositAmount}(user);
        uint256 sharesReceived = yneth.balanceOf(user) - sharesBefore;

        YnETHStateSnapshot memory ynethStateSnapshotAfter = takeYnETHStateSnapshot();
        StakingNodeStateSnapshot[] memory stakingNodesStateSnapshotAfter = takeStakingNodesStateSnapshot();

        assertEq(
            ynethStateSnapshotAfter.totalAssets,
            ynethStateSnapshotBefore.totalAssets + depositAmount,
            "totalAssets not changed correctly"
        );
        assertEq(
            ynethStateSnapshotAfter.totalSupply,
            ynethStateSnapshotBefore.totalSupply + sharesReceived,
            "totalSupply not changed correctly"
        );
        assertEq(
            ynethStateSnapshotAfter.totalStakingNodes,
            ynethStateSnapshotBefore.totalStakingNodes,
            "totalStakingNodes changed"
        );
        assertEq(
            ynethStateSnapshotAfter.totalDepositedInPool,
            ynethStateSnapshotBefore.totalDepositedInPool + depositAmount,
            "totalDepositedInPool not changed correctly"
        );
        assertEq(ynethStateSnapshotAfter.rate, ynethStateSnapshotBefore.rate, "rate changed");

        for (uint256 i = 0; i < stakingNodesStateSnapshotBefore.length; i++) {
            assertEq(
                stakingNodesStateSnapshotBefore[i].withdrawnETH,
                stakingNodesStateSnapshotAfter[i].withdrawnETH,
                "withdrawnETH changed for staking node "
            );
            assertEq(
                stakingNodesStateSnapshotBefore[i].unverifiedStakedETH,
                stakingNodesStateSnapshotAfter[i].unverifiedStakedETH,
                "unverifiedStakedETH changed for staking node "
            );
            assertEq(
                stakingNodesStateSnapshotBefore[i].queuedSharesAmount,
                stakingNodesStateSnapshotAfter[i].queuedSharesAmount,
                "queuedSharesAmount wrong for staking node "
            );
            assertEq(
                stakingNodesStateSnapshotBefore[i].preELIP002QueuedSharesAmount,
                stakingNodesStateSnapshotAfter[i].preELIP002QueuedSharesAmount,
                "queuedSharesAmount not changed to preELIP002QueuedSharesAmount for staking node "
            );
            assertEq(
                stakingNodesStateSnapshotBefore[i].podOwnerDepositShares,
                stakingNodesStateSnapshotAfter[i].podOwnerDepositShares,
                "podOwnerDepositShares wrong for staking node after upgrade"
            );
            assertEq(
                stakingNodesStateSnapshotBefore[i].delegatedTo,
                stakingNodesStateSnapshotAfter[i].delegatedTo,
                "delegatedTo wrong for staking node "
            );
            assertEq(
                stakingNodesStateSnapshotBefore[i].ethBalance,
                stakingNodesStateSnapshotAfter[i].ethBalance,
                "ethBalance wrong for staking node "
            );
            assertEq(stakingNodesStateSnapshotBefore[i].ethBalance, 0, "ethBalance not reverted for staking node");
        }

        uint256 userYnethBalanceBefore = yneth.balanceOf(user);
        yneth.approve(address(ynETHWithdrawalQueueManager), userYnethBalanceBefore);
        uint256 tokenId = ynETHWithdrawalQueueManager.requestWithdrawal(userYnethBalanceBefore);

        assertEq(yneth.balanceOf(user), 0, "user yneth balance not changed correctly");
        vm.stopPrank();

        vm.prank(actors.ops.REQUEST_FINALIZER);
        uint256 finalizationId = ynETHWithdrawalQueueManager.finalizeRequestsUpToIndex(tokenId + 1);


        IWithdrawalQueueManager.WithdrawalClaim[] memory claims = new IWithdrawalQueueManager.WithdrawalClaim[](1);
        claims[0] = IWithdrawalQueueManager.WithdrawalClaim({
            tokenId: tokenId,
            finalizationId: finalizationId,
            receiver: user
        });

        vm.startPrank(user);
        ynETHWithdrawalQueueManager.claimWithdrawals(claims);

        IWithdrawalQueueManager.WithdrawalRequest memory _withdrawalRequest = ynETHWithdrawalQueueManager.withdrawalRequest(tokenId);
        assertEq(_withdrawalRequest.processed, true, "withdrawal not processed");

        vm.expectRevert();
        stakingNodesManager.updateTotalETHStaked();
    }

    function test_depositAfterSlashingDeploymentByELAfterUpgradeOfYnETH() public skipOnHolesky {

        YnETHStateSnapshot memory ynethStateSnapshotBefore = takeYnETHStateSnapshot();
        StakingNodeStateSnapshot[] memory stakingNodesStateSnapshotBefore = takeStakingNodesStateSnapshot();

        upgradeStakingNodesManagerAndStakingNode();
        
        vm.startPrank(user);

        uint256 depositAmount = 10 ether;
        uint256 sharesBefore = yneth.balanceOf(address(this));
        yneth.depositETH{value: depositAmount}(address(this));
        uint256 sharesReceived = yneth.balanceOf(address(this)) - sharesBefore;


        YnETHStateSnapshot memory ynethStateSnapshotAfter = takeYnETHStateSnapshot();
        StakingNodeStateSnapshot[] memory stakingNodesStateSnapshotAfter = takeStakingNodesStateSnapshot();

        assertEq(
            ynethStateSnapshotAfter.totalAssets,
            ynethStateSnapshotBefore.totalAssets + depositAmount,
            "totalAssets not changed correctly"
        );
        assertEq(
            ynethStateSnapshotAfter.totalSupply,
            ynethStateSnapshotBefore.totalSupply + sharesReceived,
            "totalSupply not changed correctly"
        );
        assertEq(
            ynethStateSnapshotAfter.totalStakingNodes,
            ynethStateSnapshotBefore.totalStakingNodes,
            "totalStakingNodes changed"
        );
        assertEq(
            ynethStateSnapshotAfter.totalDepositedInPool,
            ynethStateSnapshotBefore.totalDepositedInPool + depositAmount,
            "totalDepositedInPool not changed correctly"
        );
        assertEq(ynethStateSnapshotAfter.rate, ynethStateSnapshotBefore.rate, "rate changed");

        for (uint256 i = 0; i < stakingNodesStateSnapshotBefore.length; i++) {
            assertEq(
                stakingNodesStateSnapshotBefore[i].withdrawnETH,
                stakingNodesStateSnapshotAfter[i].withdrawnETH,
                "withdrawnETH changed for staking node "
            );
            assertEq(
                stakingNodesStateSnapshotBefore[i].unverifiedStakedETH,
                stakingNodesStateSnapshotAfter[i].unverifiedStakedETH,
                "unverifiedStakedETH changed for staking node "
            );
            assertEq(
                stakingNodesStateSnapshotBefore[i].queuedSharesAmount,
                stakingNodesStateSnapshotAfter[i].preELIP002QueuedSharesAmount,
                "queuedSharesAmount not changed to preELIP002QueuedSharesAmount for staking node "
            );
            assertEq(
                stakingNodesStateSnapshotAfter[i].queuedSharesAmount,
                0,
                "queuedSharesAmount not changed to 0 for staking node "
            );
            assertEq(
                stakingNodesStateSnapshotBefore[i].podOwnerDepositShares,
                stakingNodesStateSnapshotAfter[i].podOwnerDepositShares,
                "podOwnerDepositShares wrong for staking node after upgrade"
            );
            assertEq(
                stakingNodesStateSnapshotBefore[i].delegatedTo,
                stakingNodesStateSnapshotAfter[i].delegatedTo,
                "delegatedTo wrong for staking node "
            );
             assertEq(stakingNodesStateSnapshotBefore[i].ethBalance, 0, "ethBalance didn't revert for staking node");
            assertGt(stakingNodesStateSnapshotAfter[i].ethBalance, 0, "ethBalance not reported correctly for staking node after upgrade");
        }
    }

    function upgradeEigenlayerContracts() internal {
        address oldEigenPodManagerImpl = getImplementationAddressOfTransparentUpgradeableProxy(address(eigenPodManager));
        address oldDelegationManagerImpl =
            getImplementationAddressOfTransparentUpgradeableProxy(address(delegationManager));

        address allocationManagerImpl = address(
            new AllocationManager(
                delegationManager,
                pauserRegistry,
                IPermissionController(address(0)),
                15 days,
                15 days,
                version
            )
        );

        TransparentUpgradeableProxy allocationManagerProxy = new TransparentUpgradeableProxy(
            allocationManagerImpl,
            address(this),
            abi.encodeWithSelector(AllocationManager.initialize.selector, address(this), false)
        );

        DelegationManager newDelegationManagerImpl = new DelegationManager(
            strategyManager,
            eigenPodManager,
            IAllocationManager(address(allocationManagerProxy)),
            pauserRegistry,
            IPermissionController(address(0)),
            14 days,
            version
        );

        EigenPodManager newEigenPodManagerImpl = new EigenPodManager(
            ethposDeposit,
            eigenPodBeacon,
            delegationManager,
            pauserRegistry,
            version
        );

        vm.etch(oldDelegationManagerImpl, address(newDelegationManagerImpl).code);
        vm.etch(oldEigenPodManagerImpl, address(newEigenPodManagerImpl).code);
    }

    function getImplementationAddressOfTransparentUpgradeableProxy(
        address proxy
    ) internal view returns (address) {
        bytes32 IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        return address(uint160(uint256(vm.load(proxy, IMPLEMENTATION_SLOT))));
    }

    function upgradeStakingNodesManagerAndStakingNode() internal override {
        address newStakingNodesManagerImpl = address(new StakingNodesManager());

        vm.prank(actors.admin.PROXY_ADMIN_OWNER);
        ProxyAdmin(getTransparentUpgradeableProxyAdminAddress(address(stakingNodesManager))).upgradeAndCall(
            ITransparentUpgradeableProxy(address(stakingNodesManager)), newStakingNodesManagerImpl, ""
        );

        // Upgrade StakingNode implementation
        address newStakingNodeImpl = address(new StakingNode());

        // Register new implementation
        vm.prank(actors.admin.STAKING_ADMIN);
        stakingNodesManager.upgradeStakingNodeImplementation(newStakingNodeImpl);
    }

    function takeYnETHStateSnapshot() internal view returns (YnETHStateSnapshot memory) {
        uint256 rate;
        try yneth.convertToAssets(1 ether) returns (uint256 _rate) {
            rate = _rate;
        } catch {
            rate = 0;
        }

        return YnETHStateSnapshot({
            totalAssets: yneth.totalAssets(),
            totalSupply: yneth.totalSupply(),
            totalStakingNodes: stakingNodesManager.nodesLength(),
            totalDepositedInPool: yneth.totalDepositedInPool(),
            rate: rate
        });
    }

    function takeStakingNodesStateSnapshot() internal view returns (StakingNodeStateSnapshot[] memory) {
        uint256 nodeCount = stakingNodesManager.nodesLength();
        StakingNodeStateSnapshot[] memory stakingNodeStateSnapshot = new StakingNodeStateSnapshot[](nodeCount);
        for (uint256 i = 0; i < nodeCount; i++) {
            uint256 preELIP002QueuedSharesAmount;
            int256 podOwnerDepositShares;
            address delegatedTo;
            uint256 ethBalance;

            // wrapping in try catch because preELIP002QueuedSharesAmount function won't be available before the upgrade
            try stakingNodesManager.nodes(i).preELIP002QueuedSharesAmount() returns (uint256 _preELIP002QueuedSharesAmount) {
                preELIP002QueuedSharesAmount = _preELIP002QueuedSharesAmount;
            } catch {
                preELIP002QueuedSharesAmount = 0;
            }

            try eigenPodManager.podOwnerDepositShares(address(stakingNodesManager.nodes(i))) returns (
                int256 _podOwnerDepositShares
            ) {
                podOwnerDepositShares = _podOwnerDepositShares;
            } catch {
                podOwnerDepositShares =
                    IOldEigenPodManager(address(eigenPodManager)).podOwnerShares(address(stakingNodesManager.nodes(i)));
            }

            try stakingNodesManager.nodes(i).getETHBalance() returns (uint256 _ethBalance) {
                ethBalance = _ethBalance;
            } catch {
                ethBalance = 0;
            }

            stakingNodeStateSnapshot[i] = StakingNodeStateSnapshot({
                withdrawnETH: stakingNodesManager.nodes(i).getWithdrawnETH(),
                unverifiedStakedETH: stakingNodesManager.nodes(i).unverifiedStakedETH(),
                queuedSharesAmount: stakingNodesManager.nodes(i).getQueuedSharesAmount(),
                preELIP002QueuedSharesAmount: preELIP002QueuedSharesAmount,
                podOwnerDepositShares: podOwnerDepositShares,
                delegatedTo: delegatedTo,
                ethBalance: ethBalance
            });
        }
        return stakingNodeStateSnapshot;
    }

}
