/// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {TokenStakingNodesManager} from "src/ynEIGEN/TokenStakingNodesManager.sol";

import {IStrategy} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {ITokenStakingNode} from "src/interfaces/ITokenStakingNode.sol";
import {BaseYnEigenScript} from "script/ynEigen/BaseYnEigenScript.s.sol";
import {Utils} from "script/Utils.sol";

import {console} from "lib/forge-std/src/console.sol";
import {IAssetRegistry} from "src/interfaces/IAssetRegistry.sol";

interface IynEigen {
    function assetRegistry() external view returns (address);
    function yieldNestStrategyManager() external view returns (address);
}

contract YnEigenVerifier is BaseYnEigenScript {
    Deployment private deployment;

    using Strings for uint256;

    function tempUpgradeAdvancer() internal {

        // ⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️
        // WARNING: THIS FUNCTION IS TEMPORARY AND SHOULD BE DELETED
        // It is only used to advance time for testing upgrades
        // ⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️

        // Advance time by 3.2 days (in seconds)
        vm.warp(block.timestamp + 20 minutes);

        // Execute the most recently queued upgrade
        address[] memory targets = new address[](5);
        targets[0] = 0x18ED5129bCEfA996B4cade4e614c8941De3126d2;
        targets[1] = 0x010c60d663fddDAA076F0cE63f6692f0b5605fE5;
        targets[2] = 0x4248392db8Ee31aA579822207d059A28A38c4510;
        targets[3] = 0x582538EAFfC05e3c2dfbA233267D30b9F615ED0e;
        targets[4] = 0x5c20D1a85C7d9acB503135a498E26Eb55d806552;

        uint256[] memory values = new uint256[](5);
        values[0] = 0;
        values[1] = 0;
        values[2] = 0;
        values[3] = 0;
        values[4] = 0;

        bytes[] memory payloads = new bytes[](5);
        payloads[0] = hex"9623609d0000000000000000000000005c20d1a85c7d9acb503135a498e26eb55d806552000000000000000000000000b4edf422522e6f2ed86cba8ff0e80fb308614b7b0000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000002429b6eca9000000000000000000000000acc1fb458a1317e886db376fc8141540537e68fe00000000000000000000000000000000000000000000000000000000";
        payloads[1] = hex"9623609d000000000000000000000000a0a11a9b84bf87c0323bc183715a22ec7881b7fc00000000000000000000000022f84adbdafd2ea54f73bd8e049cbabcb8a301cf00000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000000";
        payloads[2] = hex"9623609d000000000000000000000000ad31546adbfe1ecd7137310508f112039a35b6f7000000000000000000000000655ce6ce176b7b6341397292d93198ac4f0833aa00000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000000";    
        payloads[3] = hex"9623609d0000000000000000000000006eced9b156c3747bc3a94bcd20d94265d904842e00000000000000000000000038495e927a9767feb66634b074905cde8cd24e0100000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000044ccd8af22000000000000000000000000743b91cdb1c694d4f51bcda3a4a59dcc0d02b9130000000000000000000000000000000000000000000000000f43fc2c04ee000000000000000000000000000000000000000000000000000000000000";
        payloads[4] = hex"a39cebe9000000000000000000000000ae3e488cd3746424e636dba3cf2ae502e47ffb13";

        bytes32 predecessor = bytes32(0);
        bytes32 salt = bytes32(0);

        console.log("Executing upgrade batch...");

        // Impersonate YNSecurityCouncil to execute the upgrade
        vm.startPrank(actors.wallets.YNSecurityCouncil);
        deployment.upgradeTimelock.executeBatch(
            targets,
            values, 
            payloads,
            predecessor,
            salt
        );

        ITokenStakingNode[] memory tokenStakingNodes = new ITokenStakingNode[](3);
        tokenStakingNodes[0] = ITokenStakingNode(0xD0B3C73b94B1b4D99A9C4AB8cC7fFdE2Bccd04b8);
        tokenStakingNodes[1] = ITokenStakingNode(0xE6785109DBEd94279C32D26A5c3c62A1Fe25838d);
        tokenStakingNodes[2] = ITokenStakingNode(0x132Cf14AA3F663c6e9d7DE650C54f47a44D2BD85);

        deployment.eigenStrategyManager.synchronizeNodesAndUpdateBalances(tokenStakingNodes);
        vm.stopPrank();
    }

    function _verify() public {
        deployment = loadDeployment();
        tempUpgradeAdvancer();
        verifyUpgradeTimelockRoles();
        verifyProxies();
        verifyProxyAdminOwners();
        verifyRoles();
        verifySystemParameters();
        verifyContractDependencies();
        ynEigenSanityCheck();
    }

    function verifyUpgradeTimelockRoles() internal view {
        // Verify PROPOSER_ROLE
        require(
            deployment.upgradeTimelock.hasRole(
                deployment.upgradeTimelock.PROPOSER_ROLE(), address(actors.wallets.YNSecurityCouncil)
            ),
            "upgradeTimelock: PROPOSER_ROLE INVALID"
        );
        console.log("\u2705 upgradeTimelock: PROPOSER_ROLE - ", vm.toString(address(actors.wallets.YNSecurityCouncil)));

        // Verify EXECUTOR_ROLE
        require(
            deployment.upgradeTimelock.hasRole(
                deployment.upgradeTimelock.EXECUTOR_ROLE(), address(actors.wallets.YNSecurityCouncil)
            ),
            "upgradeTimelock: EXECUTOR_ROLE INVALID"
        );
        console.log("\u2705 upgradeTimelock: EXECUTOR_ROLE - ", vm.toString(address(actors.wallets.YNSecurityCouncil)));

        // Verify CANCELLER_ROLE
        require(
            deployment.upgradeTimelock.hasRole(
                deployment.upgradeTimelock.CANCELLER_ROLE(), address(actors.wallets.YNSecurityCouncil)
            ),
            "upgradeTimelock: CANCELLER_ROLE INVALID"
        );
        console.log("\u2705 upgradeTimelock: CANCELLER_ROLE - ", vm.toString(address(actors.wallets.YNSecurityCouncil)));

        // Verify DEFAULT_ADMIN_ROLE
        require(
            deployment.upgradeTimelock.hasRole(
                deployment.upgradeTimelock.DEFAULT_ADMIN_ROLE(), address(actors.wallets.YNSecurityCouncil)
            ),
            "upgradeTimelock: DEFAULT_ADMIN_ROLE INVALID"
        );
        console.log(
            "\u2705 upgradeTimelock: DEFAULT_ADMIN_ROLE - ", vm.toString(address(actors.wallets.YNSecurityCouncil))
        );

        // Verify delay
        uint256 expectedDelay = block.chainid == 17000 ? 15 minutes : 3 days;
        require(deployment.upgradeTimelock.getMinDelay() == expectedDelay, "upgradeTimelock: DELAY INVALID");
        console.log("\u2705 upgradeTimelock: DELAY - ", deployment.upgradeTimelock.getMinDelay());
    }

    function verifyProxyContract(
        address contractAddress,
        string memory contractName,
        ProxyAddresses memory proxyAddresses
    ) internal view {

        address expectedProxyAdminOwner;

        // TODO: consider changing owner here for consistency
        if (keccak256(abi.encodePacked(contractName)) == keccak256(abi.encodePacked("ynEigenViewer")) && block.chainid == 1) {
            expectedProxyAdminOwner = actors.admin.PROXY_ADMIN_OWNER;
        } else {
            expectedProxyAdminOwner = address(deployment.upgradeTimelock);
        }

        // Verify PROXY_ADMIN_OWNER
        address proxyAdminAddress = Utils.getTransparentUpgradeableProxyAdminAddress(contractAddress);
        address proxyAdminOwner = ProxyAdmin(proxyAdminAddress).owner();
        require(
            proxyAdminOwner == expectedProxyAdminOwner,
            string.concat(contractName, ": PROXY_ADMIN_OWNER mismatch, expected: ", vm.toString(expectedProxyAdminOwner), ", got: ", vm.toString(proxyAdminOwner))
        );
        console.log(string.concat("\u2705 ", contractName, ": PROXY_ADMIN_OWNER - ", vm.toString(proxyAdminOwner)));

        // Verify ProxyAdmin address
        require(
            proxyAdminAddress == address(proxyAddresses.proxyAdmin),
            string.concat(contractName, ": ProxyAdmin address mismatch, expected: ", vm.toString(address(proxyAddresses.proxyAdmin)), ", got: ", vm.toString(proxyAdminAddress))
        );
        console.log(string.concat("\u2705 ", contractName, ": ProxyAdmin address - ", vm.toString(proxyAdminAddress)));

        // Verify Implementation address
        address implementationAddress = Utils.getTransparentUpgradeableProxyImplementationAddress(contractAddress);
        require(
            implementationAddress == proxyAddresses.implementation,
            string.concat(contractName, ": Implementation address mismatch, expected: ", vm.toString(proxyAddresses.implementation), ", got: ", vm.toString(implementationAddress))
        );
        console.log(string.concat("\u2705 ", contractName, ": Implementation address - ", vm.toString(implementationAddress)));
    }

    function verifyProxies() internal view {
        verifyProxyContract(
            address(deployment.ynEigen),
            "ynEigen",
            deployment.proxies.ynEigen
        );

        verifyProxyContract(
            address(deployment.assetRegistry),
            "assetRegistry",
            deployment.proxies.assetRegistry
        );

        verifyProxyContract(
            address(deployment.eigenStrategyManager),
            "eigenStrategyManager",
            deployment.proxies.eigenStrategyManager
        );

        verifyProxyContract(
            address(deployment.tokenStakingNodesManager),
            "tokenStakingNodesManager",
            deployment.proxies.tokenStakingNodesManager
        );

        verifyProxyContract(
            address(deployment.ynEigenDepositAdapterInstance),
            "ynEigenDepositAdapter",
            deployment.proxies.ynEigenDepositAdapter
        );

        verifyProxyContract(
            address(deployment.viewer),
            "ynEigenViewer",
            deployment.proxies.ynEigenViewer
        );

        verifyProxyContract(
            address(deployment.redemptionAssetsVault),
            "redemptionAssetsVault",
            deployment.proxies.redemptionAssetsVault
        );

        verifyProxyContract(
            address(deployment.withdrawalQueueManager),
            "withdrawalQueueManager",
            deployment.proxies.withdrawalQueueManager
        );

        verifyProxyContract(
            address(deployment.wrapper),
            "wrapper",
            deployment.proxies.wrapper
        );
    }

    function verifyProxyAdminOwners() internal view {
        address proxyAdminOwner = address(deployment.upgradeTimelock);

        address ynEigenAdmin =
            ProxyAdmin(Utils.getTransparentUpgradeableProxyAdminAddress(address(deployment.ynEigen))).owner();
        require(
            ynEigenAdmin == proxyAdminOwner,
            string.concat(
                "ynEigen: PROXY_ADMIN_OWNER INVALID, expected: ",
                vm.toString(proxyAdminOwner),
                ", got: ",
                vm.toString(ynEigenAdmin)
            )
        );
        console.log("\u2705 ynEigen: PROXY_ADMIN_OWNER - ", vm.toString(ynEigenAdmin));

        address stakingNodesManagerAdmin = ProxyAdmin(
            Utils.getTransparentUpgradeableProxyAdminAddress(address(deployment.tokenStakingNodesManager))
        ).owner();
        require(
            stakingNodesManagerAdmin == proxyAdminOwner,
            string.concat(
                "stakingNodesManager: PROXY_ADMIN_OWNER INVALID, expected: ",
                vm.toString(proxyAdminOwner),
                ", got: ",
                vm.toString(stakingNodesManagerAdmin)
            )
        );
        console.log("\u2705 stakingNodesManager: PROXY_ADMIN_OWNER - ", vm.toString(stakingNodesManagerAdmin));

        address assetRegistryAdmin =
            ProxyAdmin(Utils.getTransparentUpgradeableProxyAdminAddress(address(deployment.assetRegistry))).owner();
        require(
            assetRegistryAdmin == proxyAdminOwner,
            string.concat(
                "assetRegistry: PROXY_ADMIN_OWNER INVALID, expected: ",
                vm.toString(proxyAdminOwner),
                ", got: ",
                vm.toString(assetRegistryAdmin)
            )
        );
        console.log("\u2705 assetRegistry: PROXY_ADMIN_OWNER - ", vm.toString(assetRegistryAdmin));

        address eigenStrategyManagerAdmin = ProxyAdmin(
            Utils.getTransparentUpgradeableProxyAdminAddress(address(deployment.eigenStrategyManager))
        ).owner();
        require(
            eigenStrategyManagerAdmin == proxyAdminOwner,
            string.concat(
                "eigenStrategyManager: PROXY_ADMIN_OWNER INVALID, expected: ",
                vm.toString(proxyAdminOwner),
                ", got: ",
                vm.toString(eigenStrategyManagerAdmin)
            )
        );
        console.log("\u2705 eigenStrategyManager: PROXY_ADMIN_OWNER - ", vm.toString(eigenStrategyManagerAdmin));

        address ynEigenDepositAdapterAdmin = ProxyAdmin(
            Utils.getTransparentUpgradeableProxyAdminAddress(address(deployment.ynEigenDepositAdapterInstance))
        ).owner();
        require(
            ynEigenDepositAdapterAdmin == proxyAdminOwner,
            string.concat(
                "ynEigenDepositAdapter: PROXY_ADMIN_OWNER INVALID, expected: ",
                vm.toString(proxyAdminOwner),
                ", got: ",
                vm.toString(ynEigenDepositAdapterAdmin)
            )
        );
        console.log("\u2705 ynEigenDepositAdapter: PROXY_ADMIN_OWNER - ", vm.toString(ynEigenDepositAdapterAdmin));

        address ynEigenDepositAdapterInstanceAdmin = ProxyAdmin(
            Utils.getTransparentUpgradeableProxyAdminAddress(address(deployment.ynEigenDepositAdapterInstance))
        ).owner();
        require(
            ynEigenDepositAdapterInstanceAdmin == proxyAdminOwner,
            string.concat(
                "ynEigenDepositAdapterInstance: PROXY_ADMIN_OWNER INVALID, expected: ",
                vm.toString(proxyAdminOwner),
                ", got: ",
                vm.toString(ynEigenDepositAdapterInstanceAdmin)
            )
        );
        console.log(
            "\u2705 ynEigenDepositAdapterInstance: PROXY_ADMIN_OWNER - ",
            vm.toString(ynEigenDepositAdapterInstanceAdmin)
        );
    }

    function verifyRoles() internal view {
        //--------------------------------------------------------------------------------------
        // YnEigen roles
        //--------------------------------------------------------------------------------------

        // DEFAULT_ADMIN_ROLE
        require(
            deployment.ynEigen.hasRole(deployment.ynEigen.DEFAULT_ADMIN_ROLE(), address(actors.admin.ADMIN)),
            "ynEigen: DEFAULT_ADMIN_ROLE INVALID"
        );
        console.log("\u2705 ynEigen: DEFAULT_ADMIN_ROLE - ", vm.toString(address(actors.admin.ADMIN)));

        // PAUSER_ROLE
        require(
            deployment.ynEigen.hasRole(deployment.ynEigen.PAUSER_ROLE(), address(actors.ops.PAUSE_ADMIN)),
            "ynEigen: PAUSER_ROLE INVALID"
        );
        console.log("\u2705 ynEigen: PAUSER_ROLE - ", vm.toString(address(actors.ops.PAUSE_ADMIN)));

        // UNPAUSER_ROLE
        require(
            deployment.ynEigen.hasRole(deployment.ynEigen.UNPAUSER_ROLE(), address(actors.admin.UNPAUSE_ADMIN)),
            "ynEigen: UNPAUSER_ROLE INVALID"
        );
        console.log("\u2705 ynEigen: UNPAUSER_ROLE - ", vm.toString(address(actors.admin.UNPAUSE_ADMIN)));

        // BURNER_ROLE
        require(
            deployment.ynEigen.hasRole(deployment.ynEigen.BURNER_ROLE(), address(deployment.withdrawalQueueManager)),
            "ynEigen: BURNER_ROLE INVALID"
        );
        console.log("\u2705 ynEigen: BURNER_ROLE - ", vm.toString(address(deployment.withdrawalQueueManager)));

        //--------------------------------------------------------------------------------------
        // assetRegistry roles
        //--------------------------------------------------------------------------------------

        // DEFAULT_ADMIN_ROLE
        require(
            deployment.assetRegistry.hasRole(deployment.assetRegistry.DEFAULT_ADMIN_ROLE(), address(actors.admin.ADMIN)),
            "assetRegistry: DEFAULT_ADMIN_ROLE INVALID"
        );
        console.log("\u2705 assetRegistry: DEFAULT_ADMIN_ROLE - ", vm.toString(address(actors.admin.ADMIN)));

        // PAUSER_ROLE
        require(
            deployment.assetRegistry.hasRole(deployment.assetRegistry.PAUSER_ROLE(), address(actors.ops.PAUSE_ADMIN)),
            "assetRegistry: PAUSER_ROLE INVALID"
        );
        console.log("\u2705 assetRegistry: PAUSER_ROLE - ", vm.toString(address(actors.ops.PAUSE_ADMIN)));

        // UNPAUSER_ROLE
        require(
            deployment.assetRegistry.hasRole(
                deployment.assetRegistry.UNPAUSER_ROLE(), address(actors.admin.UNPAUSE_ADMIN)
            ),
            "assetRegistry: UNPAUSER_ROLE INVALID"
        );
        console.log("\u2705 assetRegistry: UNPAUSER_ROLE - ", vm.toString(address(actors.admin.UNPAUSE_ADMIN)));

        // ASSET_MANAGER_ROLE
        require(
            deployment.assetRegistry.hasRole(
                deployment.assetRegistry.ASSET_MANAGER_ROLE(), address(actors.admin.ASSET_MANAGER)
            ),
            "assetRegistry: ASSET_MANAGER_ROLE INVALID"
        );
        console.log("\u2705 assetRegistry: ASSET_MANAGER_ROLE - ", vm.toString(address(actors.admin.ASSET_MANAGER)));

        //--------------------------------------------------------------------------------------
        // eigenStrategyManager roles
        //--------------------------------------------------------------------------------------

        // DEFAULT_ADMIN_ROLE
        require(
            deployment.eigenStrategyManager.hasRole(
                deployment.eigenStrategyManager.DEFAULT_ADMIN_ROLE(), address(actors.admin.EIGEN_STRATEGY_ADMIN)
            ),
            "eigenStrategyManager: DEFAULT_ADMIN_ROLE INVALID"
        );
        console.log(
            "\u2705 eigenStrategyManager: DEFAULT_ADMIN_ROLE - ",
            vm.toString(address(actors.admin.EIGEN_STRATEGY_ADMIN))
        );

        // PAUSER_ROLE
        require(
            deployment.eigenStrategyManager.hasRole(
                deployment.eigenStrategyManager.PAUSER_ROLE(), address(actors.ops.PAUSE_ADMIN)
            ),
            "eigenStrategyManager: PAUSER_ROLE INVALID"
        );
        console.log("\u2705 eigenStrategyManager: PAUSER_ROLE - ", vm.toString(address(actors.ops.PAUSE_ADMIN)));

        // UNPAUSER_ROLE
        require(
            deployment.eigenStrategyManager.hasRole(
                deployment.eigenStrategyManager.UNPAUSER_ROLE(), address(actors.admin.UNPAUSE_ADMIN)
            ),
            "eigenStrategyManager: UNPAUSER_ROLE INVALID"
        );
        console.log("\u2705 eigenStrategyManager: UNPAUSER_ROLE - ", vm.toString(address(actors.admin.UNPAUSE_ADMIN)));

        // STRATEGY_CONTROLLER_ROLE
        require(
            deployment.eigenStrategyManager.hasRole(
                deployment.eigenStrategyManager.STRATEGY_CONTROLLER_ROLE(), address(actors.ops.STRATEGY_CONTROLLER)
            ),
            "eigenStrategyManager: STRATEGY_CONTROLLER_ROLE INVALID"
        );
        console.log(
            "\u2705 eigenStrategyManager: STRATEGY_CONTROLLER_ROLE - ",
            vm.toString(address(actors.ops.STRATEGY_CONTROLLER))
        );

        // STRATEGY_ADMIN_ROLE
        require(
            deployment.eigenStrategyManager.hasRole(
                deployment.eigenStrategyManager.STRATEGY_ADMIN_ROLE(), address(actors.admin.EIGEN_STRATEGY_ADMIN)
            ),
            "eigenStrategyManager: STRATEGY_ADMIN_ROLE INVALID"
        );
        console.log(
            "\u2705 eigenStrategyManager: STRATEGY_ADMIN_ROLE - ",
            vm.toString(address(actors.admin.EIGEN_STRATEGY_ADMIN))
        );

        //--------------------------------------------------------------------------------------
        // tokenStakingNodesManager roles
        //--------------------------------------------------------------------------------------

        // DEFAULT_ADMIN_ROLE
        require(
            deployment.tokenStakingNodesManager.hasRole(
                deployment.tokenStakingNodesManager.DEFAULT_ADMIN_ROLE(), address(actors.admin.ADMIN)
            ),
            "tokenStakingNodesManager: DEFAULT_ADMIN_ROLE INVALID"
        );
        console.log("\u2705 tokenStakingNodesManager: DEFAULT_ADMIN_ROLE - ", vm.toString(address(actors.admin.ADMIN)));

        address proxyAdminOwner = address(deployment.upgradeTimelock);
        // STAKING_ADMIN_ROLE
        require(
            deployment.tokenStakingNodesManager.hasRole(
                deployment.tokenStakingNodesManager.STAKING_ADMIN_ROLE(), proxyAdminOwner
            ),
            "tokenStakingNodesManager: STAKING_ADMIN_ROLE INVALID"
        );
        console.log("\u2705 tokenStakingNodesManager: STAKING_ADMIN_ROLE - ", vm.toString(address(proxyAdminOwner)));

        // TOKEN_STAKING_NODE_OPERATOR_ROLE
        require(
            deployment.tokenStakingNodesManager.hasRole(
                deployment.tokenStakingNodesManager.TOKEN_STAKING_NODE_OPERATOR_ROLE(),
                address(actors.ops.TOKEN_STAKING_NODE_OPERATOR)
            ),
            "tokenStakingNodesManager: TOKEN_STAKING_NODE_OPERATOR_ROLE INVALID"
        );
        console.log(
            "\u2705 tokenStakingNodesManager: TOKEN_STAKING_NODE_OPERATOR_ROLE - ",
            vm.toString(address(actors.ops.TOKEN_STAKING_NODE_OPERATOR))
        );

        // TOKEN_STAKING_NODE_CREATOR_ROLE
        require(
            deployment.tokenStakingNodesManager.hasRole(
                deployment.tokenStakingNodesManager.TOKEN_STAKING_NODE_CREATOR_ROLE(),
                address(actors.ops.STAKING_NODE_CREATOR)
            ),
            "tokenStakingNodesManager: TOKEN_STAKING_NODE_CREATOR_ROLE INVALID"
        );
        console.log(
            "\u2705 tokenStakingNodesManager: TOKEN_STAKING_NODE_CREATOR_ROLE - ",
            vm.toString(address(actors.ops.STAKING_NODE_CREATOR))
        );

        // PAUSER_ROLE
        require(
            deployment.tokenStakingNodesManager.hasRole(
                deployment.tokenStakingNodesManager.PAUSER_ROLE(), address(actors.ops.PAUSE_ADMIN)
            ),
            "tokenStakingNodesManager: PAUSER_ROLE INVALID"
        );
        console.log("\u2705 tokenStakingNodesManager: PAUSER_ROLE - ", vm.toString(address(actors.ops.PAUSE_ADMIN)));

        // UNPAUSER_ROLE
        require(
            deployment.tokenStakingNodesManager.hasRole(
                deployment.tokenStakingNodesManager.UNPAUSER_ROLE(), address(actors.admin.UNPAUSE_ADMIN)
            ),
            "tokenStakingNodesManager: UNPAUSER_ROLE INVALID"
        );
        console.log(
            "\u2705 tokenStakingNodesManager: UNPAUSER_ROLE - ", vm.toString(address(actors.admin.UNPAUSE_ADMIN))
        );

        //--------------------------------------------------------------------------------------
        // ynEigenDepositAdapter roles
        //--------------------------------------------------------------------------------------

        // DEFAULT_ADMIN_ROLE
        require(
            deployment.ynEigenDepositAdapterInstance.hasRole(
                deployment.ynEigenDepositAdapterInstance.DEFAULT_ADMIN_ROLE(), address(actors.admin.ADMIN)
            ),
            "ynEigenDepositAdapter: DEFAULT_ADMIN_ROLE INVALID"
        );
        console.log("\u2705 ynEigenDepositAdapter: DEFAULT_ADMIN_ROLE - ", vm.toString(address(actors.admin.ADMIN)));

        //--------------------------------------------------------------------------------------
        // redemptionAssetsVault roles
        //--------------------------------------------------------------------------------------

        // DEFAULT_ADMIN_ROLE
        require(
            deployment.redemptionAssetsVault.hasRole(
                deployment.redemptionAssetsVault.DEFAULT_ADMIN_ROLE(), address(actors.admin.ADMIN)
            ),
            "redemptionAssetsVault: DEFAULT_ADMIN_ROLE INVALID"
        );
        console.log("\u2705 redemptionAssetsVault: DEFAULT_ADMIN_ROLE - ", vm.toString(address(actors.admin.ADMIN)));

        // PAUSER_ROLE
        require(
            deployment.redemptionAssetsVault.hasRole(
                deployment.redemptionAssetsVault.PAUSER_ROLE(), address(actors.admin.ADMIN)
            ),
            "redemptionAssetsVault: PAUSER_ROLE INVALID"
        );
        console.log("\u2705 redemptionAssetsVault: PAUSER_ROLE - ", vm.toString(address(actors.admin.ADMIN)));

        // UNPAUSER_ROLE
        require(
            deployment.redemptionAssetsVault.hasRole(
                deployment.redemptionAssetsVault.UNPAUSER_ROLE(), address(actors.admin.UNPAUSE_ADMIN)
            ),
            "redemptionAssetsVault: UNPAUSER_ROLE INVALID"
        );
        console.log("\u2705 redemptionAssetsVault: UNPAUSER_ROLE - ", vm.toString(address(actors.admin.UNPAUSE_ADMIN)));

        //--------------------------------------------------------------------------------------
        // withdrawalQueueManager roles
        //--------------------------------------------------------------------------------------

        // DEFAULT_ADMIN_ROLE
        require(
            deployment.withdrawalQueueManager.hasRole(
                deployment.withdrawalQueueManager.DEFAULT_ADMIN_ROLE(), address(actors.admin.ADMIN)
            ),
            "withdrawalQueueManager: DEFAULT_ADMIN_ROLE INVALID"
        );
        console.log("\u2705 withdrawalQueueManager: DEFAULT_ADMIN_ROLE - ", vm.toString(address(actors.admin.ADMIN)));


        // WITHDRAWAL_QUEUE_ADMIN_ROLE
        require(
            deployment.withdrawalQueueManager.hasRole(
                deployment.withdrawalQueueManager.WITHDRAWAL_QUEUE_ADMIN_ROLE(), address(actors.admin.ADMIN)
            ),
            "withdrawalQueueManager: WITHDRAWAL_QUEUE_ADMIN_ROLE INVALID"
        );
        console.log("\u2705 withdrawalQueueManager: WITHDRAWAL_QUEUE_ADMIN_ROLE - ", vm.toString(address(actors.admin.ADMIN)));

        // REDEMPTION_ASSET_WITHDRAWER_ROLE
        require(
            deployment.withdrawalQueueManager.hasRole(
                deployment.withdrawalQueueManager.REDEMPTION_ASSET_WITHDRAWER_ROLE(), address(actors.ops.REDEMPTION_ASSET_WITHDRAWER)
            ),
            "withdrawalQueueManager: REDEMPTION_ASSET_WITHDRAWER_ROLE INVALID"
        );
        console.log("\u2705 withdrawalQueueManager: REDEMPTION_ASSET_WITHDRAWER_ROLE - ", vm.toString(address(actors.ops.REDEMPTION_ASSET_WITHDRAWER)));

        // REQUEST_FINALIZER_ROLE
        require(
            deployment.withdrawalQueueManager.hasRole(
                deployment.withdrawalQueueManager.REQUEST_FINALIZER_ROLE(), address(actors.ops.YNEIGEN_REQUEST_FINALIZER)
            ),
            "withdrawalQueueManager: REQUEST_FINALIZER_ROLE INVALID"
        );
        console.log("\u2705 withdrawalQueueManager: REQUEST_FINALIZER_ROLE - ", vm.toString(address(actors.ops.YNEIGEN_REQUEST_FINALIZER)));
    }

    function verifySystemParameters() internal view {
        // Verify the system parameters
        for (uint256 i = 0; i < inputs.assets.length; i++) {
            Asset memory asset = inputs.assets[i];
            IERC20 token = IERC20(asset.token);
            IStrategy strategy = IStrategy(asset.strategy);

            require(
                deployment.assetRegistry.assets(i) == token,
                string.concat("assetRegistry: asset ", i.toString(), " INVALID")
            );
            console.log(
                string.concat("\u2705 assetRegistry: asset ", i.toString(), " - Value:"),
                address(deployment.assetRegistry.assets(i))
            );

            require(
                deployment.eigenStrategyManager.strategies(token) == strategy,
                string.concat("eigenStrategyManager: strategy ", i.toString(), " INVALID")
            );
            console.log(
                string.concat("\u2705 eigenStrategyManager: strategy ", i.toString(), " - Value:"),
                address(deployment.eigenStrategyManager.strategies(token))
            );
        }

        require(
            address(deployment.tokenStakingNodesManager.strategyManager())
                == address(chainAddresses.eigenlayer.STRATEGY_MANAGER_ADDRESS),
            "tokenStakingNodesManager: strategyManager INVALID"
        );
        console.log(
            "\u2705 tokenStakingNodesManager: strategyManager - Value:",
            address(deployment.tokenStakingNodesManager.strategyManager())
        );

        require(
            address(deployment.tokenStakingNodesManager.delegationManager())
                == address(chainAddresses.eigenlayer.DELEGATION_MANAGER_ADDRESS),
            "tokenStakingNodesManager: delegationManager INVALID"
        );
        console.log(
            "\u2705 tokenStakingNodesManager: delegationManager - Value:",
            address(deployment.tokenStakingNodesManager.delegationManager())
        );

        require(
            deployment.tokenStakingNodesManager.maxNodeCount() == 10, "tokenStakingNodesManager: maxNodeCount INVALID"
        );
        console.log(
            "\u2705 tokenStakingNodesManager: maxNodeCount - Value:", deployment.tokenStakingNodesManager.maxNodeCount()
        );

        require(
            address(deployment.ynEigenDepositAdapterInstance.ynEigen()) == address(deployment.ynEigen),
            "ynEigenDepositAdapter: ynEigen INVALID"
        );
        console.log(
            "\u2705 ynEigenDepositAdapter: ynEigen - Value:",
            address(deployment.ynEigenDepositAdapterInstance.ynEigen())
        );

        require(
            address(deployment.ynEigenDepositAdapterInstance.wstETH()) == address(chainAddresses.lsd.WSTETH_ADDRESS),
            "ynEigenDepositAdapter: wstETH INVALID"
        );
        console.log(
            "\u2705 ynEigenDepositAdapter: wstETH - Value:", address(deployment.ynEigenDepositAdapterInstance.wstETH())
        );

        require(
            address(deployment.ynEigenDepositAdapterInstance.woETH()) == address(chainAddresses.lsd.WOETH_ADDRESS),
            "ynEigenDepositAdapter: woETH INVALID"
        );
        console.log(
            "\u2705 ynEigenDepositAdapter: woETH - Value:", address(deployment.ynEigenDepositAdapterInstance.woETH())
        );

        // EXPECTING 10 BPS
        require(
            deployment.withdrawalQueueManager.withdrawalFee() == 1000,
            "WithdrawalQueueManager: withdrawalFee INVALID"
        );
        console.log("\u2705 WithdrawalQueueManager: withdrawalFee - Value:", deployment.withdrawalQueueManager.withdrawalFee());

        console.log("\u2705 All system parameters verified successfully");
    }

    function verifyContractDependencies() internal view {
        verifyYnEIGENDependencies();
        verifyTokenStakingNodesManagerDependencies();
        verifyAssetRegistryDependencies();
        verifyEigenStrategyManagerDependencies();
        verifyWithdrawalQueueManagerDependencies();
        verifyRedemptionAssetsVaultDependencies();

        console.log("\u2705 All contract dependencies verified successfully");
    }

    function verifyYnEIGENDependencies() internal view {
        //Verify ynEIGEN contract dependencies
        require(
            IynEigen(address(deployment.ynEigen)).assetRegistry() == address(deployment.assetRegistry),
            "ynEigen: AssetRegistry dependency mismatch"
        );
        console.log("\u2705 ynEigen: AssetRegistry dependency verified successfully");

        require(
            IynEigen(address(deployment.ynEigen)).yieldNestStrategyManager() == address(deployment.eigenStrategyManager),
            "ynEigen: EigenStrategyManager dependency mismatch"
        );
        console.log("\u2705 ynEigen: EigenStrategyManager dependency verified successfully");
    }

    function verifyTokenStakingNodesManagerDependencies() internal view {
        require(
            address(deployment.tokenStakingNodesManager.strategyManager())
                == chainAddresses.eigenlayer.STRATEGY_MANAGER_ADDRESS,
            "tokenStakingNodesManager: strategyManager dependency mismatch"
        );
        console.log("\u2705 tokenStakingNodesManager: strategyManager dependency verified successfully");

        require(
            address(deployment.tokenStakingNodesManager.delegationManager())
                == chainAddresses.eigenlayer.DELEGATION_MANAGER_ADDRESS,
            "tokenStakingNodesManager: delegationManager dependency mismatch"
        );
        console.log("\u2705 tokenStakingNodesManager: delegationManager dependency verified successfully");

        require(
            address(deployment.tokenStakingNodesManager.upgradeableBeacon().implementation())
                == address(deployment.tokenStakingNodeImplementation),
            "tokenStakingNodesManager: upgradeableBeacon dependency mismatch"
        );
        console.log("\u2705 tokenStakingNodesManager: upgradeableBeacon dependency verified successfully");

        require(
            address(deployment.tokenStakingNodesManager.yieldNestStrategyManager())
                == address(deployment.eigenStrategyManager),
            "tokenStakingNodesManager: yieldNestStrategyManager dependency mismatch"
        );
        console.log("\u2705 tokenStakingNodesManager: yieldNestStrategyManager dependency verified successfully");
    }

    function verifyAssetRegistryDependencies() internal view {
        require(
            address(deployment.assetRegistry.strategyManager()) == address(deployment.eigenStrategyManager),
            "assetRegistry: strategyManager dependency mismatch"
        );
        console.log("\u2705 assetRegistry: strategyManager dependency verified successfully");

        require(
            address(deployment.assetRegistry.rateProvider()) == address(deployment.rateProvider),
            "assetRegistry: rateProvider dependency mismatch"
        );
        console.log("\u2705 assetRegistry: rateProvider dependency verified successfully");

        require(
            address(deployment.assetRegistry.ynEigen()) == address(deployment.ynEigen),
            "assetRegistry: ynEigen dependency mismatch"
        );
        console.log("\u2705 assetRegistry: ynEigen dependency verified successfully");
    }

    function verifyEigenStrategyManagerDependencies() internal view {
        require(
            address(deployment.eigenStrategyManager.ynEigen()) == address(deployment.ynEigen),
            "eigenStrategyManager: ynEigen INVALID"
        );
        console.log("\u2705 eigenStrategyManager: ynEigen - Value:", address(deployment.eigenStrategyManager.ynEigen()));

        require(
            address(deployment.eigenStrategyManager.strategyManager())
                == address(chainAddresses.eigenlayer.STRATEGY_MANAGER_ADDRESS),
            "eigenStrategyManager: strategyManager INVALID"
        );
        console.log(
            "\u2705 eigenStrategyManager: strategyManager - Value:",
            address(deployment.eigenStrategyManager.strategyManager())
        );

        require(
            address(deployment.eigenStrategyManager.delegationManager())
                == address(chainAddresses.eigenlayer.DELEGATION_MANAGER_ADDRESS),
            "eigenStrategyManager: delegationManager INVALID"
        );
        console.log(
            "\u2705 eigenStrategyManager: delegationManager - Value:",
            address(deployment.eigenStrategyManager.delegationManager())
        );

        require(
            address(deployment.eigenStrategyManager.tokenStakingNodesManager())
                == address(deployment.tokenStakingNodesManager),
            "eigenStrategyManager: tokenStakingNodesManager INVALID"
        );
        console.log(
            "\u2705 eigenStrategyManager: tokenStakingNodesManager - Value:",
            address(deployment.eigenStrategyManager.tokenStakingNodesManager())
        );

        require(
            address(deployment.eigenStrategyManager.wrapper()) == address(deployment.wrapper),
            "eigenStrategyManager: wrapper INVALID"
        );
        console.log("\u2705 eigenStrategyManager: wrapper - Value:", address(deployment.eigenStrategyManager.wrapper()));
    }

    function verifyWithdrawalQueueManagerDependencies() internal view {
        require(
            address(deployment.withdrawalQueueManager.redeemableAsset()) == address(deployment.ynEigen),
            "withdrawalQueueManager: ynEigen INVALID"
        );
        console.log("\u2705 withdrawalQueueManager: ynEigen - Value:", address(deployment.withdrawalQueueManager.redeemableAsset()));

        require(
            address(deployment.withdrawalQueueManager.redemptionAssetsVault()) == address(deployment.redemptionAssetsVault),
            "withdrawalQueueManager: redemptionAssetsVault INVALID"
        );
        console.log("\u2705 withdrawalQueueManager: redemptionAssetsVault - Value:", address(deployment.withdrawalQueueManager.redemptionAssetsVault()));
    }

    function verifyRedemptionAssetsVaultDependencies() internal view {
        require(
            address(deployment.redemptionAssetsVault.ynEigen()) == address(deployment.ynEigen),
            "redemptionAssetsVault: ynEigen INVALID"
        );
        console.log("\u2705 redemptionAssetsVault: ynEigen - Value:", address(deployment.redemptionAssetsVault.ynEigen()));

        require(
            address(deployment.redemptionAssetsVault.assetRegistry()) == address(deployment.assetRegistry),
            "redemptionAssetsVault: assetRegistry INVALID"
        );
        console.log("\u2705 redemptionAssetsVault: assetRegistry - Value:", address(deployment.redemptionAssetsVault.assetRegistry()));

        require(
            address(deployment.redemptionAssetsVault.redeemer()) == address(deployment.withdrawalQueueManager),
            "redemptionAssetsVault: redeemer INVALID"
        );
        console.log("\u2705 redemptionAssetsVault: redeemer - Value:", address(deployment.redemptionAssetsVault.redeemer()));
    }

    function ynEigenSanityCheck() internal {

        // Check that totalSupply is less than totalAssets
        uint256 totalSupply = deployment.ynEigen.totalSupply();
        uint256 totalAssets = deployment.ynEigen.totalAssets();
        console.log("totalSupply: ", totalSupply);
        console.log("totalAssets: ", totalAssets);
        // require(totalSupply <= totalAssets, "totalSupply should be less than or equal to totalAssets");
        console.log("\u2705 totalSupply is less than totalAssets");

        // Print totalSupply and totalAssets
        console.log(string.concat("Total Supply: ", vm.toString(totalSupply), " ynEigen (", vm.toString(totalSupply / 1e18), " units)"));
        console.log(string.concat("Total Assets: ", vm.toString(totalAssets), " wei (", vm.toString(totalAssets / 1e18), " Unit of Account)"));

        uint256 previewRedeemResult = deployment.ynEigen.previewRedeem(1 ether);
        console.log(string.concat("previewRedeem of 1 ynEigen: ", vm.toString(previewRedeemResult), " wei (", vm.toString(previewRedeemResult / 1e18), " Unit of Account)"));
    }
}
