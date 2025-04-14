// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IStrategy} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    TransparentUpgradeableProxy,
    ITransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {IDelegationManagerTypes} from "lib/eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";

import {ITokenStakingNodesManager} from "src/interfaces/ITokenStakingNodesManager.sol";
import {ITokenStakingNode} from "src/interfaces/ITokenStakingNode.sol";
import {IRedeemableAsset} from "src/interfaces/IRedeemableAsset.sol";
import {IYieldNestStrategyManager} from "src/interfaces/IYieldNestStrategyManager.sol";

import {LSDWrapper} from "src/ynEIGEN/LSDWrapper.sol";
import {RedemptionAssetsVault} from "src/ynEIGEN/RedemptionAssetsVault.sol";
import {WithdrawalQueueManager} from "src/WithdrawalQueueManager.sol";
import {IWithdrawalQueueManager} from "src/interfaces/IWithdrawalQueueManager.sol";
import {IwstETH} from "src/external/lido/IwstETH.sol";

import "./ynLSDeScenarioBaseTest.sol";

contract ynLSDeWithdrawalScenarioTemp is ynLSDeScenarioBaseTest {
    bool private _setup = true;

    address public constant user = address(0x111111);

    ITokenStakingNode public tokenStakingNode;

    uint256 public constant AMOUNT = 10 ether;
    uint32 public queueBlockNumber;

    function setUp() public virtual override {
        super.assignContracts(false);

        // deal assets to user
        {
            deal({token: chainAddresses.lsd.WSTETH_ADDRESS, to: user, give: 1000 ether});
            deal({token: chainAddresses.lsd.WOETH_ADDRESS, to: user, give: 1000 ether});
            deal({token: chainAddresses.lsd.SFRXETH_ADDRESS, to: user, give: 1000 ether});
        }
    }

    function _setupTokenStakingNode(uint256 _amount) private {
        vm.prank(actors.ops.STAKING_NODE_CREATOR);
        tokenStakingNode = tokenStakingNodesManager.createTokenStakingNode();

        uint256 _len = 3;
        IERC20[] memory _assetsToDeposit = new IERC20[](_len);
        _assetsToDeposit[0] = IERC20(chainAddresses.lsd.WSTETH_ADDRESS);
        _assetsToDeposit[1] = IERC20(chainAddresses.lsd.SFRXETH_ADDRESS);
        _assetsToDeposit[2] = IERC20(chainAddresses.lsd.WOETH_ADDRESS);

        uint256[] memory _amounts = new uint256[](_len);
        _amounts[0] = _amount;
        _amounts[1] = _amount;
        _amounts[2] = _amount;

        vm.startPrank(user);
        for (uint256 i = 0; i < _len; i++) {
            _assetsToDeposit[i].approve(address(yneigen), _amounts[i]);
            yneigen.deposit(_assetsToDeposit[i], _amounts[i], user);
        }
        vm.stopPrank();

        vm.startPrank(actors.ops.STRATEGY_CONTROLLER);
        eigenStrategyManager.stakeAssetsToNode(tokenStakingNode.nodeId(), _assetsToDeposit, _amounts);
        vm.stopPrank();
    }

    function _queueWithdrawalSTETH(uint256 _amount) internal {
        IStrategy _strategy = IStrategy(chainAddresses.lsdStrategies.STETH_STRATEGY_ADDRESS);
        vm.prank(actors.ops.YNEIGEN_WITHDRAWAL_MANAGER);
        tokenStakingNode.queueWithdrawals(_strategy, _amount);
        queueBlockNumber = uint32(block.number);
    }

    function testQueueWithdrawalBeforeELUpgradeAndCompletedAfterELAndYnUpgrade(bool _executeSynchronizeNodesAndUpdateBalances) public {
        uint256 _amount = 30 ether;
         if (_setup) _setupTokenStakingNode(_amount);


        _setup = false;
        _queueWithdrawalSTETH(_amount);

        {
            IERC20[] memory assets = assetRegistry.getAssets();
            uint256 assetsLength = assets.length;
            for (uint256 i = 0; i < assetsLength; i++) {
                eigenStrategyManager.updateTokenStakingNodesBalances(assets[i]);
            }
        }


        TestUpgradeUtils.executeEigenlayerSlashingUpgrade();
        super.upgradeTokenStakingNodesManagerAndTokenStakingNode();
                // Capture total assets before upgrade
        uint256 totalAssetsBefore = yneigen.totalAssets();

        IStrategy[] memory _strategies = new IStrategy[](1);
        _strategies[0] = IStrategy(chainAddresses.lsdStrategies.STETH_STRATEGY_ADDRESS);
        uint256[] memory _shares = new uint256[](1);
        _shares[0] = _amount;

        IDelegationManagerTypes.Withdrawal memory withdrawal = IDelegationManagerTypes.Withdrawal({
            staker: address(tokenStakingNode),
            delegatedTo: delegationManager.delegatedTo(address(tokenStakingNode)),
            withdrawer: address(tokenStakingNode),
            nonce: 0,
            startBlock: queueBlockNumber,
            strategies: _strategies,
            scaledShares: _shares
        });

        IStrategy _strategy = IStrategy(chainAddresses.lsdStrategies.STETH_STRATEGY_ADDRESS);
        
        uint256 preELIP002QueuedSharesBefore = tokenStakingNode.preELIP002QueuedSharesAmount(_strategy);
        uint256 queuedSharesBefore = tokenStakingNode.queuedShares(_strategy);

        vm.roll(block.number + delegationManager.minWithdrawalDelayBlocks() + 1);

        vm.prank(actors.ops.YNEIGEN_WITHDRAWAL_MANAGER);
        tokenStakingNode.completeQueuedWithdrawals(withdrawal, true);


        if (_executeSynchronizeNodesAndUpdateBalances) {
            eigenStrategyManager.synchronizeNodesAndUpdateBalances(tokenStakingNodesManager.getAllNodes());
        }

        // Assert total assets remain unchanged after completing withdrawal
        assertApproxEqAbs(
            totalAssetsBefore,
            yneigen.totalAssets(),
            2,
            "Total assets should remain roughly equal after completing withdrawal"
        );


        uint256 preELIP002QueuedSharesAfter = tokenStakingNode.preELIP002QueuedSharesAmount(_strategy);
        uint256 queuedSharesAfter = tokenStakingNode.queuedShares(_strategy);

        assertEq(preELIP002QueuedSharesAfter, preELIP002QueuedSharesBefore - _amount, "preELIP002QueuedSharesAfter should reduce by the amount withdrawn");
        assertEq(queuedSharesAfter, queuedSharesBefore, "queuedShares should remain same for legacy withdrawals");
    }

}
