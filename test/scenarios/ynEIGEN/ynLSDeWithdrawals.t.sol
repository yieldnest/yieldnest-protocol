// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IStrategy} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {TransparentUpgradeableProxy, ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {IRedeemableAsset} from "src/interfaces/IRedeemableAsset.sol";

import {RedemptionAssetsVault} from "src/ynEIGEN/RedemptionAssetsVault.sol";
import {WithdrawalQueueManager} from "src/WithdrawalQueueManager.sol";

import "./ynLSDeUpgradeScenario.sol";

contract ynLSDeWithdrawalsTest is ynLSDeUpgradeScenario {

    address public constant user = address(0x42069);

    ITokenStakingNode public tokenStakingNode;
    RedemptionAssetsVault public redemptionAssetsVault;
    WithdrawalQueueManager public withdrawalQueueManager;

    function setUp() public override {
        super.setUp();

        // upgrades the contracts
        {
            test_Upgrade_AllContracts_Batch();
            test_Upgrade_TokenStakingNodeImplementation_Scenario();
        }

        // deal assets to user
        {
            deal({ token: chainAddresses.lsd.WSTETH_ADDRESS, to: user, give: 1 ether });
            deal({ token: chainAddresses.lsd.WOETH_ADDRESS, to: user, give: 1 ether });
            deal({ token: chainAddresses.lsd.RETH_ADDRESS, to: user, give: 1 ether });
            deal({ token: chainAddresses.lsd.SFRXETH_ADDRESS, to: user, give: 1 ether });
        }

        // deploy RedemptionAssetsVault
        {
            TransparentUpgradeableProxy _proxy = new TransparentUpgradeableProxy(
                address(new RedemptionAssetsVault()),
                actors.admin.PROXY_ADMIN_OWNER,
                ""
            );
            redemptionAssetsVault = RedemptionAssetsVault(payable(address(_proxy)));
        }

        // deploy WithdrawalQueueManager
        {
            TransparentUpgradeableProxy _proxy = new TransparentUpgradeableProxy(
                address(new WithdrawalQueueManager()),
                actors.admin.PROXY_ADMIN_OWNER,
                ""
            );
            withdrawalQueueManager = WithdrawalQueueManager(address(_proxy));
        }

        // initialize tokenStakingNodesManager
        {
            vm.prank(actors.admin.ADMIN);
            tokenStakingNodesManager.initializeV2(address(this), actors.ops.WITHDRAWAL_MANAGER);
        }

        // initialize RedemptionAssetsVault
        {
            RedemptionAssetsVault.Init memory _init = RedemptionAssetsVault.Init({
                admin: actors.admin.PROXY_ADMIN_OWNER,
                redeemer: address(withdrawalQueueManager),
                ynEigen: yneigen,
                assetRegistry: assetRegistry
            });
            redemptionAssetsVault.initialize(_init);
        }

        // initialize WithdrawalQueueManager
        {
            WithdrawalQueueManager.Init memory _init = WithdrawalQueueManager.Init({
                name: "ynLSDe Withdrawal Manager",
                symbol: "ynLSDeWM",
                redeemableAsset: IRedeemableAsset(address(yneigen)),
                redemptionAssetsVault: redemptionAssetsVault,
                admin: actors.admin.PROXY_ADMIN_OWNER,
                withdrawalQueueAdmin: actors.ops.WITHDRAWAL_MANAGER,
                redemptionAssetWithdrawer: actors.ops.REDEMPTION_ASSET_WITHDRAWER,
                requestFinalizer:  actors.ops.REQUEST_FINALIZER,
                withdrawalFee: 500, // 0.05%
                feeReceiver: actors.admin.FEE_RECEIVER
            });
            withdrawalQueueManager.initialize(_init);
        }
    }

    //
    // queueWithdrawals
    //

    function testQueueWithdrawals() public {
        _setupTokenStakingNode(1 ether);

        IStrategy[] memory _strategies = new IStrategy[](3);
        _strategies[0] = IStrategy(chainAddresses.lsdStrategies.STETH_STRATEGY_ADDRESS);
        _strategies[1] = IStrategy(chainAddresses.lsdStrategies.OETH_STRATEGY_ADDRESS);
        _strategies[2] = IStrategy(chainAddresses.lsdStrategies.SFRXETH_STRATEGY_ADDRESS);

        uint256[] memory _shares = new uint256[](3);
        _shares[0] = IStrategy(chainAddresses.lsdStrategies.STETH_STRATEGY_ADDRESS).userUnderlyingView((address(tokenStakingNode)));
        _shares[1] = IStrategy(chainAddresses.lsdStrategies.OETH_STRATEGY_ADDRESS).userUnderlyingView((address(tokenStakingNode)));
        _shares[2] = IStrategy(chainAddresses.lsdStrategies.SFRXETH_STRATEGY_ADDRESS).userUnderlyingView((address(tokenStakingNode)));

        // vm.prank(actors.ops.TOKEN_STAKING_NODES_WITHDRAWER);
        // tokenStakingNode.queueWithdrawals(_strategies, _shares); // @todo - here
    }

    function testQueueWithdrawalsWrongCaller() public {
        _setupTokenStakingNode(1 ether);

        IStrategy[] memory _strategies = new IStrategy[](1);
        _strategies[0] = IStrategy(chainAddresses.lsdStrategies.STETH_STRATEGY_ADDRESS);
        uint256[] memory _shares = new uint256[](1);
        _shares[0] = 1 ether;

        vm.expectRevert(abi.encodeWithSelector(TokenStakingNode.NotTokenStakingNodesWithdrawer.selector));
        tokenStakingNode.queueWithdrawals(_strategies, _shares);
    }

    //
    // completeQueuedWithdrawals
    //

    //
    // processPrincipalWithdrawals
    //

    //
    // requestWithdrawal
    //

    //
    // claimWithdrawal
    //

    // struct Withdrawal {
    //     // The address that originated the Withdrawal
    //     address staker;
    //     // The address that the staker was delegated to at the time that the Withdrawal was created
    //     address delegatedTo;
    //     // The address that can complete the Withdrawal + will receive funds when completing the withdrawal
    //     address withdrawer;
    //     // Nonce used to guarantee that otherwise identical withdrawals have unique hashes
    //     uint256 nonce;
    //     // Block number when the Withdrawal was created
    //     uint32 startBlock;
    //     // Array of strategies that the Withdrawal contains
    //     IStrategy[] strategies;
    //     // Array containing the amount of shares in each Strategy in the `strategies` array
    //     uint256[] shares;
    // }

    function _setupTokenStakingNode(uint256 _amount) private {
        vm.prank(actors.ops.STAKING_NODE_CREATOR);
        tokenStakingNode = tokenStakingNodesManager.createTokenStakingNode();

        uint256 _len = 3;
        IERC20[] memory _assetsToDeposit = new IERC20[](_len);
        _assetsToDeposit[0] = IERC20(chainAddresses.lsd.WSTETH_ADDRESS);
        _assetsToDeposit[1] = IERC20(chainAddresses.lsd.WOETH_ADDRESS);
        _assetsToDeposit[2] = IERC20(chainAddresses.lsd.SFRXETH_ADDRESS);

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
}