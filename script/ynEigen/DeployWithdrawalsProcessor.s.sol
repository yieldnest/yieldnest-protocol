// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {TransparentUpgradeableProxy, ITransparentUpgradeableProxy} from
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
        bool _fullDeployment = vm.envBool("FULL_DEPLOYMENT");

        if (_fullDeployment) {
            require(!_isOngoingWithdrawals(), "!isOngoingWithdrawals");
        }

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

            if (_fullDeployment) {
                withdrawalsProcessor = WithdrawalsProcessor(
                    address(
                        new TransparentUpgradeableProxy(
                            address(withdrawalsProcessor), chainAddresses.ynEigen.TIMELOCK_CONTROLLER_ADDRESS, ""
                        )
                    )
                );

                WithdrawalsProcessor(address(withdrawalsProcessor)).initialize(owner, keeper);
            }
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

            // HOLESKY
            // ----------------------------------
            // Grant roles to WithdrawalsProcessor:
            // YNSecurityCouncil:  0x743b91CDB1C694D4F51bCDA3a4A59DcC0d02b913
            // WithdrawalsProcessor:  0xA1C5E681D143377F78eF727db73Deaa70EE4441f (proxy) -- V1
            // EigenStrategyManager:  0xA0a11A9b84bf87c0323bc183715a22eC7881B7FC
            // withdrawalQueueManager:  0xaF8052DC454318D52A4478a91aCa14305590389f
            // ----------------------------------

            // ----------------------------------
            // WithdrawalsProcessor:  0xdDb2282f56A7355DD904E7d1074980d69A6bAFd3 -- V2
            // ----------------------------------

            // ----------------------------------
            // Grant roles to WithdrawalsProcessor:
            // YNSecurityCouncil:  0x743b91CDB1C694D4F51bCDA3a4A59DcC0d02b913
            // WithdrawalsProcessor:  0x6eceD9B156C3747bc3A94BCD20D94265d904842e  -- new proxy
            // EigenStrategyManager:  0xA0a11A9b84bf87c0323bc183715a22eC7881B7FC
            // withdrawalQueueManager:  0xaF8052DC454318D52A4478a91aCa14305590389f
            // ----------------------------------

            // MAINNET
            // ----------------------------------
            // Grant roles to WithdrawalsProcessor:
            // YNSecurityCouncil:  0xfcad670592a3b24869C0b51a6c6FDED4F95D6975
            // WithdrawalsProcessor:  0x57F6991f1205Ba50D0Acc30aF08555721Dc4A117
            // EigenStrategyManager:  0x92D904019A92B0Cafce3492Abb95577C285A68fC
            // withdrawalQueueManager:  0x8Face3283E20b19d98a7a132274B69C1304D60b4
            // ----------------------------------
        }

        vm.stopBroadcast();
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

// == Logs ==
//   WithdrawalsProcessor:  0xd1Cc0F09Bcc5695810C44F4d34BDcf28eD3a3fa7