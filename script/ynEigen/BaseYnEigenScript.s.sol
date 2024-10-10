// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {stdJson} from "lib/forge-std/src/StdJson.sol";
import {ynEigen} from "src/ynEIGEN/ynEigen.sol";
import {AssetRegistry} from "src/ynEIGEN/AssetRegistry.sol";
import {EigenStrategyManager} from "src/ynEIGEN/EigenStrategyManager.sol";
import {TokenStakingNodesManager} from "src/ynEIGEN/TokenStakingNodesManager.sol";
import {TokenStakingNode} from "src/ynEIGEN/TokenStakingNode.sol";
import {ynEigenDepositAdapter} from "src/ynEIGEN/ynEigenDepositAdapter.sol";
import {IRateProvider} from "src/interfaces/IRateProvider.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {LSDWrapper} from "src/ynEIGEN/LSDWrapper.sol";
import {RedemptionAssetsVault} from "src/ynEIGEN/RedemptionAssetsVault.sol";
import {WithdrawalQueueManager} from "src/WithdrawalQueueManager.sol";

import {ActorAddresses} from "script/Actors.sol";
import {ContractAddresses} from "script/ContractAddresses.sol";
import {BaseScript} from "script/BaseScript.s.sol";
import {ynEigenViewer} from "src/ynEIGEN/ynEigenViewer.sol";

import {console} from "lib/forge-std/src/console.sol";

contract BaseYnEigenScript is BaseScript {
    using stdJson for string;

    struct Deployment {
        ynEigen ynEigen;
        AssetRegistry assetRegistry;
        EigenStrategyManager eigenStrategyManager;
        TokenStakingNodesManager tokenStakingNodesManager;
        TokenStakingNode tokenStakingNodeImplementation;
        ynEigenDepositAdapter ynEigenDepositAdapterInstance;
        IRateProvider rateProvider;
        TimelockController upgradeTimelock;
        ynEigenViewer viewer;
        RedemptionAssetsVault redemptionAssetsVault;
        WithdrawalQueueManager withdrawalQueueManager;
        LSDWrapper lsdWrapper;
    }

    struct Asset {
        string name;
        address strategy;
        address token;
    }

    struct Input {
        Asset[] assets;
        uint256 chainId;
        string name;
        string symbol;
    }

    error IncorrectChainId(uint256 specifiedChainId, uint256 actualChainId);
    error UnsupportedChainId(uint256 chainId);
    error UnsupportedAsset(string asset, uint256 chainId);

    Input public inputs;
    ActorAddresses.Actors public actors;
    ContractAddresses.ChainAddresses public chainAddresses;

    address internal _deployer;

    constructor() {
        actors = getActors();
        chainAddresses = getChainAddresses();
    }

    function _initDeployer() internal {
        _deployer = msg.sender; // set by --sender when running the script
    }

    function _loadJson(string memory _path) internal {
        string memory path = string(abi.encodePacked(vm.projectRoot(), "/", _path));
        string memory json = vm.readFile(path);
        bytes memory data = vm.parseJson(json);

        Input memory _inputs = abi.decode(data, (Input));

        this.loadInputs(_inputs);
    }

    /**
     * @dev this function is required to load the JSON input struct into storage untill that feature is added to foundry
     */
    function loadInputs(Input calldata _inputs) external {
        inputs = _inputs;
    }

    function _validateNetwork() internal virtual {
        if (block.chainid != inputs.chainId) revert IncorrectChainId(inputs.chainId, block.chainid);
        if (!isSupportedChainId(inputs.chainId)) revert UnsupportedChainId(inputs.chainId);
    }

    function tokenName() internal view returns (string memory) {
        return inputs.symbol;
    }

    function getDeploymentFile() internal view virtual returns (string memory) {
        string memory root = vm.projectRoot();

        return string.concat(root, "/deployments/", tokenName(), "-", vm.toString(block.chainid), ".json");
    }

    function saveDeployment(Deployment memory deployment) public virtual {
        string memory json = "deployment";

        // contract addresses
        serializeProxyElements(json, tokenName(), address(deployment.ynEigen));
        serializeProxyElements(json, "assetRegistry", address(deployment.assetRegistry));
        serializeProxyElements(json, "eigenStrategyManager", address(deployment.eigenStrategyManager));
        serializeProxyElements(json, "tokenStakingNodesManager", address(deployment.tokenStakingNodesManager));
        vm.serializeAddress(json, "tokenStakingNodeImplementation", address(deployment.tokenStakingNodeImplementation));
        serializeProxyElements(json, "ynEigenDepositAdapter", address(deployment.ynEigenDepositAdapterInstance));
        serializeProxyElements(json, "rateProvider", address(deployment.rateProvider));
        serializeProxyElements(json, "ynEigenViewer", address(deployment.viewer));
        vm.serializeAddress(json, "upgradeTimelock", address(deployment.upgradeTimelock));
        serializeProxyElements(json, "redemptionAssetsVault", address(deployment.redemptionAssetsVault));
        serializeProxyElements(json, "withdrawalQueueManager", address(deployment.withdrawalQueueManager));
        serializeProxyElements(json, "lsdWrapper", address(deployment.lsdWrapper));


        // actors
        vm.serializeAddress(json, "PROXY_ADMIN_OWNER", address(actors.admin.PROXY_ADMIN_OWNER));
        vm.serializeAddress(json, "ADMIN", address(actors.admin.ADMIN));
        vm.serializeAddress(json, "STAKING_ADMIN", address(actors.admin.STAKING_ADMIN));
        vm.serializeAddress(json, "STAKING_NODES_OPERATOR", address(actors.ops.STAKING_NODES_OPERATOR));
        vm.serializeAddress(json, "PAUSE_ADMIN", address(actors.ops.PAUSE_ADMIN));
        vm.serializeAddress(json, "UNPAUSE_ADMIN", address(actors.admin.UNPAUSE_ADMIN));
        vm.serializeAddress(json, "TOKEN_STAKING_NODE_CREATOR", address(actors.ops.STAKING_NODE_CREATOR));
        vm.serializeAddress(json, "STRATEGY_CONTROLLER", address(actors.ops.STRATEGY_CONTROLLER));
        vm.serializeAddress(json, "EIGEN_STRATEGY_ADMIN", address(actors.admin.EIGEN_STRATEGY_ADMIN));
        vm.serializeAddress(json, "YnSecurityCouncil", address(actors.wallets.YNSecurityCouncil));
        vm.serializeAddress(json, "YNDev", address(actors.wallets.YNDev));
        string memory finalJson = vm.serializeAddress(json, "DEFAULT_SIGNER", address((actors.eoa.DEFAULT_SIGNER)));

        vm.writeJson(finalJson, getDeploymentFile());

        console.log("Deployment JSON file written successfully:", getDeploymentFile());
    }

    function loadDeployment() public view returns (Deployment memory) {
        string memory deploymentFile = getDeploymentFile();
        string memory jsonContent = vm.readFile(deploymentFile);
        Deployment memory deployment;
        deployment.ynEigen = ynEigen(payable(jsonContent.readAddress(string.concat(".proxy-", tokenName()))));
        deployment.tokenStakingNodesManager =
            TokenStakingNodesManager(payable(jsonContent.readAddress(".proxy-tokenStakingNodesManager")));
        deployment.assetRegistry = AssetRegistry(payable(jsonContent.readAddress(".proxy-assetRegistry")));
        deployment.eigenStrategyManager =
            EigenStrategyManager(payable(jsonContent.readAddress(".proxy-eigenStrategyManager")));
        deployment.tokenStakingNodeImplementation =
            TokenStakingNode(payable(jsonContent.readAddress(".tokenStakingNodeImplementation")));
        deployment.ynEigenDepositAdapterInstance =
            ynEigenDepositAdapter(payable(jsonContent.readAddress(".proxy-ynEigenDepositAdapter")));
        deployment.rateProvider = IRateProvider(payable(jsonContent.readAddress(".proxy-rateProvider")));
        deployment.viewer = ynEigenViewer(payable(jsonContent.readAddress(".proxy-ynEigenViewer")));
        deployment.upgradeTimelock = TimelockController(payable(jsonContent.readAddress(".upgradeTimelock")));

        return deployment;
    }

    function getProxyAddress(string memory contractName) public view returns (address) {
        string memory deploymentFile = getDeploymentFile();
        string memory jsonContent = vm.readFile(deploymentFile);
        string memory proxyKey = string.concat(".proxy-", contractName);
        return jsonContent.readAddress(proxyKey);
    }
}
