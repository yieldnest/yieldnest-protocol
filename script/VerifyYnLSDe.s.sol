/// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import {ContractAddresses} from "./ContractAddresses.sol";
import {BaseYnEigenScript} from "./BaseYnEigenScript.s.sol";
// import { IEigenPodManager } from "lib/eigenlayer-contracts/src/contracts/interfaces/IEigenPodManager.sol";
// import {IStakingNode} from "src/interfaces/IStakingNode.sol";
// import {ProxyAdmin} from "lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {Utils} from "./Utils.sol";

import {ActorAddresses} from "./Actors.sol";
import {console} from "../lib/forge-std/src/console.sol";

// forge script script/VerifyYnLSDe.s.sol:VerifyYnLSDeScript --legacy --rpc-url https://ethereum-holesky-rpc.publicnode.com --broadcast

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
        // verifyContractDependencies();
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

    // {
    // "ADMIN": "0x743b91CDB1C694D4F51bCDA3a4A59DcC0d02b913",
    // "DEFAULT_SIGNER": "0x72fdBD51085bDa5eEEd3b55D1a46E2e92f0837a5",
    // "EIGEN_STRATEGY_ADMIN": "0x743b91CDB1C694D4F51bCDA3a4A59DcC0d02b913",
    // "PAUSE_ADMIN": "0x743b91CDB1C694D4F51bCDA3a4A59DcC0d02b913",
    // "PROXY_ADMIN_OWNER": "0x743b91CDB1C694D4F51bCDA3a4A59DcC0d02b913",
    // "STAKING_ADMIN": "0x743b91CDB1C694D4F51bCDA3a4A59DcC0d02b913",
    // "STAKING_NODES_OPERATOR": "0x9Dd8F69b62ddFd990241530F47dcEd0Dad7f7d39",
    // "STRATEGY_CONTROLLER": "0x1234567890123456789012345678901234567890",
    // "TOKEN_STAKING_NODE_CREATOR": "0x9Dd8F69b62ddFd990241530F47dcEd0Dad7f7d39",
    // "UNPAUSE_ADMIN": "0x743b91CDB1C694D4F51bCDA3a4A59DcC0d02b913",
    // "implementation-YnLSDe": "0xf59624D4Cb47A6470293E4A3a667614256C201b3",
    // "implementation-assetRegistry": "0x46ACFa9399b1AD9cE961A78B529Fe0B237653Dbd",
    // "implementation-eigenStrategyManager": "0x69D2C2606E967F82CDa5700A431958837e202596",
    // "implementation-tokenStakingNodesManager": "0x3afe56CAB25D9a999e8C9382563bfcb8B14aBf3D",
    // "implementation-ynEigenDepositAdapter": "0x271bC23121Df9cA87D9e93A66e8CcAD5EE8d4889",
    // "proxy-YnLSDe": "0x06422232DF6814153faA91eA4907bAA3B24c7A9E",
    // "proxy-assetRegistry": "0x1b6E84502C860393B3bc4575E80ba7490a992915",
    // "proxy-eigenStrategyManager": "0x95df255197efA88f2D44aa2356DEcf16066562CA",
    // "proxy-tokenStakingNodesManager": "0xd0B26346a0737c81Db6A354396f72D022646d29E",
    // "proxy-ynEigenDepositAdapter": "0xEe168c00969555cb7cb916588297BdD1B25687Ee",
    // "proxyAdmin-YnLSDe": "0xF4C5EAfE2b95ef970B26D78b024B184CcFB2E8ff",
    // "proxyAdmin-assetRegistry": "0x1597a4647df97Bc168527C282f0a2817CAF8242f",
    // "proxyAdmin-eigenStrategyManager": "0xE30e82D8b99688Ff08Ca6B998FbB25b9A04bfc34",
    // "proxyAdmin-tokenStakingNodesManager": "0x84fceB89720d9e2C88Deb7B918a83005Ba109e17",
    // "proxyAdmin-ynEigenDepositAdapter": "0xa304673979F66114e64a3680D9395A52c7218bC0",
    // "tokenStakingNodeImplementation": "0x8A96E90711669e68B6B879e9CeBE581e691b6861"
    // }
    // struct Deployment {
    //     ynEigen ynEigen;
    //     AssetRegistry assetRegistry;
    //     EigenStrategyManager eigenStrategyManager; todo
    //     TokenStakingNodesManager tokenStakingNodesManager; todo
    //     TokenStakingNode tokenStakingNodeImplementation; todo
    //     ynEigenDepositAdapter ynEigenDepositAdapterInstance; todo
    // }

    function verifySystemParameters() internal view {
        // Verify the system parameters
        require(
            deployment.ynEigen.assetRegistry() == address(deployment.assetRegistry),
            "ynETH: assetRegistry INVALID"
        );
        console.log("\u2705 ynETH: assetRegistry - Value:", deployment.ynEigen.assetRegistry());

        require(
            deployment.ynEigen.eigenStrategyManager() == address(deployment.eigenStrategyManager),
            "ynETH: eigenStrategyManager INVALID"
        );
        console.log("\u2705 ynETH: eigenStrategyManager - Value:", deployment.ynEigen.eigenStrategyManager());

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
            deployment.assetRegistry.rateProvider() == IRateProvider(chainAddresses.lsdRateProvider),
            "assetRegistry: rateProvider INVALID"
        );
        console.log("\u2705 assetRegistry: rateProvider - Value:", deployment.assetRegistry.rateProvider());

        require(
            deployment.assetRegistry.yieldNestStrategyManager() == IYieldNestStrategyManager(address(deployment.eigenStrategyManager)),
            "assetRegistry: yieldNestStrategyManager INVALID"
        );
        console.log("\u2705 assetRegistry: yieldNestStrategyManager - Value:", deployment.assetRegistry.yieldNestStrategyManager());

        require(
            deployment.assetRegistry.ynEigen() == IynEigen(address(deployment.ynEigen)),
            "assetRegistry: ynEigen INVALID"
        );
        console.log("\u2705 assetRegistry: ynEigen - Value:", deployment.assetRegistry.ynEigen());

        require(
            deployment.assetRegistry.assets(0) == assets[0],
            "assetRegistry: asset 0 INVALID"
        );
        console.log("\u2705 assetRegistry: asset 0 - Value:", deployment.assetRegistry.assets(0));

        require(
            deployment.assetRegistry.assets(1) == assets[1],
            "assetRegistry: asset 1 INVALID"
        );
        console.log("\u2705 assetRegistry: asset 1 - Value:", deployment.assetRegistry.assets(1));

        require(
            deployment.assetRegistry.assets(2) == assets[2],
            "assetRegistry: asset 2 INVALID"
        );
        console.log("\u2705 assetRegistry: asset 2 - Value:", deployment.assetRegistry.assets(2));

        require(
            deployment.assetRegistry.assets(3) == assets[3],
            "assetRegistry: asset 3 INVALID"
        );
        console.log("\u2705 assetRegistry: asset 3 - Value:", deployment.assetRegistry.assets(3));

        require(
            deployment.eigenStrategyManager.ynEigen() == IynEigen(address(deployment.ynEigen)),
            "eigenStrategyManager: ynEigen INVALID"
        );
        console.log("\u2705 eigenStrategyManager: ynEigen - Value:", deployment.eigenStrategyManager.ynEigen());

        require(
            deployment.eigenStrategyManager.strategyManager() == IStrategyManager(chainAddresses.eigenlayer.STRATEGY_MANAGER_ADDRESS),
            "eigenStrategyManager: strategyManager INVALID"
        );
        console.log("\u2705 eigenStrategyManager: strategyManager - Value:", deployment.eigenStrategyManager.strategyManager());

        require(
            deployment.eigenStrategyManager.delegationManager() == IDelegationManager(chainAddresses.eigenlayer.DELEGATION_MANAGER_ADDRESS),
            "eigenStrategyManager: delegationManager INVALID"
        );
        console.log("\u2705 eigenStrategyManager: delegationManager - Value:", deployment.eigenStrategyManager.delegationManager());

        require(
            deployment.eigenStrategyManager.tokenStakingNodesManager() == ITokenStakingNodesManager(address(deployment.tokenStakingNodesManager)),
            "eigenStrategyManager: tokenStakingNodesManager INVALID"
        );
        console.log("\u2705 eigenStrategyManager: tokenStakingNodesManager - Value:", deployment.eigenStrategyManager.tokenStakingNodesManager());

        require(
            deployment.eigenStrategyManager.wstETH() == IwstETH(chainAddresses.lsd.WSTETH_ADDRESS),
            "eigenStrategyManager: wstETH INVALID"
        );
        console.log("\u2705 eigenStrategyManager: wstETH - Value:", deployment.eigenStrategyManager.wstETH());

        require(
            deployment.eigenStrategyManager.woETH() == IERC4626(chainAddresses.lsd.WOETH_ADDRESS),
            "eigenStrategyManager: woETH INVALID"
        );
        console.log("\u2705 eigenStrategyManager: woETH - Value:", deployment.eigenStrategyManager.woETH());

        require(
            deployment.eigenStrategyManager.assets(0) == assets[0],
            "eigenStrategyManager: asset 0 INVALID"
        );
        console.log("\u2705 eigenStrategyManager: asset 0 - Value:", deployment.eigenStrategyManager.assets(0));

        require(
            deployment.eigenStrategyManager.assets(1) == assets[1],
            "eigenStrategyManager: asset 1 INVALID"
        );
        console.log("\u2705 eigenStrategyManager: asset 1 - Value:", deployment.eigenStrategyManager.assets(1));

        require(
            deployment.eigenStrategyManager.assets(2) == assets[2],
            "eigenStrategyManager: asset 2 INVALID"
        );
        console.log("\u2705 eigenStrategyManager: asset 2 - Value:", deployment.eigenStrategyManager.assets(2));

        require(
            deployment.eigenStrategyManager.assets(3) == assets[3],
            "eigenStrategyManager: asset 3 INVALID"
        );
        console.log("\u2705 eigenStrategyManager: asset 3 - Value:", deployment.eigenStrategyManager.assets(3));

        require(
            deployment.eigenStrategyManager.strategies(0) == strategies[0],
            "eigenStrategyManager: strategy 0 INVALID"
        );
        console.log("\u2705 eigenStrategyManager: strategy 0 - Value:", deployment.eigenStrategyManager.strategies(0));

        require(
            deployment.eigenStrategyManager.strategies(1) == strategies[1],
            "eigenStrategyManager: strategy 1 INVALID"
        );
        console.log("\u2705 eigenStrategyManager: strategy 1 - Value:", deployment.eigenStrategyManager.strategies(1));

        require(
            deployment.eigenStrategyManager.strategies(2) == strategies[2],
            "eigenStrategyManager: strategy 2 INVALID"
        );
        console.log("\u2705 eigenStrategyManager: strategy 2 - Value:", deployment.eigenStrategyManager.strategies(2));

        require(
            deployment.eigenStrategyManager.strategies(3) == strategies[3],
            "eigenStrategyManager: strategy 3 INVALID"
        );
        console.log("\u2705 eigenStrategyManager: strategy 3 - Value:", deployment.eigenStrategyManager.strategies(3));

        // tokenStakingNodesManager



        console.log("\u2705 All system parameters verified successfully");
    }

    function tokenName() internal override pure returns (string memory) {
        return "YnLSDe";
    }
}