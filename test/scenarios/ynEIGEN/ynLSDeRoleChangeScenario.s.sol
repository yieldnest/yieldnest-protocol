// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {ITokenStakingNode} from "../../../src/interfaces/ITokenStakingNode.sol";

import {HoleskyLSDRateProvider} from "../../../src/testnet/HoleksyLSDRateProvider.sol";

import {TestStakingNodesManagerV2} from "../../mocks/TestStakingNodesManagerV2.sol";
import {TestStakingNodeV2} from "../../mocks/TestStakingNodeV2.sol";

import "./ynLSDeScenarioBaseTest.sol";

contract ynLSDeRoleChangeScenario is ynLSDeScenarioBaseTest {

    function test_AddDefaultAdminRole_ynLSDe() public {
        address newAdmin = address(0x123); // Example new admin address
        
        vm.startPrank(actors.wallets.YNSecurityCouncil);
        yneigen.grantRole(yneigen.DEFAULT_ADMIN_ROLE(), newAdmin);
        vm.stopPrank();
        
        assertTrue(yneigen.hasRole(yneigen.DEFAULT_ADMIN_ROLE(), newAdmin), "New admin should have DEFAULT_ADMIN_ROLE for ynLSDe");
    }

    function test_AddDefaultAdminRole_TokenStakingNodesManager() public {
        address newAdmin = address(0x456); // Example new admin address
        
        vm.startPrank(actors.wallets.YNSecurityCouncil);
        tokenStakingNodesManager.grantRole(tokenStakingNodesManager.DEFAULT_ADMIN_ROLE(), newAdmin);
        vm.stopPrank();
        
        assertTrue(tokenStakingNodesManager.hasRole(tokenStakingNodesManager.DEFAULT_ADMIN_ROLE(), newAdmin), "New admin should have DEFAULT_ADMIN_ROLE for TokenStakingNodesManager");
    }

    function test_AddDefaultAdminRole_AssetRegistry() public {
        address newAdmin = address(0x789); // Example new admin address
        
        vm.startPrank(actors.wallets.YNSecurityCouncil);
        assetRegistry.grantRole(assetRegistry.DEFAULT_ADMIN_ROLE(), newAdmin);
        vm.stopPrank();
        
        assertTrue(assetRegistry.hasRole(assetRegistry.DEFAULT_ADMIN_ROLE(), newAdmin), "New admin should have DEFAULT_ADMIN_ROLE for AssetRegistry");
    }

    function test_AddDefaultAdminRole_EigenStrategyManager() public {
        address newAdmin = address(0xabc); // Example new admin address
        
        vm.startPrank(actors.wallets.YNSecurityCouncil);
        eigenStrategyManager.grantRole(eigenStrategyManager.DEFAULT_ADMIN_ROLE(), newAdmin);
        vm.stopPrank();
        
        assertTrue(eigenStrategyManager.hasRole(eigenStrategyManager.DEFAULT_ADMIN_ROLE(), newAdmin), "New admin should have DEFAULT_ADMIN_ROLE for EigenStrategyManager");
    }

    function test_AddDefaultAdminRole_ynEigenDepositAdapter() public {
        address newAdmin = address(0xfed); // Example new admin address
        
        vm.startPrank(actors.wallets.YNSecurityCouncil);
        ynEigenDepositAdapter_.grantRole(ynEigenDepositAdapter_.DEFAULT_ADMIN_ROLE(), newAdmin);
        vm.stopPrank();
        
        assertTrue(ynEigenDepositAdapter_.hasRole(ynEigenDepositAdapter_.DEFAULT_ADMIN_ROLE(), newAdmin), "New admin should have DEFAULT_ADMIN_ROLE for ynEigenDepositAdapter");
    }

}