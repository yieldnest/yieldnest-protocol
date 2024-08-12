// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

import {ITokenStakingNode} from "../../../src/interfaces/ITokenStakingNode.sol";

import {HoleskyLSDRateProvider} from "../../../src/testnet/HoleksyLSDRateProvider.sol";

import {TestStakingNodesManagerV2} from "../../mocks/TestStakingNodesManagerV2.sol";
import {TestStakingNodeV2} from "../../mocks/TestStakingNodeV2.sol";

import "./ynLSDeScenarioBaseTest.sol";
import "forge-std/console.sol";

contract ynLSDeUpgradeScenario is ynLSDeScenarioBaseTest {

    address public constant TIMELOCK = 0x62173555C27C67644C5634e114e42A63A59CD7A5;
    
    function test_Upgrade_ynLSDe_Scenario() public {
        if (block.chainid != 17000) return;

        address previousImplementation = getTransparentUpgradeableProxyImplementationAddress(address(yneigen));
        address newImplementation = address(new ynEigen()); 

        uint256 previousTotalAssets = yneigen.totalAssets();
        uint256 previousTotalSupply = IERC20(address(yneigen)).totalSupply();

        vm.prank(getTransparentUpgradeableProxyAdminAddress(address(yneigen)));
        ITransparentUpgradeableProxy(address(yneigen)).upgradeToAndCall(newImplementation, "");

        runUpgradeInvariants(address(yneigen), previousImplementation, newImplementation);
        runSystemStateInvariants(previousTotalAssets, previousTotalSupply);
    }
    
    function test_Upgrade_TokenStakingNodesManager_Scenario() public {
        if (block.chainid != 17000) return;

        address previousStakingNodesManagerImpl = getTransparentUpgradeableProxyImplementationAddress(address(tokenStakingNodesManager));
        address newStakingNodesManagerImpl = address(new TokenStakingNodesManager());
        
        uint256 previousTotalAssets = yneigen.totalAssets();
        uint256 previousTotalSupply = IERC20(address(yneigen)).totalSupply();

        vm.prank(getTransparentUpgradeableProxyAdminAddress(address(tokenStakingNodesManager)));
        ITransparentUpgradeableProxy(address(tokenStakingNodesManager)).upgradeToAndCall(newStakingNodesManagerImpl, "");
        
        runUpgradeInvariants(address(tokenStakingNodesManager), previousStakingNodesManagerImpl, newStakingNodesManagerImpl);
        runSystemStateInvariants(previousTotalAssets, previousTotalSupply);
    }

    function test_Upgrade_AssetRegistry() public {
        if (block.chainid != 17000) return;

        address previousAssetRegistryImpl = getTransparentUpgradeableProxyImplementationAddress(address(assetRegistry));
        address newAssetRegistryImpl = address(new AssetRegistry());
        
        uint256 previousTotalAssets = yneigen.totalAssets();
        uint256 previousTotalSupply = IERC20(address(yneigen)).totalSupply();

        vm.prank(getTransparentUpgradeableProxyAdminAddress(address(assetRegistry)));
        ITransparentUpgradeableProxy(address(assetRegistry)).upgradeToAndCall(newAssetRegistryImpl, "");
        
        runUpgradeInvariants(address(assetRegistry), previousAssetRegistryImpl, newAssetRegistryImpl);
        runSystemStateInvariants(previousTotalAssets, previousTotalSupply);
    }

    function test_Upgrade_EigenStrategyManager() public {
        if (block.chainid != 17000) return;

        address previousEigenStrategyManagerImpl = getTransparentUpgradeableProxyImplementationAddress(address(eigenStrategyManager));
        address newEigenStrategyManagerImpl = address(new EigenStrategyManager());
        
        uint256 previousTotalAssets = yneigen.totalAssets();
        uint256 previousTotalSupply = IERC20(address(yneigen)).totalSupply();

        vm.prank(getTransparentUpgradeableProxyAdminAddress(address(eigenStrategyManager)));
        ITransparentUpgradeableProxy(address(eigenStrategyManager)).upgradeToAndCall(newEigenStrategyManagerImpl, "");
        
        runUpgradeInvariants(address(eigenStrategyManager), previousEigenStrategyManagerImpl, newEigenStrategyManagerImpl);
        runSystemStateInvariants(previousTotalAssets, previousTotalSupply);
    }

    function test_Upgrade_LSDRateProvider() public {
        if (block.chainid != 17000) return;

        address previousLSDRateProviderImpl = getTransparentUpgradeableProxyImplementationAddress(address(lsdRateProvider));
        address newLSDRateProviderImpl = address(new HoleskyLSDRateProvider());
        
        uint256 previousTotalAssets = yneigen.totalAssets();
        uint256 previousTotalSupply = IERC20(address(yneigen)).totalSupply();

        vm.prank(getTransparentUpgradeableProxyAdminAddress(address(lsdRateProvider)));
        ITransparentUpgradeableProxy(address(lsdRateProvider)).upgradeToAndCall(newLSDRateProviderImpl, "");

        runUpgradeInvariants(address(lsdRateProvider), previousLSDRateProviderImpl, newLSDRateProviderImpl);
        runSystemStateInvariants(previousTotalAssets, previousTotalSupply);
    }

    function test_Upgrade_ynEigenDepositAdapter() public {
        if (block.chainid != 17000) return;

        address previousYnEigenDepositAdapterImpl = getTransparentUpgradeableProxyImplementationAddress(address(ynEigenDepositAdapter_));
        address newYnEigenDepositAdapterImpl = address(new ynEigenDepositAdapter());
        
        uint256 previousTotalAssets = yneigen.totalAssets();
        uint256 previousTotalSupply = IERC20(address(yneigen)).totalSupply();

        vm.prank(getTransparentUpgradeableProxyAdminAddress(address(ynEigenDepositAdapter_)));
        ITransparentUpgradeableProxy(address(ynEigenDepositAdapter_)).upgradeToAndCall(newYnEigenDepositAdapterImpl, "");
        
        runUpgradeInvariants(address(ynEigenDepositAdapter_), previousYnEigenDepositAdapterImpl, newYnEigenDepositAdapterImpl);
        runSystemStateInvariants(previousTotalAssets, previousTotalSupply);
    }

    function test_Upgrade_TokenStakingNodeImplementation_Scenario() public {
        ITokenStakingNode[] memory tokenStakingNodesBefore = tokenStakingNodesManager.getAllNodes();

        uint256 previousTotalAssets = yneigen.totalAssets();
        uint256 previousTotalSupply = IERC20(address(yneigen)).totalSupply();

        TestStakingNodeV2 testStakingNodeV2 = new TestStakingNodeV2();
        vm.prank(TIMELOCK);
        tokenStakingNodesManager.upgradeTokenStakingNode(payable(testStakingNodeV2));

        UpgradeableBeacon beacon = tokenStakingNodesManager.upgradeableBeacon();
        address upgradedImplementationAddress = beacon.implementation();
        assertEq(upgradedImplementationAddress, payable(testStakingNodeV2));

        // check tokenStakingNodesManager.getAllNodes is the same as before
        ITokenStakingNode[] memory tokenStakingNodesAfter = tokenStakingNodesManager.getAllNodes();
        assertEq(tokenStakingNodesAfter.length, tokenStakingNodesBefore.length, "TokenStakingNodes length mismatch after upgrade");
        for (uint i = 0; i < tokenStakingNodesAfter.length; i++) {
            assertEq(address(tokenStakingNodesAfter[i]), address(tokenStakingNodesBefore[i]), "TokenStakingNode address mismatch after upgrade");
        }

        runSystemStateInvariants(previousTotalAssets, previousTotalSupply);
    }

    function runUpgradeInvariants(
        address proxyAddress,
        address previousImplementation,
        address newImplementation
    ) internal {
        // Check that the new implementation address is correctly set
        address currentImplementation = getTransparentUpgradeableProxyImplementationAddress(proxyAddress);
        assertEq(currentImplementation, newImplementation, "Invariant: Implementation address should match the new implementation address");
        // Ensure the implementation address has actually changed
        assertNotEq(previousImplementation, newImplementation, "Invariant: New implementation should be different from the previous one");
    }

    function runSystemStateInvariants(uint256 previousTotalAssets, uint256 previousTotalSupply) public {  
        assertEq(yneigen.totalAssets(), previousTotalAssets, "Total assets integrity check failed");
        assertEq(yneigen.totalSupply(), previousTotalSupply, "Share mint integrity check failed");
	}
}