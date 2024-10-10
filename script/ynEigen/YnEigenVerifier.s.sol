/// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {IStrategy} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";

import {BaseYnEigenScript} from "script/ynEigen/BaseYnEigenScript.s.sol";
import {Utils} from "script/Utils.sol";

import {console} from "lib/forge-std/src/console.sol";

interface IynEigen {
    function assetRegistry() external view returns (address);
    function yieldNestStrategyManager() external view returns (address);
}

contract YnEigenVerifier is BaseYnEigenScript {
    Deployment private deployment;

    using Strings for uint256;

    function _verify() internal {
        deployment = loadDeployment();

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
        // YnEigene roles
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

        console.log("\u2705 All system parameters verified successfully");
    }

    function verifyContractDependencies() internal view {
        verifyYnEIGENDependencies();
        verifyTokenStakingNodesManagerDependencies();
        verifyAssetRegistryDependencies();
        verifyEigenStrategyManagerDependencies();

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
            address(deployment.eigenStrategyManager.wstETH()) == address(chainAddresses.lsd.WSTETH_ADDRESS),
            "eigenStrategyManager: wstETH INVALID"
        );
        console.log("\u2705 eigenStrategyManager: wstETH - Value:", address(deployment.eigenStrategyManager.wstETH()));

        require(
            address(deployment.eigenStrategyManager.woETH()) == address(chainAddresses.lsd.WOETH_ADDRESS),
            "eigenStrategyManager: woETH INVALID"
        );
        console.log("\u2705 eigenStrategyManager: woETH - Value:", address(deployment.eigenStrategyManager.woETH()));
    }

    function ynEigenSanityCheck() internal {
        require(deployment.assetRegistry.totalAssets() >= 0, "assetRegistry: totalAssets INVALID");
        console.log("\u2705 assetRegistry: totalAssets - Value:", deployment.assetRegistry.totalAssets());
    }
}
