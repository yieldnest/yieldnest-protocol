// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {TransparentUpgradeableProxy} from
    "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {IAssetRegistry} from "src/interfaces/IAssetRegistry.sol";
import {ITokenStakingNode} from "src/interfaces/ITokenStakingNode.sol";
import {ITokenStakingNodesManager} from "src/interfaces/ITokenStakingNodesManager.sol";

import {EigenStrategyManager} from "src/ynEIGEN/EigenStrategyManager.sol";
import {WithdrawalsProcessor} from "src/ynEIGEN/WithdrawalsProcessor.sol";

import {YnEigenDeployer} from "./YnEigenDeployer.s.sol";

import {console} from "lib/forge-std/src/console.sol";

// ---- Usage ----

// deploy:
// forge script script/ynEigen/DeployWithdrawalsProcessor.s.sol:DeployWithdrawalsProcessor --verify --slow --legacy --etherscan-api-key $KEY --rpc-url $RPC_URL --broadcast

contract DeployWithdrawalsProcessor is YnEigenDeployer {

    address owner;
    address keeper;

    function run() public {
        uint256 _pk = vm.envUint("DEPLOYER_PRIVATE_KEY");

        require(!_isOngoingWithdrawals(), "!isOngoingWithdrawals");

        vm.startBroadcast(_pk);

        // set owner and keeper
        {
            owner = actors.wallets.YNSecurityCouncil;
            keeper = actors.wallets.YNnWithdrawalsYnEigen;
        }

        // deploy withdrawalsProcessor
        WithdrawalsProcessor withdrawalsProcessor;
        {
            withdrawalsProcessor = new WithdrawalsProcessor(
                chainAddresses.ynEigen.WITHDRAWAL_QUEUE_MANAGER_ADDRESS, // address(withdrawalQueueManager)
                chainAddresses.ynEigen.TOKEN_STAKING_NODES_MANAGER_ADDRESS, // address(tokenStakingNodesManager)
                chainAddresses.ynEigen.ASSET_REGISTRY_ADDRESS, // address(assetRegistry)
                chainAddresses.ynEigen.EIGEN_STRATEGY_MANAGER_ADDRESS, // address(eigenStrategyManager)
                chainAddresses.eigenlayer.DELEGATION_MANAGER_ADDRESS, // address(delegationManager)
                chainAddresses.ynEigen.YNEIGEN_ADDRESS, // address(yneigen)
                chainAddresses.ynEigen.REDEMPTION_ASSETS_VAULT_ADDRESS, // address(redemptionAssetsVault)
                chainAddresses.ynEigen.WRAPPER, // address(wrapper)
                chainAddresses.lsd.STETH_ADDRESS,
                chainAddresses.lsd.WSTETH_ADDRESS,
                chainAddresses.lsd.OETH_ADDRESS,
                chainAddresses.lsd.WOETH_ADDRESS
            );

            withdrawalsProcessor = WithdrawalsProcessor(
                address(
                    new TransparentUpgradeableProxy(
                        address(withdrawalsProcessor), chainAddresses.ynEigen.TIMELOCK_CONTROLLER_ADDRESS, ""
                    )
                )
            );

            WithdrawalsProcessor(address(withdrawalsProcessor)).initialize(owner, keeper);
        }

        // grant roles to withdrawalsProcessor
        {
            // vm.startPrank(actors.wallets.YNSecurityCouncil);
            // eigenStrategyManager.grantRole(
            //     eigenStrategyManager.STAKING_NODES_WITHDRAWER_ROLE(), address(withdrawalsProcessor)
            // );
            // eigenStrategyManager.grantRole(
            //     eigenStrategyManager.WITHDRAWAL_MANAGER_ROLE(), address(withdrawalsProcessor)
            // );
            // withdrawalQueueManager.grantRole(
            //     withdrawalQueueManager.REQUEST_FINALIZER_ROLE(), address(withdrawalsProcessor)
            // );
            // vm.stopPrank();
            console.log("----------------------------------");
            console.log("Grant roles to WithdrawalsProcessor:");
            console.log("YNSecurityCouncil: ", actors.wallets.YNSecurityCouncil);
            console.log("WithdrawalsProcessor: ", address(withdrawalsProcessor));
            console.log("EigenStrategyManager: ", chainAddresses.ynEigen.EIGEN_STRATEGY_MANAGER_ADDRESS);
            console.log("withdrawalQueueManager: ", chainAddresses.ynEigen.WITHDRAWAL_QUEUE_MANAGER_ADDRESS);
            console.log("----------------------------------");
        }
    }

    function _isOngoingWithdrawals() private returns (bool) {
        IERC20[] memory _assets = IAssetRegistry(chainAddresses.ynEigen.ASSET_REGISTRY_ADDRESS).getAssets();
        ITokenStakingNode[] memory _nodes =
            ITokenStakingNodesManager(chainAddresses.ynEigen.TOKEN_STAKING_NODES_MANAGER_ADDRESS).getAllNodes();
        for (uint256 i = 0; i < _assets.length; ++i) {
            for (uint256 j = 0; j < _nodes.length; ++j) {
                if (
                    _nodes[j].queuedShares(
                        EigenStrategyManager(chainAddresses.ynEigen.EIGEN_STRATEGY_MANAGER_ADDRESS).strategies(
                            _assets[i]
                        )
                    ) > 0
                ) {
                    console.log("Ongoing withdrawals - asset: ", address(_assets[i]));
                    console.log("Ongoing withdrawals - node: ", address(_nodes[j]));
                    return true;
                }
            }
        }
        return false;
    }

}
