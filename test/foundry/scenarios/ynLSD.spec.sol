// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;
import { IntegrationBaseTest } from "test/foundry/integration/IntegrationBaseTest.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IStrategy} from "src/external/eigenlayer/v0.1.0/interfaces/IStrategy.sol";
import {IStrategyManager} from "src/external/eigenlayer/v0.1.0/interfaces/IStrategyManager.sol";
import {IDelegationManager} from "src/external/eigenlayer/v0.1.0/interfaces/IDelegationManager.sol";
import {ILSDStakingNode} from "src/interfaces/ILSDStakingNode.sol";
import {YieldNestOracle} from "src/YieldNestOracle.sol";

contract YnLSDInflationAttackTest is IntegrationBaseTest  {

	address internal _alice = makeAddr("alice");
    address internal _bob = makeAddr("bob");

    ynLSD internal _vault;
    IERC20 internal _assetToken;

    uint256 internal ONE_ASSET;
    uint256 internal ONE_SHARE;
    uint256 internal constant INITIAL_AMOUNT = 10_000_000;

	function setUp() public {
		super.setUp();
		_assetToken = IERC20(chainAddresses.ls.RETH_ADDRESS);
		_vault = ynlsd;
	}

    function test_ynLSDdonationToZeroShareAttack() public {
        // Front-running part
        uint256 bobDepositAmount = (INITIAL_AMOUNT / 2) * ONE_ASSET;
        // Alice knows that Bob is about to deposit INITIAL_AMOUNT*0.5 ATK to the Vault by observing the mempool
        vm.startPrank(_alice);
        uint256 aliceDepositAmount = 1;
        uint256 aliceShares = _vault.deposit(_assetToken, aliceDepositAmount, _alice);
        assertEq(aliceShares, aliceDepositAmount); // On the first deposit, #shares == #depositedTokens
        // Try to inflate shares value
        _assetToken.transfer(address(_vault), bobDepositAmount);
        vm.stopPrank();

        // Check that Bob did not get 0 share when he deposits
        vm.prank(_bob);
        try _vault.deposit(_assetToken, bobDepositAmount, _bob) returns (uint256 bobShares){
            // Try catch in case minting of 0 shares is forbidden
            assertGt(bobShares, 0);
            return;
        } catch Error(string memory reason) {
            console.log(reason);
            if (_vault.convertToShares(_assetToken, bobDepositAmount) == 0) {
                // We can assume it reverted because 0 shares were to be minted
                return;
            } else {
                console.log("Investigate reason");
                assertTrue(false);
            }
        }
    }

    function test_ynLSDdonationToOneShareAttack() public {
        // Front-running part
        uint256 bobDepositAmount = INITIAL_AMOUNT / 2 * ONE_ASSET;
        // Alice knows that Bob is about to deposit INITIAL_AMOUNT*0.5 ATK to the Vault by observing the mempool
        vm.startPrank(_alice);
        uint256 aliceDepositAmount = 1;
        uint256 aliceShares = _vault.deposit(_assetToken, aliceDepositAmount, _alice);
        assertEq(aliceShares, aliceDepositAmount); // On the first deposit, #shares == #depositedTokens
        // Try to inflate shares value
        _assetToken.transfer(address(_vault), bobDepositAmount / 2);
        vm.stopPrank();

        // Check that Bob will not get only 1 share when he deposits
        assertGt(_vault.convertToShares(_assetToken, bobDepositAmount), 1);
    }
}

