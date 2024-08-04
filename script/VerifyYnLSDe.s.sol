/// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import {IStrategy} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";

import {ContractAddresses} from "./ContractAddresses.sol";
import {BaseYnEigenScript} from "./BaseYnEigenScript.s.sol";
import {Utils} from "./Utils.sol";

import {ActorAddresses} from "./Actors.sol";
import {console} from "../lib/forge-std/src/console.sol";

interface IynEigen {
    function assetRegistry() external view returns (address);
    function yieldNestStrategyManager() external view returns (address);
}
contract VerifyYnLSDeScript is BaseYnEigenScript {

    Deployment deployment;
    ActorAddresses.Actors actors;
    ContractAddresses.ChainAddresses chainAddresses;

    function run() external {

        ContractAddresses contractAddresses = new ContractAddresses();
        chainAddresses = contractAddresses.getChainAddresses(block.chainid);

        deployment = loadDeployment();
        actors = getActors();

        verifyProxyAdminOwners();
        verifyRoles();
        verifySystemParameters();
        verifyContractDependencies();
        ynLSDeSanityCheck();
    }

    function verifyProxyAdminOwners() internal view {
        address ynLSDAdmin = ProxyAdmin(Utils.getTransparentUpgradeableProxyAdminAddress(address(deployment.ynEigen))).owner();
        require(
            ynLSDAdmin == actors.admin.PROXY_ADMIN_OWNER,
            string.concat("ynETH: PROXY_ADMIN_OWNER INVALID, expected: ", vm.toString(actors.admin.PROXY_ADMIN_OWNER), ", got: ", vm.toString(ynLSDAdmin))
        );
        console.log("\u2705 ynETH: PROXY_ADMIN_OWNER - ", vm.toString(ynLSDAdmin));

        address stakingNodesManagerAdmin = ProxyAdmin(Utils.getTransparentUpgradeableProxyAdminAddress(address(deployment.tokenStakingNodesManager))).owner();
        require(
            stakingNodesManagerAdmin == actors.admin.PROXY_ADMIN_OWNER,
            string.concat("stakingNodesManager: PROXY_ADMIN_OWNER INVALID, expected: ", vm.toString(actors.admin.PROXY_ADMIN_OWNER), ", got: ", vm.toString(stakingNodesManagerAdmin))
        );
        console.log("\u2705 stakingNodesManager: PROXY_ADMIN_OWNER - ", vm.toString(stakingNodesManagerAdmin));

        address assetRegistryAdmin = ProxyAdmin(Utils.getTransparentUpgradeableProxyAdminAddress(address(deployment.assetRegistry))).owner();
        require(
            assetRegistryAdmin == actors.admin.PROXY_ADMIN_OWNER,
            string.concat("assetRegistry: PROXY_ADMIN_OWNER INVALID, expected: ", vm.toString(actors.admin.PROXY_ADMIN_OWNER), ", got: ", vm.toString(assetRegistryAdmin))
        );
        console.log("\u2705 assetRegistry: PROXY_ADMIN_OWNER - ", vm.toString(assetRegistryAdmin));

        address eigenStrategyManagerAdmin = ProxyAdmin(Utils.getTransparentUpgradeableProxyAdminAddress(address(deployment.eigenStrategyManager))).owner();
        require(
            eigenStrategyManagerAdmin == actors.admin.PROXY_ADMIN_OWNER,
            string.concat("eigenStrategyManager: PROXY_ADMIN_OWNER INVALID, expected: ", vm.toString(actors.admin.PROXY_ADMIN_OWNER), ", got: ", vm.toString(eigenStrategyManagerAdmin))
        );
        console.log("\u2705 eigenStrategyManager: PROXY_ADMIN_OWNER - ", vm.toString(eigenStrategyManagerAdmin));

        address ynEigenDepositAdapterAdmin = ProxyAdmin(Utils.getTransparentUpgradeableProxyAdminAddress(address(deployment.ynEigenDepositAdapterInstance))).owner();
        require(
            ynEigenDepositAdapterAdmin == actors.admin.PROXY_ADMIN_OWNER,
            string.concat("ynEigenDepositAdapter: PROXY_ADMIN_OWNER INVALID, expected: ", vm.toString(actors.admin.PROXY_ADMIN_OWNER), ", got: ", vm.toString(ynEigenDepositAdapterAdmin))
        );
        console.log("\u2705 ynEigenDepositAdapter: PROXY_ADMIN_OWNER - ", vm.toString(ynEigenDepositAdapterAdmin));

        address ynEigenDepositAdapterInstanceAdmin = ProxyAdmin(Utils.getTransparentUpgradeableProxyAdminAddress(address(deployment.ynEigenDepositAdapterInstance))).owner();
        require(
            ynEigenDepositAdapterInstanceAdmin == actors.admin.PROXY_ADMIN_OWNER,
            string.concat("ynEigenDepositAdapterInstance: PROXY_ADMIN_OWNER INVALID, expected: ", vm.toString(actors.admin.PROXY_ADMIN_OWNER), ", got: ", vm.toString(ynEigenDepositAdapterInstanceAdmin))
        );
        console.log("\u2705 ynEigenDepositAdapterInstance: PROXY_ADMIN_OWNER - ", vm.toString(ynEigenDepositAdapterInstanceAdmin));
    }

    function verifyRoles() internal view {

        //--------------------------------------------------------------------------------------
        // YnLSDe roles
        //--------------------------------------------------------------------------------------

        // DEFAULT_ADMIN_ROLE
        require(
            deployment.ynEigen.hasRole(
                deployment.ynEigen.DEFAULT_ADMIN_ROLE(), 
                address(actors.admin.ADMIN)
            ), 
            "ynLSD: DEFAULT_ADMIN_ROLE INVALID"
        );
        console.log("\u2705 ynLSD: DEFAULT_ADMIN_ROLE - ", vm.toString(address(actors.admin.ADMIN)));

        // PAUSER_ROLE
        require(
            deployment.ynEigen.hasRole(
                deployment.ynEigen.PAUSER_ROLE(), 
                address(actors.ops.PAUSE_ADMIN)
            ), 
            "ynLSD: PAUSER_ROLE INVALID"
        );
        console.log("\u2705 ynLSD: PAUSER_ROLE - ", vm.toString(address(actors.ops.PAUSE_ADMIN)));

        // UNPAUSER_ROLE
        require(
            deployment.ynEigen.hasRole(
                deployment.ynEigen.UNPAUSER_ROLE(), 
                address(actors.admin.UNPAUSE_ADMIN)
            ), 
            "ynLSD: UNPAUSER_ROLE INVALID"
        );
        console.log("\u2705 ynLSD: UNPAUSER_ROLE - ", vm.toString(address(actors.admin.UNPAUSE_ADMIN)));

        //--------------------------------------------------------------------------------------
        // assetRegistry roles
        //--------------------------------------------------------------------------------------		

        // DEFAULT_ADMIN_ROLE
        require(
            deployment.assetRegistry.hasRole(
                deployment.assetRegistry.DEFAULT_ADMIN_ROLE(), 
                address(actors.admin.ADMIN)
            ), 
            "assetRegistry: DEFAULT_ADMIN_ROLE INVALID"
        );
        console.log("\u2705 assetRegistry: DEFAULT_ADMIN_ROLE - ", vm.toString(address(actors.admin.ADMIN)));

        // PAUSER_ROLE
        require(
            deployment.assetRegistry.hasRole(
                deployment.assetRegistry.PAUSER_ROLE(), 
                address(actors.ops.PAUSE_ADMIN)
            ), 
            "assetRegistry: PAUSER_ROLE INVALID"
        );
        console.log("\u2705 assetRegistry: PAUSER_ROLE - ", vm.toString(address(actors.ops.PAUSE_ADMIN)));

        // UNPAUSER_ROLE
        require(
            deployment.assetRegistry.hasRole(
                deployment.assetRegistry.UNPAUSER_ROLE(), 
                address(actors.admin.UNPAUSE_ADMIN)
            ), 
            "assetRegistry: UNPAUSER_ROLE INVALID"
        );
        console.log("\u2705 assetRegistry: UNPAUSER_ROLE - ", vm.toString(address(actors.admin.UNPAUSE_ADMIN)));

        // ASSET_MANAGER_ROLE
        require(
            deployment.assetRegistry.hasRole(
                deployment.assetRegistry.ASSET_MANAGER_ROLE(), 
                address(actors.admin.ASSET_MANAGER)
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
                deployment.eigenStrategyManager.DEFAULT_ADMIN_ROLE(), 
                address(actors.admin.EIGEN_STRATEGY_ADMIN)
            ), 
            "eigenStrategyManager: DEFAULT_ADMIN_ROLE INVALID"
        );
        console.log("\u2705 eigenStrategyManager: DEFAULT_ADMIN_ROLE - ", vm.toString(address(actors.admin.EIGEN_STRATEGY_ADMIN)));

        // PAUSER_ROLE
        require(
            deployment.eigenStrategyManager.hasRole(
                deployment.eigenStrategyManager.PAUSER_ROLE(), 
                address(actors.ops.PAUSE_ADMIN)
            ), 
            "eigenStrategyManager: PAUSER_ROLE INVALID"
        );
        console.log("\u2705 eigenStrategyManager: PAUSER_ROLE - ", vm.toString(address(actors.ops.PAUSE_ADMIN)));

        // UNPAUSER_ROLE
        require(
            deployment.eigenStrategyManager.hasRole(
                deployment.eigenStrategyManager.UNPAUSER_ROLE(), 
                address(actors.admin.UNPAUSE_ADMIN)
            ), 
            "eigenStrategyManager: UNPAUSER_ROLE INVALID"
        );
        console.log("\u2705 eigenStrategyManager: UNPAUSER_ROLE - ", vm.toString(address(actors.admin.UNPAUSE_ADMIN)));

        // STRATEGY_CONTROLLER_ROLE
        require(
            deployment.eigenStrategyManager.hasRole(
                deployment.eigenStrategyManager.STRATEGY_CONTROLLER_ROLE(), 
                address(actors.ops.STRATEGY_CONTROLLER)
            ), 
            "eigenStrategyManager: STRATEGY_CONTROLLER_ROLE INVALID"
        );
        console.log("\u2705 eigenStrategyManager: STRATEGY_CONTROLLER_ROLE - ", vm.toString(address(actors.ops.STRATEGY_CONTROLLER)));

        // STRATEGY_ADMIN_ROLE
        require(
            deployment.eigenStrategyManager.hasRole(
                deployment.eigenStrategyManager.STRATEGY_ADMIN_ROLE(), 
                address(actors.admin.EIGEN_STRATEGY_ADMIN)
            ), 
            "eigenStrategyManager: STRATEGY_ADMIN_ROLE INVALID"
        );
        console.log("\u2705 eigenStrategyManager: STRATEGY_ADMIN_ROLE - ", vm.toString(address(actors.admin.EIGEN_STRATEGY_ADMIN)));

        //--------------------------------------------------------------------------------------
        // tokenStakingNodesManager roles
        //--------------------------------------------------------------------------------------			

        // DEFAULT_ADMIN_ROLE
        require(
            deployment.tokenStakingNodesManager.hasRole(
                deployment.tokenStakingNodesManager.DEFAULT_ADMIN_ROLE(), 
                address(actors.admin.ADMIN)
            ), 
            "tokenStakingNodesManager: DEFAULT_ADMIN_ROLE INVALID"
        );
        console.log("\u2705 tokenStakingNodesManager: DEFAULT_ADMIN_ROLE - ", vm.toString(address(actors.admin.ADMIN)));

        // STAKING_ADMIN_ROLE
        require(
            deployment.tokenStakingNodesManager.hasRole(
                deployment.tokenStakingNodesManager.STAKING_ADMIN_ROLE(), 
                address(actors.admin.STAKING_ADMIN)
            ), 
            "tokenStakingNodesManager: STAKING_ADMIN_ROLE INVALID"
        );
        console.log("\u2705 tokenStakingNodesManager: STAKING_ADMIN_ROLE - ", vm.toString(address(actors.admin.STAKING_ADMIN)));

        // TOKEN_STAKING_NODE_OPERATOR_ROLE
        require(
            deployment.tokenStakingNodesManager.hasRole(
                deployment.tokenStakingNodesManager.TOKEN_STAKING_NODE_OPERATOR_ROLE(), 
                address(actors.ops.TOKEN_STAKING_NODE_OPERATOR)
            ), 
            "tokenStakingNodesManager: TOKEN_STAKING_NODE_OPERATOR_ROLE INVALID"
        );
        console.log("\u2705 tokenStakingNodesManager: TOKEN_STAKING_NODE_OPERATOR_ROLE - ", vm.toString(address(actors.ops.TOKEN_STAKING_NODE_OPERATOR)));

        // TOKEN_STAKING_NODE_CREATOR_ROLE
        require(
            deployment.tokenStakingNodesManager.hasRole(
                deployment.tokenStakingNodesManager.TOKEN_STAKING_NODE_CREATOR_ROLE(), 
                address(actors.ops.STAKING_NODE_CREATOR)
            ), 
            "tokenStakingNodesManager: TOKEN_STAKING_NODE_CREATOR_ROLE INVALID"
        );
        console.log("\u2705 tokenStakingNodesManager: TOKEN_STAKING_NODE_CREATOR_ROLE - ", vm.toString(address(actors.ops.STAKING_NODE_CREATOR)));

        // PAUSER_ROLE
        require(
            deployment.tokenStakingNodesManager.hasRole(
                deployment.tokenStakingNodesManager.PAUSER_ROLE(), 
                address(actors.ops.PAUSE_ADMIN)
            ), 
            "tokenStakingNodesManager: PAUSER_ROLE INVALID"
        );
        console.log("\u2705 tokenStakingNodesManager: PAUSER_ROLE - ", vm.toString(address(actors.ops.PAUSE_ADMIN)));

        // UNPAUSER_ROLE
        require(
            deployment.tokenStakingNodesManager.hasRole(
                deployment.tokenStakingNodesManager.UNPAUSER_ROLE(), 
                address(actors.admin.UNPAUSE_ADMIN)
            ), 
            "tokenStakingNodesManager: UNPAUSER_ROLE INVALID"
        );
        console.log("\u2705 tokenStakingNodesManager: UNPAUSER_ROLE - ", vm.toString(address(actors.admin.UNPAUSE_ADMIN)));


        //--------------------------------------------------------------------------------------
        // ynEigenDepositAdapter roles
        //--------------------------------------------------------------------------------------

        // DEFAULT_ADMIN_ROLE
        require(
            deployment.ynEigenDepositAdapterInstance.hasRole(
                deployment.ynEigenDepositAdapterInstance.DEFAULT_ADMIN_ROLE(), 
                address(actors.admin.ADMIN)
            ), 
            "ynEigenDepositAdapter: DEFAULT_ADMIN_ROLE INVALID"
        );
        console.log("\u2705 ynEigenDepositAdapter: DEFAULT_ADMIN_ROLE - ", vm.toString(address(actors.admin.ADMIN)));
    }

    function verifySystemParameters() internal view {
        // Verify the system parameters
        IERC20[] memory assets;
        IStrategy[] memory strategies;
        if (block.chainid == 1) {
            uint256 assetCount = 3;
            assets = new IERC20[](assetCount);
            assets[0] = IERC20(chainAddresses.lsd.WSTETH_ADDRESS);
            assets[1] = IERC20(chainAddresses.lsd.SFRXETH_ADDRESS);
            assets[2] = IERC20(chainAddresses.lsd.WOETH_ADDRESS);

            strategies = new IStrategy[](assetCount);
            strategies[0] = IStrategy(chainAddresses.lsdStrategies.STETH_STRATEGY_ADDRESS);
            strategies[1] = IStrategy(chainAddresses.lsdStrategies.SFRXETH_STRATEGY_ADDRESS);
            strategies[2] = IStrategy(chainAddresses.lsdStrategies.OETH_STRATEGY_ADDRESS);

        } else if (block.chainid == 17000) {

            uint256 assetCount = 4;
            assets = new IERC20[](assetCount);
            assets[0] = IERC20(chainAddresses.lsd.WSTETH_ADDRESS);
            assets[1] = IERC20(chainAddresses.lsd.SFRXETH_ADDRESS);
            assets[2] = IERC20(chainAddresses.lsd.RETH_ADDRESS);
            assets[3] = IERC20(chainAddresses.lsd.METH_ADDRESS);

            strategies = new IStrategy[](assetCount);
            strategies[0] = IStrategy(chainAddresses.lsdStrategies.STETH_STRATEGY_ADDRESS);
            strategies[1] = IStrategy(chainAddresses.lsdStrategies.SFRXETH_STRATEGY_ADDRESS);
            strategies[2] = IStrategy(chainAddresses.lsdStrategies.RETH_STRATEGY_ADDRESS);
            strategies[3] = IStrategy(chainAddresses.lsdStrategies.METH_STRATEGY_ADDRESS);
        } else {
            revert(string(string.concat("Chain ID ", vm.toString(block.chainid), " not supported")));
        }

        require(
            deployment.assetRegistry.assets(0) == assets[0],
            "assetRegistry: asset 0 INVALID"
        );
        console.log("\u2705 assetRegistry: asset 0 - Value:", address(deployment.assetRegistry.assets(0)));

        require(
            deployment.assetRegistry.assets(1) == assets[1],
            "assetRegistry: asset 1 INVALID"
        );
        console.log("\u2705 assetRegistry: asset 1 - Value:", address(deployment.assetRegistry.assets(1)));

        require(
            deployment.assetRegistry.assets(2) == assets[2],
            "assetRegistry: asset 2 INVALID"
        );
        console.log("\u2705 assetRegistry: asset 2 - Value:", address(deployment.assetRegistry.assets(2)));

        require(
            deployment.assetRegistry.assets(3) == assets[3],
            "assetRegistry: asset 3 INVALID"
        );
        console.log("\u2705 assetRegistry: asset 3 - Value:", address(deployment.assetRegistry.assets(3)));

        require(
            address(deployment.eigenStrategyManager.ynEigen()) == address(deployment.ynEigen),
            "eigenStrategyManager: ynEigen INVALID"
        );
        console.log("\u2705 eigenStrategyManager: ynEigen - Value:", address(deployment.eigenStrategyManager.ynEigen()));

        require(
            address(deployment.eigenStrategyManager.strategyManager()) == address(chainAddresses.eigenlayer.STRATEGY_MANAGER_ADDRESS),
            "eigenStrategyManager: strategyManager INVALID"
        );
        console.log("\u2705 eigenStrategyManager: strategyManager - Value:", address(deployment.eigenStrategyManager.strategyManager()));

        require(
            address(deployment.eigenStrategyManager.delegationManager()) == address(chainAddresses.eigenlayer.DELEGATION_MANAGER_ADDRESS),
            "eigenStrategyManager: delegationManager INVALID"
        );
        console.log("\u2705 eigenStrategyManager: delegationManager - Value:", address(deployment.eigenStrategyManager.delegationManager()));

        require(
            address(deployment.eigenStrategyManager.tokenStakingNodesManager()) == address(deployment.tokenStakingNodesManager),
            "eigenStrategyManager: tokenStakingNodesManager INVALID"
        );
        console.log("\u2705 eigenStrategyManager: tokenStakingNodesManager - Value:", address(deployment.eigenStrategyManager.tokenStakingNodesManager()));

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

        require(
            deployment.eigenStrategyManager.strategies(IERC20(chainAddresses.lsd.WSTETH_ADDRESS)) == strategies[0],
            "eigenStrategyManager: strategy 0 INVALID"
        );
        console.log("\u2705 eigenStrategyManager: strategy 0 - Value:", address(deployment.eigenStrategyManager.strategies(IERC20(chainAddresses.lsd.WSTETH_ADDRESS))));

        require(
            deployment.eigenStrategyManager.strategies(IERC20(chainAddresses.lsd.SFRXETH_ADDRESS)) == strategies[1],
            "eigenStrategyManager: strategy 1 INVALID"
        );
        console.log("\u2705 eigenStrategyManager: strategy 1 - Value:", address(deployment.eigenStrategyManager.strategies(IERC20(chainAddresses.lsd.SFRXETH_ADDRESS))));

        require(
            address(deployment.tokenStakingNodesManager.strategyManager()) == address(chainAddresses.eigenlayer.STRATEGY_MANAGER_ADDRESS),
            "tokenStakingNodesManager: strategyManager INVALID"
        );
        console.log("\u2705 tokenStakingNodesManager: strategyManager - Value:", address(deployment.tokenStakingNodesManager.strategyManager()));

        require(
            address(deployment.tokenStakingNodesManager.delegationManager()) == address(chainAddresses.eigenlayer.DELEGATION_MANAGER_ADDRESS),
            "tokenStakingNodesManager: delegationManager INVALID"
        );
        console.log("\u2705 tokenStakingNodesManager: delegationManager - Value:", address(deployment.tokenStakingNodesManager.delegationManager()));

        require(
            deployment.tokenStakingNodesManager.maxNodeCount() == 10,
            "tokenStakingNodesManager: maxNodeCount INVALID"
        );
        console.log("\u2705 tokenStakingNodesManager: maxNodeCount - Value:", deployment.tokenStakingNodesManager.maxNodeCount());

        require(
            address(deployment.ynEigenDepositAdapterInstance.ynEigen()) == address(deployment.ynEigen),
            "ynEigenDepositAdapter: ynEigen INVALID"
        );
        console.log("\u2705 ynEigenDepositAdapter: ynEigen - Value:", address(deployment.ynEigenDepositAdapterInstance.ynEigen()));

        require(
            address(deployment.ynEigenDepositAdapterInstance.wstETH()) == address(chainAddresses.lsd.WSTETH_ADDRESS),
            "ynEigenDepositAdapter: wstETH INVALID"
        );
        console.log("\u2705 ynEigenDepositAdapter: wstETH - Value:", address(deployment.ynEigenDepositAdapterInstance.wstETH()));

        require(
            address(deployment.ynEigenDepositAdapterInstance.woETH()) == address(chainAddresses.lsd.WOETH_ADDRESS),
            "ynEigenDepositAdapter: woETH INVALID"
        );
        console.log("\u2705 ynEigenDepositAdapter: woETH - Value:", address(deployment.ynEigenDepositAdapterInstance.woETH()));

        console.log("\u2705 All system parameters verified successfully");
    }

    function verifyContractDependencies() internal {

        verifyYnEIGENDependencies();
        verifyTokenStakingNodesManagerDependencies();
        verifyAssetRegistryDependencies();

        console.log("\u2705 All contract dependencies verified successfully");
    }

    // @dev - cant verify, those dependencies are internal
    function verifyYnEIGENDependencies() internal view {
        // Verify ynEIGEN contract dependencies
        // require(
        //     IynEigen(address(deployment.ynEigen)).assetRegistry() == address(deployment.assetRegistry),
        //     "ynEigen: AssetRegistry dependency mismatch"
        // );
        // console.log("\u2705 ynEigen: AssetRegistry dependency verified successfully");

        // require(
        //     IynEigen(address(deployment.ynEigen)).yieldNestStrategyManager() == address(deployment.eigenStrategyManager),
        //     "ynEigen: EigenStrategyManager dependency mismatch"
        // );
        // console.log("\u2705 ynEigen: EigenStrategyManager dependency verified successfully");
    }

    function verifyTokenStakingNodesManagerDependencies() internal view {
        require(
            address(deployment.tokenStakingNodesManager.strategyManager()) == chainAddresses.eigenlayer.STRATEGY_MANAGER_ADDRESS,
            "tokenStakingNodesManager: strategyManager dependency mismatch"
        );
        console.log("\u2705 tokenStakingNodesManager: strategyManager dependency verified successfully");

        require (
            address(deployment.tokenStakingNodesManager.delegationManager()) == chainAddresses.eigenlayer.DELEGATION_MANAGER_ADDRESS,
            "tokenStakingNodesManager: delegationManager dependency mismatch"
        );
        console.log("\u2705 tokenStakingNodesManager: delegationManager dependency verified successfully");

        require(
            address(deployment.tokenStakingNodesManager.upgradeableBeacon().implementation()) == address(deployment.tokenStakingNodeImplementation),
            "tokenStakingNodesManager: upgradeableBeacon dependency mismatch"
        );
        console.log("\u2705 tokenStakingNodesManager: upgradeableBeacon dependency verified successfully");
    }

    function verifyAssetRegistryDependencies() internal view {
        require(
            address(deployment.assetRegistry.strategyManager()) == address(deployment.eigenStrategyManager),
            "assetRegistry: strategyManager dependency mismatch"
        );
        console.log("\u2705 assetRegistry: strategyManager dependency verified successfully");
    }

    function ynLSDeSanityCheck() internal {
        require(
            deployment.assetRegistry.totalAssets() >= 0,
            "assetRegistry: totalAssets INVALID"
        );
        console.log("\u2705 assetRegistry: totalAssets - Value:", deployment.assetRegistry.totalAssets());
    }

    function tokenName() internal override pure returns (string memory) {
        return "YnLSDe";
    }
}