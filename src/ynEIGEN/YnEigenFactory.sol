// SPDX-License-Identifier: BSD-3-Clause License
pragma solidity ^0.8.24;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {TransparentUpgradeableProxy} from
    "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IDelegationManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategyManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IStrategy} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";

import {ITokenStakingNodesManager} from "src/interfaces/ITokenStakingNodesManager.sol";

import {IynEigen} from "src/interfaces/IynEigen.sol";
import {IRateProvider} from "src/interfaces/IRateProvider.sol";
import {IAssetRegistry} from "src/interfaces/IAssetRegistry.sol";
import {IYieldNestStrategyManager} from "src/interfaces/IYieldNestStrategyManager.sol";
import {ynEigen} from "src/ynEIGEN/ynEigen.sol";
import {TokenStakingNode} from "src/ynEIGEN/TokenStakingNode.sol";
import {EigenStrategyManager} from "src/ynEIGEN/EigenStrategyManager.sol";
import {AssetRegistry} from "src/ynEIGEN/AssetRegistry.sol";
import {TokenStakingNodesManager} from "src/ynEIGEN/TokenStakingNodesManager.sol";
import {ynEigenDepositAdapter} from "src/ynEIGEN/ynEigenDepositAdapter.sol";
import {ynEigenViewer} from "src/ynEIGEN/ynEigenViewer.sol";

import {IwstETH} from "src/external/lido/IwstETH.sol";
import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";

/// @notice Actors involved in the contract with specific roles.
struct YnEigenActors {
    address ADMIN;
    address PAUSE_ADMIN;
    address UNPAUSE_ADMIN;
    address STAKING_NODES_DELEGATOR_ADMIN;
    address ASSET_MANAGER_ADMIN;
    address EIGEN_STRATEGY_ADMIN;
    address STAKING_NODE_CREATOR;
    address STRATEGY_CONTROLLER;
    address TOKEN_STAKING_NODE_OPERATOR;
    address YN_SECURITY_COUNCIL;
}

/// @notice Addresses of external contracts on the chain.
struct YnEigenChainAddresses {
    address WSTETH_ADDRESS;
    address WOETH_ADDRESS;
    address STRATEGY_MANAGER;
    address DELEGATION_MANAGER;
}

/// @notice Initialization parameters for deploying YnEigen contracts.
struct YnEigenInit {
    string name;
    string symbol;
    uint256 timeLockDelay;
    uint256 maxNodeCount;
    address rateProviderImplementation;
    IERC20[] assets;
    IStrategy[] strategies;
    YnEigenActors actors;
    YnEigenChainAddresses chainAddresses;
}

/**
 * @title YnEigenFactorySignals
 * @dev Interface for signaling errors and events in the YnEigenFactory contract.
 */
interface IYnEigenFactory {
    // Events
    event YnEigenDeployed(
        ynEigen ynEigen,
        EigenStrategyManager eigenStrategyManager,
        TokenStakingNodesManager tokenStakingNodesManager,
        TokenStakingNode tokenStakingNode,
        AssetRegistry assetRegistry,
        ynEigenDepositAdapter ynEigenDepositAdapter,
        IRateProvider rateProvider,
        TimelockController timelock,
        ynEigenViewer viewer
    );
}

library ynEigenFactoryInitValidator {
    // Errors
    error InvalidAssetsLength();
    error InvalidAsset(uint256 index);
    error InvalidStrategy(uint256 index);
    error InvalidWstETHAddress();
    error InvalidWoETHAddress();
    error InvalidStrategyManager();
    error InvalidDelegationManager();
    error InvalidName();
    error InvalidSymbol();
    error InvalidTimeLockDelay();
    error InvalidMaxNodeCount();
    error InvalidRateProviderImplementation();
    error InvalidAdmin();
    error InvalidPauseAdmin();
    error InvalidUnpauseAdmin();
    error InvalidStakingNodesDelegatorAdmin();
    error InvalidAssetManagerAdmin();
    error InvalidEigenStrategyAdmin();
    error InvalidStakingNodeCreator();
    error InvalidStrategyController();
    error InvalidTokenStakingNodeOperator();
    error InvalidYNSecurityCouncil();

    /**
     * @dev Internal function to validate chain addresses.
     * @param chainAddresses The ChainAddresses struct to validate.
     */
    function _validateChainAddresses(YnEigenChainAddresses calldata chainAddresses) internal pure {
        if (chainAddresses.WSTETH_ADDRESS == address(0)) {
            revert InvalidWstETHAddress();
        }
        if (chainAddresses.WOETH_ADDRESS == address(0)) {
            revert InvalidWoETHAddress();
        }
        if (chainAddresses.STRATEGY_MANAGER == address(0)) {
            revert InvalidStrategyManager();
        }
        if (chainAddresses.DELEGATION_MANAGER == address(0)) {
            revert InvalidDelegationManager();
        }
    }

    /**
     * @dev Internal function to validate actor addresses.
     * @param actors The Actors struct to validate.
     */
    function _validateActors(YnEigenActors calldata actors) internal pure {
        if (actors.ADMIN == address(0)) {
            revert InvalidAdmin();
        }
        if (actors.PAUSE_ADMIN == address(0)) {
            revert InvalidPauseAdmin();
        }
        if (actors.UNPAUSE_ADMIN == address(0)) {
            revert InvalidUnpauseAdmin();
        }
        if (actors.STAKING_NODES_DELEGATOR_ADMIN == address(0)) {
            revert InvalidStakingNodesDelegatorAdmin();
        }
        if (actors.ASSET_MANAGER_ADMIN == address(0)) {
            revert InvalidAssetManagerAdmin();
        }
        if (actors.EIGEN_STRATEGY_ADMIN == address(0)) {
            revert InvalidEigenStrategyAdmin();
        }
        if (actors.STAKING_NODE_CREATOR == address(0)) {
            revert InvalidStakingNodeCreator();
        }
        if (actors.STRATEGY_CONTROLLER == address(0)) {
            revert InvalidStrategyController();
        }
        if (actors.TOKEN_STAKING_NODE_OPERATOR == address(0)) {
            revert InvalidTokenStakingNodeOperator();
        }
        if (actors.YN_SECURITY_COUNCIL == address(0)) {
            revert InvalidYNSecurityCouncil();
        }
    }

    /**
     * @dev Internal function to validate initialization parameters.
     * @param init The YnEigenInit struct to validate.
     */
    function validate(YnEigenInit calldata init) internal pure {
        if (bytes(init.name).length == 0) {
            revert InvalidName();
        }
        if (bytes(init.symbol).length == 0) {
            revert InvalidSymbol();
        }
        if (init.timeLockDelay == 0) {
            revert InvalidTimeLockDelay();
        }
        if (init.maxNodeCount == 0) {
            revert InvalidMaxNodeCount();
        }
        if (init.rateProviderImplementation == address(0)) {
            revert InvalidRateProviderImplementation();
        }
        if (init.assets.length == 0) {
            revert InvalidAssetsLength();
        }
        if (init.assets.length != init.strategies.length) {
            revert InvalidAssetsLength();
        }
        for (uint256 i = 0; i < init.assets.length; i++) {
            if (address(init.assets[i]) == address(0)) {
                revert InvalidAsset(i);
            }
            if (address(init.strategies[i]) == address(0)) {
                revert InvalidStrategy(i);
            }
        }
        _validateActors(init.actors);
        _validateChainAddresses(init.chainAddresses);
    }
}

/**
 * @title YnEigenFactory
 * @dev Factory contract to deploy and manage YnEigen-related contracts.
 */
contract YnEigenFactory is IYnEigenFactory {
    /**
     * @dev Internal function to deploy a TransparentUpgradeableProxy.
     * @param implementation The address of the implementation contract.
     * @param timelock The address of the TimelockController.
     * @return proxy The address of the deployed proxy contract.
     */
    function _deployProxy(address implementation, address timelock) internal returns (address proxy) {
        proxy = address(new TransparentUpgradeableProxy(implementation, timelock, ""));
    }

    /**
     * @notice Deploys the YnEigen contract suite with the provided initialization parameters.
     * @param init The YnEigenInit struct containing initialization parameters.
     * @return ynToken The deployed ynEigen contract.
     * @return eigenStrategyManager The deployed EigenStrategyManager contract.
     * @return tokenStakingNodesManager The deployed TokenStakingNodesManager contract.
     * @return tokenStakingNode The deployed TokenStakingNode contract.
     * @return assetRegistry The deployed AssetRegistry contract.
     * @return ynEigenDepositAdapterInstance The deployed ynEigenDepositAdapter contract.
     * @return rateProvider The deployed IRateProvider contract.
     * @return timelock The deployed TimelockController contract.
     * @return viewer The deployed ynEigenViewer contract.
     */
    function deploy(YnEigenInit calldata init)
        external
        returns (
            ynEigen ynToken,
            EigenStrategyManager eigenStrategyManager,
            TokenStakingNodesManager tokenStakingNodesManager,
            TokenStakingNode tokenStakingNode,
            AssetRegistry assetRegistry,
            ynEigenDepositAdapter ynEigenDepositAdapterInstance,
            IRateProvider rateProvider,
            TimelockController timelock,
            ynEigenViewer viewer
        )
    {
        ynEigenFactoryInitValidator.validate(init);

        // Deploy timelock
        {
            // Configure TimelockController roles:
            // - YNSecurityCouncil is set as both proposer and executor
            // This setup ensures that only the security council can propose, cancel, and execute,
            // while the Timelock adds the necessary delay for each upgrade.
            address[] memory _proposers = new address[](1);
            _proposers[0] = init.actors.YN_SECURITY_COUNCIL;
            address[] memory _executors = new address[](1);
            _executors[0] = init.actors.YN_SECURITY_COUNCIL;

            timelock =
                new TimelockController(init.timeLockDelay, _proposers, _executors, init.actors.YN_SECURITY_COUNCIL);
        }

        // Deploy implementations
        {
            ynEigen ynEigenImplementation = new ynEigen();
            ynToken = ynEigen((_deployProxy(address(ynEigenImplementation), address(timelock))));
        }

        {
            address rateProviderImplementation = init.rateProviderImplementation;
            rateProvider = IRateProvider((_deployProxy(rateProviderImplementation, address(timelock))));
        }

        {
            EigenStrategyManager eigenStrategyManagerImplementation = new EigenStrategyManager();
            eigenStrategyManager =
                EigenStrategyManager((_deployProxy(address(eigenStrategyManagerImplementation), address(timelock))));
        }

        {
            TokenStakingNodesManager tokenStakingNodesManagerImplementation = new TokenStakingNodesManager();
            tokenStakingNodesManager = TokenStakingNodesManager(
                (_deployProxy(address(tokenStakingNodesManagerImplementation), address(timelock)))
            );
        }

        {
            AssetRegistry assetRegistryImplementation = new AssetRegistry();
            assetRegistry = AssetRegistry((_deployProxy(address(assetRegistryImplementation), address(timelock))));
        }

        // Initialize ynToken
        {
            address[] memory pauseWhitelist = new address[](0);

            ynEigen.Init memory ynInit = ynEigen.Init({
                name: init.name,
                symbol: init.symbol,
                admin: init.actors.ADMIN,
                pauser: init.actors.PAUSE_ADMIN,
                unpauser: init.actors.UNPAUSE_ADMIN,
                yieldNestStrategyManager: address(eigenStrategyManager),
                assetRegistry: IAssetRegistry(address(assetRegistry)),
                pauseWhitelist: pauseWhitelist
            });
            ynToken.initialize(ynInit);
        }

        {
            EigenStrategyManager.Init memory eigenStrategyManagerInit = EigenStrategyManager.Init({
                assets: init.assets,
                strategies: init.strategies,
                ynEigen: IynEigen(address(ynToken)),
                strategyManager: IStrategyManager(init.chainAddresses.STRATEGY_MANAGER),
                delegationManager: IDelegationManager(init.chainAddresses.DELEGATION_MANAGER),
                tokenStakingNodesManager: ITokenStakingNodesManager(address(tokenStakingNodesManager)),
                admin: init.actors.ADMIN,
                pauser: init.actors.PAUSE_ADMIN,
                unpauser: init.actors.UNPAUSE_ADMIN,
                strategyController: init.actors.STRATEGY_CONTROLLER,
                strategyAdmin: init.actors.EIGEN_STRATEGY_ADMIN,
                wstETH: IwstETH(init.chainAddresses.WSTETH_ADDRESS),
                woETH: IERC4626(init.chainAddresses.WOETH_ADDRESS)
            });
            eigenStrategyManager.initialize(eigenStrategyManagerInit);
        }

        {
            AssetRegistry.Init memory assetRegistryInit = AssetRegistry.Init({
                assets: init.assets,
                rateProvider: IRateProvider(address(rateProvider)),
                yieldNestStrategyManager: IYieldNestStrategyManager(address(eigenStrategyManager)),
                ynEigen: IynEigen(address(ynToken)),
                admin: init.actors.ADMIN,
                pauser: init.actors.PAUSE_ADMIN,
                unpauser: init.actors.UNPAUSE_ADMIN,
                assetManagerRole: init.actors.ASSET_MANAGER_ADMIN
            });
            assetRegistry.initialize(assetRegistryInit);
        }

        {
            // Explanation of the use of DEFAULT_SIGNER in the script:
            // DEFAULT_SIGNER is used as a placeholder for the initial administrative roles during setup
            // to allow registering the implementation of TokenStakingNode as part of this script.
            // It will be replaced by specific actor roles at the end of the script.
            TokenStakingNodesManager.Init memory tokenStakingNodesManagerInit = TokenStakingNodesManager.Init({
                admin: address(this), // change at end of script
                stakingAdmin: address(this), // change at end of script
                strategyManager: IStrategyManager(init.chainAddresses.STRATEGY_MANAGER),
                delegationManager: IDelegationManager(init.chainAddresses.DELEGATION_MANAGER),
                yieldNestStrategyManager: address(eigenStrategyManager),
                maxNodeCount: init.maxNodeCount,
                pauser: init.actors.PAUSE_ADMIN,
                unpauser: init.actors.UNPAUSE_ADMIN,
                tokenStakingNodeOperator: init.actors.TOKEN_STAKING_NODE_OPERATOR,
                tokenStakingNodeCreatorRole: init.actors.STAKING_NODE_CREATOR,
                tokenStakingNodesDelegator: init.actors.STAKING_NODES_DELEGATOR_ADMIN
            });

            tokenStakingNodesManager.initialize(tokenStakingNodesManagerInit);
        }

        {
            tokenStakingNode = new TokenStakingNode();
            tokenStakingNodesManager.registerTokenStakingNode(address(tokenStakingNode));
        }

        // Post Deployment, the actual roles can be set.
        tokenStakingNodesManager.grantRole(tokenStakingNodesManager.DEFAULT_ADMIN_ROLE(), init.actors.ADMIN);
        tokenStakingNodesManager.grantRole(tokenStakingNodesManager.STAKING_ADMIN_ROLE(), address(timelock));

        // Remove roles from DEFAULT_SIGNER. DEFAULT_ADMIN_ROLE MUST be done last.
        tokenStakingNodesManager.revokeRole(tokenStakingNodesManager.STAKING_ADMIN_ROLE(), address(this));
        tokenStakingNodesManager.revokeRole(tokenStakingNodesManager.DEFAULT_ADMIN_ROLE(), address(this));

        // ynEigenDepositAdapter
        {
            ynEigenDepositAdapter ynEigenDepositAdapterImplementation = new ynEigenDepositAdapter();
            ynEigenDepositAdapterInstance =
                ynEigenDepositAdapter((_deployProxy(address(ynEigenDepositAdapterImplementation), address(timelock))));
        }

        {
            ynEigenDepositAdapter.Init memory ynEigenDepositAdapterInit = ynEigenDepositAdapter.Init({
                ynEigen: address(ynToken),
                wstETH: init.chainAddresses.WSTETH_ADDRESS,
                woETH: init.chainAddresses.WOETH_ADDRESS,
                admin: init.actors.ADMIN
            });
            ynEigenDepositAdapterInstance.initialize(ynEigenDepositAdapterInit);
        }

        {
            address _viewerImplementation = address(
                new ynEigenViewer(
                    address(assetRegistry), address(ynToken), address(tokenStakingNodesManager), address(rateProvider)
                )
            );

            // ProxyAdmin Owner set to YNSecurityCouncil since ynEigenViewer does not run production on-chain SC logic.
            viewer = ynEigenViewer((_deployProxy(_viewerImplementation, init.actors.YN_SECURITY_COUNCIL)));
        }

        emit YnEigenDeployed(
            ynToken,
            eigenStrategyManager,
            tokenStakingNodesManager,
            tokenStakingNode,
            assetRegistry,
            ynEigenDepositAdapterInstance,
            rateProvider,
            timelock,
            viewer
        );
    }
}
