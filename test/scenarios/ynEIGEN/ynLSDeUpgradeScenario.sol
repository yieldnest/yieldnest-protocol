// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {ITokenStakingNode} from "../../../src/interfaces/ITokenStakingNode.sol";

import {HoleskyLSDRateProvider} from "../../../src/testnet/HoleksyLSDRateProvider.sol";

import {TestStakingNodesManagerV2} from "../../mocks/TestStakingNodesManagerV2.sol";
// import {TestStakingNodeV2} from "../../mocks/TestStakingNodeV2.sol";
import {TokenStakingNode} from "../../../src/ynEIGEN/TokenStakingNode.sol";

import "./ynLSDeScenarioBaseTest.sol";
import {console} from "forge-std/console.sol";


contract ynLSDeUpgradeScenario is ynLSDeScenarioBaseTest {

    function setUp() public virtual override {
        super.setUp();
        test_Upgrade_TokenStakingNodeImplementation_Scenario();
    }
    
    function test_Upgrade_ynLSDe_Scenario() public {

        address previousImplementation = getTransparentUpgradeableProxyImplementationAddress(address(yneigen));
        console.log("Total assets before upgrade:", yneigen.totalAssets());
        address newImplementation = address(new ynEigen()); 

        uint256 previousTotalAssets = yneigen.totalAssets();
        uint256 previousTotalSupply = IERC20(address(yneigen)).totalSupply();

        upgradeContract(address(yneigen), newImplementation);

        runUpgradeInvariants(address(yneigen), previousImplementation, newImplementation);
        runSystemStateInvariants(previousTotalAssets, previousTotalSupply);
        runTransferOwnership(address(yneigen));
    }
    
    function test_Upgrade_TokenStakingNodesManager_Scenario() public {

        address previousStakingNodesManagerImpl = getTransparentUpgradeableProxyImplementationAddress(address(tokenStakingNodesManager));
        address newStakingNodesManagerImpl = address(new TokenStakingNodesManager());
        
        uint256 previousTotalAssets = yneigen.totalAssets();
        uint256 previousTotalSupply = IERC20(address(yneigen)).totalSupply();

        upgradeContract(address(tokenStakingNodesManager), newStakingNodesManagerImpl);
        
        runUpgradeInvariants(address(tokenStakingNodesManager), previousStakingNodesManagerImpl, newStakingNodesManagerImpl);
        runSystemStateInvariants(previousTotalAssets, previousTotalSupply);
        runTransferOwnership(address(tokenStakingNodesManager));
    }

    function test_Upgrade_AssetRegistry() public {

        address previousAssetRegistryImpl = getTransparentUpgradeableProxyImplementationAddress(address(assetRegistry));
        address newAssetRegistryImpl = address(new AssetRegistry());
        
        uint256 previousTotalAssets = yneigen.totalAssets();
        uint256 previousTotalSupply = IERC20(address(yneigen)).totalSupply();

        upgradeContract(address(assetRegistry), newAssetRegistryImpl);
        
        runUpgradeInvariants(address(assetRegistry), previousAssetRegistryImpl, newAssetRegistryImpl);
        runSystemStateInvariants(previousTotalAssets, previousTotalSupply);
        runTransferOwnership(address(assetRegistry));
    }

    function test_Upgrade_EigenStrategyManager() public {

        address previousEigenStrategyManagerImpl = getTransparentUpgradeableProxyImplementationAddress(address(eigenStrategyManager));
        address newEigenStrategyManagerImpl = address(new EigenStrategyManager());
        
        uint256 previousTotalAssets = yneigen.totalAssets();
        uint256 previousTotalSupply = IERC20(address(yneigen)).totalSupply();

        upgradeContract(address(eigenStrategyManager), newEigenStrategyManagerImpl);
        
        runUpgradeInvariants(address(eigenStrategyManager), previousEigenStrategyManagerImpl, newEigenStrategyManagerImpl);
        runSystemStateInvariants(previousTotalAssets, previousTotalSupply);
        runTransferOwnership(address(eigenStrategyManager));
    }

    function test_Upgrade_LSDRateProvider() public {

        address previousLSDRateProviderImpl = getTransparentUpgradeableProxyImplementationAddress(address(lsdRateProvider));
        address newLSDRateProviderImpl;
        if (block.chainid == 17000) { // Holesky
            newLSDRateProviderImpl = address(new HoleskyLSDRateProvider());
        } else if (block.chainid == 1) { // Mainnet
            newLSDRateProviderImpl = address(new LSDRateProvider());
        } else {
            revert("Unsupported chain ID");
        }

        uint256 previousTotalAssets = yneigen.totalAssets();
        uint256 previousTotalSupply = IERC20(address(yneigen)).totalSupply();

        upgradeContract(address(lsdRateProvider), newLSDRateProviderImpl);

        runUpgradeInvariants(address(lsdRateProvider), previousLSDRateProviderImpl, newLSDRateProviderImpl);
        runSystemStateInvariants(previousTotalAssets, previousTotalSupply);
        runTransferOwnership(address(lsdRateProvider));
    }

    function test_Upgrade_ynEigenDepositAdapter() public {

        address previousYnEigenDepositAdapterImpl = getTransparentUpgradeableProxyImplementationAddress(address(ynEigenDepositAdapter_));
        address newYnEigenDepositAdapterImpl = address(new ynEigenDepositAdapter());
        
        uint256 previousTotalAssets = yneigen.totalAssets();
        uint256 previousTotalSupply = IERC20(address(yneigen)).totalSupply();

        upgradeContract(address(ynEigenDepositAdapter_), newYnEigenDepositAdapterImpl);
        
        runUpgradeInvariants(address(ynEigenDepositAdapter_), previousYnEigenDepositAdapterImpl, newYnEigenDepositAdapterImpl);
        runSystemStateInvariants(previousTotalAssets, previousTotalSupply);
        runTransferOwnership(address(ynEigenDepositAdapter_));
    }

    function test_Upgrade_AllContracts_Batch() public {
        address[] memory contracts = new address[](6);
        address[] memory newImplementations = new address[](6);

        // YnLSDe
        contracts[0] = address(yneigen);
        newImplementations[0] = address(new ynEigen());

        // EigenStrategyManager
        contracts[1] = address(eigenStrategyManager);
        newImplementations[1] = address(new EigenStrategyManager());

        // LSDRateProvider
        if (block.chainid == 17000) { // Holesky
            newImplementations[2] = address(new HoleskyLSDRateProvider());
        } else if (block.chainid == 1) { // Mainnet
            newImplementations[2] = address(new LSDRateProvider());
        } else {
            revert("Unsupported chain ID");
        }
        contracts[2] = address(lsdRateProvider);

        // ynEigenDepositAdapter
        contracts[3] = address(ynEigenDepositAdapter_);
        newImplementations[3] = address(new ynEigenDepositAdapter());

        // AssetRegistry
        contracts[4] = address(assetRegistry);
        newImplementations[4] = address(new AssetRegistry());

        // TokenStakingNodesManager
        contracts[5] = address(tokenStakingNodesManager);
        newImplementations[5] = address(new TokenStakingNodesManager());

        uint256 previousTotalAssets = yneigen.totalAssets();
        uint256 previousTotalSupply = IERC20(address(yneigen)).totalSupply();

        address[] memory previousImplementations = new address[](contracts.length);
        for (uint i = 0; i < contracts.length; i++) {
            previousImplementations[i] = getTransparentUpgradeableProxyImplementationAddress(contracts[i]);
        }

        upgradeContractBatch(contracts, newImplementations);

        for (uint i = 0; i < contracts.length; i++) {
            runUpgradeInvariants(contracts[i], previousImplementations[i], newImplementations[i]);
            runTransferOwnership(contracts[i]);
        }

        runSystemStateInvariants(previousTotalAssets, previousTotalSupply);
    }

    function test_Upgrade_TokenStakingNodeImplementation_Scenario() public {

        ITokenStakingNode[] memory tokenStakingNodesBefore = tokenStakingNodesManager.getAllNodes();

        uint256 previousTotalAssets = yneigen.totalAssets();
        uint256 previousTotalSupply = IERC20(address(yneigen)).totalSupply();

        TokenStakingNode testStakingNodeV2 = new TokenStakingNode();
        {
            bytes memory _data = abi.encodeWithSignature(
                "upgradeTokenStakingNode(address)",
                testStakingNodeV2
            );
            vm.startPrank(actors.wallets.YNSecurityCouncil);
            timelockController.schedule(
                address(tokenStakingNodesManager), // target
                0, // value
                _data,
                bytes32(0), // predecessor
                bytes32(0), // salt
                timelockController.getMinDelay() // delay
            );
            vm.stopPrank();

            uint256 minDelay;
            if (block.chainid == 1) { // Mainnet
                minDelay = 3 days;
            } else if (block.chainid == 17000) { // Holesky
                minDelay = 15 minutes;
            } else {
                revert("Unsupported chain ID");
            }
            skip(minDelay);

            vm.startPrank(actors.wallets.YNSecurityCouncil);
            timelockController.execute(
                address(tokenStakingNodesManager), // target
                0, // value
                _data,
                bytes32(0), // predecessor
                bytes32(0) // salt
            );
            vm.stopPrank();
        }

    
        UpgradeableBeacon beacon = tokenStakingNodesManager.upgradeableBeacon();
        address upgradedImplementationAddress = beacon.implementation();
        assertEq(upgradedImplementationAddress, address(testStakingNodeV2));

        // check tokenStakingNodesManager.getAllNodes is the same as before
        ITokenStakingNode[] memory tokenStakingNodesAfter = tokenStakingNodesManager.getAllNodes();
        assertEq(tokenStakingNodesAfter.length, tokenStakingNodesBefore.length, "TokenStakingNodes length mismatch after upgrade");
        for (uint i = 0; i < tokenStakingNodesAfter.length; i++) {
            assertEq(address(tokenStakingNodesAfter[i]), address(tokenStakingNodesBefore[i]), "TokenStakingNode address mismatch after upgrade");
        }

        runSystemStateInvariants(previousTotalAssets, previousTotalSupply);
        // runTransferOwnership(address(tokenStakingNodesManager)); // NOTE: fails ynLSDeWithdrawals.t.sol setup
    }

    function runUpgradeInvariants(
        address proxyAddress,
        address previousImplementation,
        address newImplementation
    ) internal {
        // Check that the new implementation address is correctly set
        address currentImplementation = getTransparentUpgradeableProxyImplementationAddress(proxyAddress);
        assertEq(currentImplementation, newImplementation, "Invariant: Implementation address should match the new implementation address");
        // Ensure the implementation address has actually changed
        assertNotEq(previousImplementation, newImplementation, "Invariant: New implementation should be different from the previous one");
    }

    function runSystemStateInvariants(uint256 previousTotalAssets, uint256 previousTotalSupply) public {  
        uint256 threshold = previousTotalAssets / 1e3;
        assertTrue(compareWithThreshold(yneigen.totalAssets(), previousTotalAssets, threshold), "Total assets integrity check failed");
        assertEq(yneigen.totalSupply(), previousTotalSupply, "Share mint integrity check failed");
	}

    function upgradeContractBatch(address[] memory _proxyAddresses, address[] memory _newImplementations) public {
        require(_proxyAddresses.length == _newImplementations.length, "Arrays must have the same length");

        address[] memory targets = new address[](_proxyAddresses.length);
        uint256[] memory values = new uint256[](_proxyAddresses.length);
        bytes[] memory payloads = new bytes[](_proxyAddresses.length);

        for (uint i = 0; i < _proxyAddresses.length; i++) {
            targets[i] = getTransparentUpgradeableProxyAdminAddress(_proxyAddresses[i]);
            values[i] = 0;
            payloads[i] = abi.encodeWithSignature(
                "upgradeAndCall(address,address,bytes)",
                _proxyAddresses[i],
                _newImplementations[i],
                ""
            );
        }

        vm.startPrank(actors.wallets.YNSecurityCouncil);
        timelockController.scheduleBatch(
            targets,
            values,
            payloads,
            bytes32(0), // predecessor
            bytes32(0), // salt
            timelockController.getMinDelay() // delay
        );
        vm.stopPrank();

        uint256 minDelay;
        if (block.chainid == 1) { // Mainnet
            minDelay = 3 days;
        } else if (block.chainid == 17000) { // Holesky
            minDelay = 15 minutes;
        } else {
            revert("Unsupported chain ID");
        }
        skip(minDelay);

        vm.startPrank(actors.wallets.YNSecurityCouncil);
        timelockController.executeBatch(
            targets,
            values,
            payloads,
            bytes32(0), // predecessor
            bytes32(0) // salt
        );
        vm.stopPrank();
    }

    function upgradeContract(address _proxyAddress, address _newImplementation) public {
        bytes memory _data = abi.encodeWithSignature(
            "upgradeAndCall(address,address,bytes)",
            _proxyAddress, // proxy
            _newImplementation, // implementation
            "" // no data
        );
        vm.startPrank(actors.wallets.YNSecurityCouncil);
        timelockController.schedule(
            getTransparentUpgradeableProxyAdminAddress(_proxyAddress), // target
            0, // value
            _data,
            bytes32(0), // predecessor
            bytes32(0), // salt
            timelockController.getMinDelay() // delay
        );
        vm.stopPrank();

        uint256 minDelay;
        if (block.chainid == 1) { // Mainnet
            minDelay = 3 days;
        } else if (block.chainid == 17000) { // Holesky
            minDelay = 15 minutes;
        } else {
            revert("Unsupported chain ID");
        }
        skip(minDelay);

        vm.startPrank(actors.wallets.YNSecurityCouncil);
        timelockController.execute(
            getTransparentUpgradeableProxyAdminAddress(_proxyAddress), // target
            0, // value
            _data,
            bytes32(0), // predecessor
            bytes32(0) // salt
        );
        vm.stopPrank();
    }

    function runTransferOwnership(address _proxy) public {
        address _newOwner = address(0x1241242151);
        bytes memory _data = abi.encodeWithSignature("transferOwnership(address)", _newOwner);
        vm.startPrank(actors.wallets.YNSecurityCouncil);
        timelockController.schedule(
            getTransparentUpgradeableProxyAdminAddress(address(_proxy)), // target
            0, // value
            _data,
            bytes32(0), // predecessor
            bytes32(0), // salt
            timelockController.getMinDelay() // delay
        );
        vm.stopPrank();

        uint256 minDelay;
        if (block.chainid == 1) { // Mainnet
            minDelay = 3 days;
        } else if (block.chainid == 17000) { // Holesky
            minDelay = 15 minutes;
        } else {
            revert("Unsupported chain ID");
        }
        skip(minDelay);

        vm.startPrank(actors.wallets.YNSecurityCouncil);
        timelockController.execute(
            getTransparentUpgradeableProxyAdminAddress(address(_proxy)), // target
            0, // value
            _data,
            bytes32(0), // predecessor
            bytes32(0) // salt
        );
        vm.stopPrank();
        assertEq(Ownable(getTransparentUpgradeableProxyAdminAddress(address(_proxy))).owner(), _newOwner, "Ownership transfer failed");
    }
}