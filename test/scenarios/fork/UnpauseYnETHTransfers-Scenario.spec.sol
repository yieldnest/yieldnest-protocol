// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;
import {StakingNodesManager} from "src/StakingNodesManager.sol";
import {ynETH} from "src/ynETH.sol";
import {RewardsReceiver} from "src/RewardsReceiver.sol";
import {RewardsDistributor} from "src/RewardsDistributor.sol";
import {ProxyAdmin} from "lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {IRewardsDistributor} from "src/interfaces/IRewardsDistributor.sol";
import {IStakingNodesManager} from "src/interfaces/IStakingNodesManager.sol";
import {IStakingNode} from "src/interfaces/IStakingNodesManager.sol";
import {IStrategy} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {TransparentUpgradeableProxy} from "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ITransparentUpgradeableProxy} from "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ScenarioBaseTest} from "test/scenarios/ScenarioBaseTest.sol";
import { Invariants } from "test/scenarios/Invariants.sol";

import {UpgradeableBeacon} from "lib/openzeppelin-contracts/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {TestStakingNodesManagerV2} from "test/mocks/TestStakingNodesManagerV2.sol";
import {TestStakingNodeV2} from "test/mocks/TestStakingNodeV2.sol";

contract UnpauseYnETHScenario is ScenarioBaseTest {

    address YNSecurityCouncil = 0xfcad670592a3b24869C0b51a6c6FDED4F95D6975;


    function setUp() public override {
        super.setUp();   

        // All tests start with unpausing
        uint256 previousTotalDeposited = yneth.totalDepositedInPool();
        uint256 previousTotalAssets = yneth.totalAssets();
        uint256 previousTotalSupply = IERC20(address(yneth)).totalSupply();

        vm.prank(YNSecurityCouncil);
        yneth.unpauseTransfers();

        runSystemStateInvariants(previousTotalDeposited, previousTotalAssets, previousTotalSupply);     
    }
    
    function test_unpauseTransfers_ynETH_NewDeposit_and_Transfer_Scenario() public {

        // Simulate a deposit of ETH and transfer of ynETH tokens
        address receiver = address(0x123);
        address to = address(0x456);
        uint256 depositAmount = 1000 ether;
        uint256 transferAmount = 100 ether; // 100 ynETH

        // Deposit ETH and receive ynETH shares
        vm.deal(receiver, depositAmount); // Provide ETH to the receiver
        vm.prank(receiver);
        yneth.depositETH{value: depositAmount}(receiver);

        // Transfer ynETH shares to another address
        vm.prank(receiver);
        yneth.transfer(to, transferAmount);

        assertEq(yneth.balanceOf(to), transferAmount, "Transfer balance check failed");
    }

    function test_unpauseTransfers_transferFromWhale_Scenario() public {
        address whale = address(0xB9779AeC32f4cbF376F325d8c393B0D2711874eD);
        address recipient = address(0xDeaDBEEFCAfebABe000000000000000000000000);
        uint256 whaleBalance = yneth.balanceOf(whale);
        uint256 transferAmount = whaleBalance / 2;

        vm.prank(whale);
        yneth.transfer(recipient, transferAmount);

        assertEq(yneth.balanceOf(recipient), transferAmount, "Recipient did not receive the correct amount of ynETH");
    }

    function test_unpauseTransfers_tryToUnpauseAgain_Scenario() public {
        vm.prank(YNSecurityCouncil);
        yneth.unpauseTransfers();

        address whale = address(0xB9779AeC32f4cbF376F325d8c393B0D2711874eD);
        address recipient = address(0xDeaDBEEFCAfebABe000000000000000000000000);
        uint256 whaleBalance = yneth.balanceOf(whale);
        uint256 transferAmount = whaleBalance / 2;

        vm.prank(whale);
        yneth.transfer(recipient, transferAmount);

        assertEq(yneth.balanceOf(recipient), transferAmount, "Recipient did not receive the correct amount of ynETH");
    }

    function runSystemStateInvariants(
        uint256 previousTotalDeposited,
        uint256 previousTotalAssets,
        uint256 previousTotalSupply
    ) public {  
        assertEq(yneth.totalDepositedInPool(), previousTotalDeposited, "Total deposit integrity check failed");
        assertEq(yneth.totalAssets(), previousTotalAssets, "Total assets integrity check failed");
        assertEq(yneth.totalSupply(), previousTotalSupply, "Share mint integrity check failed");
	}
}