// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {ScenarioBaseTest} from "test/scenarios/ScenarioBaseTest.sol";
import {IStakingNodesManager} from "src/interfaces/IStakingNodesManager.sol";
import {IStakingNode} from "src/interfaces/IStakingNodesManager.sol";
import {ProxyAdmin} from "lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy} from "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {ynETH} from "src/ynETH.sol";

contract ynETHRenamamble is ynETH {

    function rename() public {
        ERC20Storage storage $ = __getERC20Storage();

        if (keccak256(bytes($._symbol)) == keccak256(bytes("ynETHn"))) {
            revert("Symbol and name already set to desired value");
        }

        $._name = "YieldNest Native Staked ETH";
        $._symbol = "ynETHn";
    }

    // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.ERC20")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ERC20StorageLocation = 0x52c63247e1f47db19d5ce0460030c497f067ca4cebf71ba98eeadabe20bace00;

    function __getERC20Storage() internal returns (ERC20Storage storage $) {
        assembly {
            $.slot := ERC20StorageLocation
        }
    }
}


contract RenameScenario is ScenarioBaseTest {
    address YNSecurityCouncil;

    function setUp() public override {
        super.setUp();
        YNSecurityCouncil = actors.wallets.YNSecurityCouncil;
    }

    function test_Rename_StakingNode_Scenario() public {
        // Store the previous name and symbol
        string memory previousName = yneth.name();
        string memory previousSymbol = yneth.symbol();

        // Deploy the new implementation
        ynETHRenamamble newImplementation = new ynETHRenamamble();

        // Upgrade the proxy to the new implementation
        vm.prank(YNSecurityCouncil);
        ProxyAdmin(getTransparentUpgradeableProxyAdminAddress(address(yneth))).upgradeAndCall(
            ITransparentUpgradeableProxy(address(yneth)),
            address(newImplementation),
            ""
        );

        // Call the rename function
        vm.prank(YNSecurityCouncil);
        ynETHRenamamble(payable(address(yneth))).rename();

        // Verify the name and symbol have changed
        assertNotEq(yneth.name(), previousName, "Name should have changed");
        assertNotEq(yneth.symbol(), previousSymbol, "Symbol should have changed");
        assertEq(yneth.name(), "YieldNest Native Staked ETH", "New name is incorrect");
        assertEq(yneth.symbol(), "ynETHn", "New symbol is incorrect");

        // Verify that calling rename again reverts
        vm.prank(YNSecurityCouncil);
        vm.expectRevert("Symbol and name already set to desired value");
        ynETHRenamamble(payable(address(yneth))).rename();
    }
}