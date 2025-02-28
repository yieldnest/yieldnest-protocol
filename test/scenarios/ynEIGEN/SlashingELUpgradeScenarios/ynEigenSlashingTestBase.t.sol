// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {TokenStakingNodesManager} from "src/ynEIGEN/TokenStakingNodesManager.sol";
import {TokenStakingNode} from "src/ynEIGEN/TokenStakingNode.sol";
import {EigenStrategyManager} from "src/ynEIGEN/EigenStrategyManager.sol";
import {WithdrawalsProcessor} from "src/ynEIGEN/WithdrawalsProcessor.sol";
import {ITokenStakingNode} from "src/interfaces/ITokenStakingNode.sol";
import {ITokenStakingNodesManager} from "src/interfaces/ITokenStakingNodesManager.sol";
import {IynEigen} from "src/interfaces/IynEigen.sol";
import {IETHPOSDeposit} from "lib/eigenlayer-contracts/src/contracts/interfaces/IETHPOSDeposit.sol";
import {IBeacon} from "lib/eigenlayer-contracts/lib/openzeppelin-contracts-v4.9.0/contracts/proxy/beacon/IBeacon.sol";
import {IAssetRegistry} from "src/interfaces/IAssetRegistry.sol";
import {IEigenPodManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IEigenPodManager.sol";
import {ProxyAdmin} from "lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {
    TransparentUpgradeableProxy,
    ITransparentUpgradeableProxy
} from "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {StorageSlot} from "lib/openzeppelin-contracts/contracts/utils/StorageSlot.sol";
import {IDelegationManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {DelegationManager} from "lib/eigenlayer-contracts/src/contracts/core/DelegationManager.sol";
import {AllocationManager} from "lib/eigenlayer-contracts/src/contracts/core/AllocationManager.sol";
import {IAllocationManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {UpgradeableBeacon} from "lib/openzeppelin-contracts/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {IPauserRegistry} from "lib/eigenlayer-contracts/src/contracts/interfaces/IPauserRegistry.sol";
import {IPermissionController} from "lib/eigenlayer-contracts/src/contracts/interfaces/IPermissionController.sol";
import {IStrategyManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {BeaconChainMock, BeaconChainProofs, CheckpointProofs, CredentialProofs, EigenPodManager} from "lib/eigenlayer-contracts/src/test/integration/mocks/BeaconChainMock.t.sol";
import {IStrategy} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {Base} from "./../Base.t.sol";

/**
 * @title ynEigenSlashingTestBase
 * @notice Base contract containing common functionality for all slashing upgrade tests
 */

contract ynEigenSlashingTestBase is Base {

    /**
     * @dev Struct to capture the state of the ynEigen system at a point in time
     */
    struct YnEigenStateSnapshot {
        uint256 totalAssets;
        uint256 totalSupply;
        uint256 totalStakingNodes;
        uint256 rate;
    }

    /**
     * @dev Struct to capture the state of a TokenStakingNode at a point in time
     * Removed the mapping to make it compatible with memory arrays
     */
    struct TokenStakingNodeStateSnapshot {
        uint256 queuedShares;
        uint256 legacyQueuedShares;
        address delegatedTo;
        uint256 totalWithdrawnBalance;
        bool isSynchronized;
    }
    
    // Separate mapping to track withdrawn balances per node and asset
    mapping(address => mapping(address => uint256)) public nodeAssetWithdrawnBalances;

    // Contracts
    IynEigen public ynEigen;
    ITokenStakingNodesManager public tokenStakingNodesManager;
    EigenStrategyManager public eigenStrategyManager;
    // IDelegationManager public delegationManager;
    IAllocationManager public allocationManager;
    IStrategyManager public strategyManager;
    IPauserRegistry public pauserRegistry;
    IERC20 public wstETH;
    IAssetRegistry public assetRegistry;
    
    // Test actors
    address public admin;
    address public user;
    address public proxyAdminOwner;
    address public strategyAdmin;
    
    IETHPOSDeposit public ethposDeposit;
    IBeacon public eigenPodBeacon;

    // Test state
    uint256 public initialWstETHBalance = 100 ether;
    
    // Implementations for upgrade
    address public newTokenStakingNodeImpl;
    address public newEigenStrategyManagerImpl;
    address public newTokenStakingNodesManagerImpl;
    
    // Storage slots
    bytes32 internal constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    bytes32 internal constant ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    /**
     * @dev Sets up the test environment with necessary contracts and initial state
     */
    function setUp() public virtual {
        admin = makeAddr("admin");
        user = makeAddr("user");
        proxyAdminOwner = makeAddr("proxyAdminOwner");
        strategyAdmin = makeAddr("strategyAdmin");
        
        connectToContracts();
        
        // Fund test user with wstETH
        vm.startPrank(admin);
        wstETH.transfer(user, initialWstETHBalance);
        vm.stopPrank();
        
        // Prepare upgrade implementations
        prepareUpgradeImplementations();
    }
    
    /**
     * @dev Connect to the required contracts
     */
    function connectToContracts() internal virtual {
        pauserRegistry = IPauserRegistry(0x0c431C66F4dE941d089625E5B423D00707977060);
        strategyManager = IStrategyManager(0x858646372CC42E1A627fcE94aa7A7033e7CF075A);

   
        ethposDeposit = IETHPOSDeposit(0x00000000219ab540356cBB839Cbe05303d7705Fa);
        eigenPodBeacon = IBeacon(0x5a2a4F2F3C18f09179B6703e63D9eDD165909073);
        
        // TODO Relace with real or mock
        ynEigen = IynEigen(makeAddr("ynEigen"));
        tokenStakingNodesManager = ITokenStakingNodesManager(makeAddr("tokenStakingNodesManager"));
        eigenStrategyManager = EigenStrategyManager(makeAddr("eigenStrategyManager"));
        delegationManager = IDelegationManager(makeAddr("delegationManager"));
        allocationManager = IAllocationManager(makeAddr("allocationManager"));
        wstETH = IERC20(makeAddr("wstETH"));
        assetRegistry = IAssetRegistry(makeAddr("assetRegistry"));
    }
    
    /**
     * @dev Prepare new implementation contracts for upgrades
     */
    function prepareUpgradeImplementations() internal virtual {
        newTokenStakingNodeImpl = address(new TokenStakingNode());
        newEigenStrategyManagerImpl = address(new EigenStrategyManager());
        newTokenStakingNodesManagerImpl = address(new TokenStakingNodesManager());
    }

    //--------------------------------------------------------------------------
    // State Capture Functions
    //--------------------------------------------------------------------------
    
    /**
     * @dev Captures the current state of the ynEigen system
     */
    function takeYnEigenStateSnapshot() internal view returns (YnEigenStateSnapshot memory) {
        uint256 rate;
        try ynEigen.previewRedeem(1 ether) returns (uint256 _rate) {
            rate = _rate;
        } catch {
            rate = 0;
        }

        return YnEigenStateSnapshot({
            totalAssets: ynEigen.totalAssets(),
            totalSupply: ynEigen.totalSupply(),
            totalStakingNodes: tokenStakingNodesManager.nodesLength(),
            rate: rate
        });
    }
    
    /**
     * @dev Captures the current state of all TokenStakingNodes
     */
    function takeTokenStakingNodesStateSnapshot() internal returns (TokenStakingNodeStateSnapshot[] memory) {
        uint256 nodeCount = tokenStakingNodesManager.nodesLength();
        TokenStakingNodeStateSnapshot[] memory snapshots = new TokenStakingNodeStateSnapshot[](nodeCount);
        ITokenStakingNode[] memory nodes = tokenStakingNodesManager.getAllNodes();
        
        for (uint256 i = 0; i < nodeCount; i++) {
            ITokenStakingNode node = nodes[i];
            address nodeAddress = address(node);
            
            uint256 legacyQueuedShares;
            uint256 queuedShares;
            bool isSynchronized;
            address delegatedTo;
            
            // Try-catch for compatibility across versions
            try node.legacyQueuedShares(getDefaultStrategy()) returns (uint256 _legacyQueuedShares) {
                legacyQueuedShares = _legacyQueuedShares;
            } catch {
                legacyQueuedShares = 0;
            }
            
            try node.queuedShares(getDefaultStrategy()) returns (uint256 _queuedShares) {
                queuedShares = _queuedShares;
            } catch {
                queuedShares = 0;
            }
            
            try node.isSynchronized() returns (bool _isSynchronized) {
                isSynchronized = _isSynchronized;
            } catch {
                isSynchronized = false;
            }
            
            try node.delegatedTo() returns (address _delegatedTo) {
                delegatedTo = _delegatedTo;
            } catch {
                delegatedTo = address(0);
            }
            
            // Create the snapshot without mapping
            snapshots[i] = TokenStakingNodeStateSnapshot({
                queuedShares: queuedShares,
                legacyQueuedShares: legacyQueuedShares,
                delegatedTo: delegatedTo,
                isSynchronized: isSynchronized,
                totalWithdrawnBalance: 0  // Will accumulate below
            });
            
            // Get withdrawn balances for key assets and store in the contract's mapping
            IERC20[] memory trackedAssets = getTrackedAssets();
            uint256 totalWithdrawnBalance = 0;
            
            for (uint256 j = 0; j < trackedAssets.length; j++) {
                address assetAddress = address(trackedAssets[j]);
                uint256 withdrawnBalance = 0;
                
                try node.withdrawn(trackedAssets[j]) returns (uint256 _withdrawnBalance) {
                    withdrawnBalance = _withdrawnBalance;
                } catch {
                    withdrawnBalance = 0;
                }
                
                // Store in the contract's mapping
                nodeAssetWithdrawnBalances[nodeAddress][assetAddress] = withdrawnBalance;
                totalWithdrawnBalance += withdrawnBalance;
            }
            
            snapshots[i].totalWithdrawnBalance = totalWithdrawnBalance;
        }
        
        return snapshots;
    }


    
    //--------------------------------------------------------------------------
    // Upgrade Functions 
    //--------------------------------------------------------------------------
    
    /**
     * @dev Upgrades EigenLayer contracts to versions supporting slashing
     */
    function upgradeEigenlayerContracts() internal {
        
        // TODO update to not use pod, pos, etc.
        address oldEigenPodManagerImpl = getImplementationAddressOfTransparentUpgradeableProxy(address(eigenPodManager));
        address oldDelegationManagerImpl =
            getImplementationAddressOfTransparentUpgradeableProxy(address(delegationManager));

        address allocationManagerImpl = address(
            new AllocationManager(
                delegationManager,
                pauserRegistry,
                IPermissionController(address(0)),
                15 days,
                15 days
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
            14 days
        );

        EigenPodManager newEigenPodManagerImpl = new EigenPodManager(
            ethposDeposit,
            eigenPodBeacon,
            delegationManager,
            pauserRegistry
        );

        vm.etch(oldDelegationManagerImpl, address(newDelegationManagerImpl).code);
        vm.etch(oldEigenPodManagerImpl, address(newEigenPodManagerImpl).code);
    }
    
    /**
     * @dev Upgrades YnEigen contracts to be compatible with new EigenLayer interfaces
     */
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
                15 days
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
            14 days
        );

        EigenPodManager newEigenPodManagerImpl = new EigenPodManager(
            ethposDeposit,
            eigenPodBeacon,
            delegationManager,
            pauserRegistry
        );

        vm.etch(oldDelegationManagerImpl, address(newDelegationManagerImpl).code);
        vm.etch(oldEigenPodManagerImpl, address(newEigenPodManagerImpl).code);
        
        // Synchronize all nodes
        ITokenStakingNode[] memory nodes = tokenStakingNodesManager.getAllNodes();
        for (uint256 i = 0; i < nodes.length; i++) {
            vm.prank(admin);
            nodes[i].synchronize();
        }
    }
        

    //--------------------------------------------------------------------------
    // Utility Functions
    //--------------------------------------------------------------------------
    
    
    /**
     * @dev Gets the implementation address of a proxy
     */
    function getImplementationAddressOfTransparentUpgradeableProxy(
        address proxy
    ) internal view returns (address) {
        return address(uint160(uint256(vm.load(proxy, IMPLEMENTATION_SLOT))));
    }
    
    
    /**
     * @dev Returns a default strategy for testing
     */
    function getDefaultStrategy() internal view returns (IStrategy) {
        return eigenStrategyManager.strategies(wstETH);
    }
    
    /**
     * @dev Returns a list of tracked assets for testing
     */
    function getTrackedAssets() internal view returns (IERC20[] memory) {
        return assetRegistry.getAssets();
    }
    
    /**
     * @dev Converts an asset amount to the unit of account
     */
    function convertToUnitOfAccount(IERC20 asset, uint256 amount) internal view returns (uint256) {
        return assetRegistry.convertToUnitOfAccount(asset, amount);
    }
    
    /**
     * @dev Verifies that two node state snapshots are identical
     */
    function verifyNodeStatesUnchanged(
        TokenStakingNodeStateSnapshot[] memory beforeSnapshot,
        TokenStakingNodeStateSnapshot[] memory afterSnapshot
    ) internal pure {
        require(beforeSnapshot.length == afterSnapshot.length, "Snapshot array lengths differ");
        
        for (uint256 i = 0; i < beforeSnapshot.length; i++) {
            assertEq(beforeSnapshot[i].queuedShares, afterSnapshot[i].queuedShares, "queuedShares changed");
            assertEq(beforeSnapshot[i].legacyQueuedShares, afterSnapshot[i].legacyQueuedShares, "legacyQueuedShares changed");
            assertEq(beforeSnapshot[i].delegatedTo, afterSnapshot[i].delegatedTo, "delegatedTo changed");
            assertEq(beforeSnapshot[i].isSynchronized, afterSnapshot[i].isSynchronized, "isSynchronized changed");
            assertEq(beforeSnapshot[i].totalWithdrawnBalance, afterSnapshot[i].totalWithdrawnBalance, "totalWithdrawnBalance changed");
        }
    }
}

