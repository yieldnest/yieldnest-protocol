// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {TransparentUpgradeableProxy, ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {RedemptionAssetsVault} from "src/ynEIGEN/RedemptionAssetsVault.sol";
import {LSDWrapper} from "src/ynEIGEN/LSDWrapper.sol";
import {WithdrawalQueueManager} from "src/WithdrawalQueueManager.sol";
import {IRedeemableAsset} from "src/interfaces/IRedeemableAsset.sol";
import {IRedemptionAssetsVault} from "src/interfaces/IRedemptionAssetsVault.sol";
import {IAssetRegistry} from "src/interfaces/IAssetRegistry.sol";
import {IynEigen} from "src/interfaces/IynEigen.sol";
import {ynEigen} from "src/ynEIGEN/ynEigen.sol";
import {ynEigenDepositAdapter} from "src/ynEIGEN/ynEigenDepositAdapter.sol";

import "forge-std/console.sol";

import "./BaseYnEigenScript.s.sol";

// ---- Usage ----

// deploy:
// forge script script/ynEigen/YnUpgrader.s.sol:YnUpgrader --verify --slow --legacy --etherscan-api-key $KEY --rpc-url $RPC_URL --broadcast

// verify:
// --constructor-args $(cast abi-encode "constructor(address)" 0x5C1E6bA712e9FC3399Ee7d5824B6Ec68A0363C02)
// forge verify-contract --etherscan-api-key $KEY --watch --chain-id $CHAIN_ID --compiler-version $FULL_COMPILER_VER --verifier-url $VERIFIER_URL $ADDRESS $PATH:$FILE_NAME

contract YnUpgrader is BaseYnEigenScript {

    // holesky
    address yneigenProxy = 0x071bdC8eDcdD66730f45a3D3A6F794FAA37C75ED;
    address assetRegistryProxy = 0xaD31546AdbfE1EcD7137310508f112039a35b6F7;
    address ynEigenDepositAdapterProxy = 0x7d0c1F604571a1c015684e6c15f2DdEc432C5e74;
    address eigenStrategyManagerProxy = 0xA0a11A9b84bf87c0323bc183715a22eC7881B7FC;
    address tokenStakingNodesManagerProxy = 0x5c20D1a85C7d9acB503135a498E26Eb55d806552;
    TimelockController timelockController = TimelockController(payable(address(0x62173555C27C67644C5634e114e42A63A59CD7A5)));
    //

    TransparentUpgradeableProxy redemptionAssetsVaultProxy;
    TransparentUpgradeableProxy withdrawalQueueManagerProxy;
    TransparentUpgradeableProxy wrapperProxy;

    function run() public {

        vm.startBroadcast(vm.envUint("DEPLOYER_PRIVATE_KEY"));

        // deploy RedemptionAssetsVault
        address _redemptionAssetsVaultImpl;
        {
            _redemptionAssetsVaultImpl = address(new RedemptionAssetsVault());
            redemptionAssetsVaultProxy = new TransparentUpgradeableProxy(
                _redemptionAssetsVaultImpl,
                actors.admin.PROXY_ADMIN_OWNER,
                ""
            );
        }

        // deploy WithdrawalQueueManager
        address _withdrawalQueueManagerImpl;
        {
            _withdrawalQueueManagerImpl = address(new WithdrawalQueueManager());
            withdrawalQueueManagerProxy = new TransparentUpgradeableProxy(
                _withdrawalQueueManagerImpl,
                actors.admin.PROXY_ADMIN_OWNER,
                ""
            );
        }

        // deploy wrapper
        address _wrapperImpl;
        {
            _wrapperImpl = address(new LSDWrapper(
                chainAddresses.lsd.WSTETH_ADDRESS,
                chainAddresses.lsd.WOETH_ADDRESS,
                chainAddresses.lsd.OETH_ADDRESS,
                chainAddresses.lsd.STETH_ADDRESS
            ));
            wrapperProxy = new TransparentUpgradeableProxy(
                _wrapperImpl,
                actors.admin.PROXY_ADMIN_OWNER,
                abi.encodeWithSignature("initialize()")
            );
        }

        // initialize RedemptionAssetsVault
        {
            RedemptionAssetsVault.Init memory _init = RedemptionAssetsVault.Init({
                admin: actors.admin.PROXY_ADMIN_OWNER,
                redeemer: address(withdrawalQueueManagerProxy),
                ynEigen: IynEigen(address(yneigenProxy)),
                assetRegistry: IAssetRegistry(assetRegistryProxy)
            });
            RedemptionAssetsVault(address(redemptionAssetsVaultProxy)).initialize(_init);
        }

        // initialize WithdrawalQueueManager
        {
            WithdrawalQueueManager.Init memory _init = WithdrawalQueueManager.Init({
                name: "ynLSDe Withdrawal Manager",
                symbol: "ynLSDeWM",
                redeemableAsset: IRedeemableAsset(yneigenProxy),
                redemptionAssetsVault: IRedemptionAssetsVault(address(redemptionAssetsVaultProxy)),
                admin: actors.admin.PROXY_ADMIN_OWNER,
                withdrawalQueueAdmin: actors.ops.WITHDRAWAL_MANAGER,
                redemptionAssetWithdrawer: actors.ops.REDEMPTION_ASSET_WITHDRAWER,
                requestFinalizer:  actors.ops.REQUEST_FINALIZER,
                withdrawalFee: 1000,
                feeReceiver: actors.admin.FEE_RECEIVER
            });
            WithdrawalQueueManager(address(withdrawalQueueManagerProxy)).initialize(_init);
        }

        address _ynEigenImpl = address(new ynEigen());
        address _assetRegistryImpl = address(new AssetRegistry());
        address _tokenStakingNodesManagerImpl = address(new TokenStakingNodesManager());
        address _ynEigenDepositAdapterImpl = address(new ynEigenDepositAdapter());
        address _eigenStrategyManagerImpl = address(new EigenStrategyManager());
        address _tokenStakingNodeImpl = address(new TokenStakingNode());

        {
            _upgradeContracts(
                _ynEigenImpl,
                _assetRegistryImpl,
                _tokenStakingNodesManagerImpl,
                _ynEigenDepositAdapterImpl,
                _eigenStrategyManagerImpl,
                _tokenStakingNodeImpl
            );
        }

        vm.stopBroadcast();

        console.log("=====================================");
        console.log("=====================================");
        console.log("_redemptionAssetsVaultProxy: ", address(redemptionAssetsVaultProxy));
        console.log("_redemptionAssetsVaultImpl: ", address(_redemptionAssetsVaultImpl));
        console.log("_withdrawalQueueManagerProxy: ", address(withdrawalQueueManagerProxy));
        console.log("_withdrawalQueueManagerImpl: ", address(_withdrawalQueueManagerImpl));
        console.log("_wrapperProxy: ", address(wrapperProxy));
        console.log("_wrapperImpl: ", address(_wrapperImpl));
        console.log("_ynEigenImpl: ", _ynEigenImpl);
        console.log("_assetRegistryImpl: ", _assetRegistryImpl);
        console.log("_tokenStakingNodesManagerImpl: ", _tokenStakingNodesManagerImpl);
        console.log("_eigenStrategyManagerImpl: ", _eigenStrategyManagerImpl);
        console.log("_ynEigenDepositAdapterImpl: ", _ynEigenDepositAdapterImpl);
        // _printBurnerRole();
        console.log("=====================================");
        console.log("=====================================");
    }

    function _upgradeContracts(
        address _ynEigenImpl,
        address _assetRegistryImpl,
        address _tokenStakingNodesManagerImpl,
        address _ynEigenDepositAdapterImpl,
        address _eigenStrategyManagerImpl,
        address _tokenStakingNodeImpl
    ) internal {

        address[] memory _proxyAddresses = new address[](3);
        _proxyAddresses[0] = address(yneigenProxy);
        _proxyAddresses[1] = address(assetRegistryProxy);
        _proxyAddresses[2] = address(tokenStakingNodesManagerProxy);
        address[] memory _newImplementations = new address[](3);
        _newImplementations[0] = _ynEigenImpl;
        _newImplementations[1] = _assetRegistryImpl;
        _newImplementations[2] = _tokenStakingNodesManagerImpl;

        address[] memory targets = new address[](6);
        uint256[] memory values = new uint256[](6);
        bytes[] memory payloads = new bytes[](6);
        bytes32 predecessor = bytes32(0);
        bytes32 salt = bytes32(0);
        uint256 delay = timelockController.getMinDelay();

        for (uint256 i = 0; i < _proxyAddresses.length; i++) {
            bytes memory _data = abi.encodeWithSignature(
                "upgradeAndCall(address,address,bytes)",
                _proxyAddresses[i], // proxy
                _newImplementations[i], // implementation
                ""
            );
            targets[i] = getTransparentUpgradeableProxyAdminAddress(_proxyAddresses[i]);
            values[i] = 0;
            payloads[i] = _data;
        }

        targets[3] = address(tokenStakingNodesManagerProxy);
        values[3] = 0;
        payloads[3] = abi.encodeWithSignature(
            "upgradeTokenStakingNode(address)",
            _tokenStakingNodeImpl
        );

        targets[4] = getTransparentUpgradeableProxyAdminAddress(address(eigenStrategyManagerProxy));
        values[4] = 0;
        payloads[4] = abi.encodeWithSignature(
            "upgradeAndCall(address,address,bytes)",
            address(eigenStrategyManagerProxy), // proxy
            _eigenStrategyManagerImpl, // implementation
            abi.encodeWithSignature(
                "initializeV2(address,address,address)",
                address(redemptionAssetsVaultProxy),
                address(wrapperProxy),
                actors.ops.WITHDRAWAL_MANAGER
            )
        );

        targets[5] = getTransparentUpgradeableProxyAdminAddress(address(ynEigenDepositAdapterProxy));
        values[5] = 0;
        payloads[5] = abi.encodeWithSignature(
            "upgradeAndCall(address,address,bytes)",
            ynEigenDepositAdapterProxy, // proxy
            _ynEigenDepositAdapterImpl, // implementation
            abi.encodeWithSignature("initializeV2(address)", address(wrapperProxy))
        );

        // vm.prank(actors.wallets.YNSecurityCouncil);
        // timelockController.scheduleBatch(targets, values, payloads, predecessor, salt, delay);

        // print all targets, values, payloads
        for (uint256 i = 0; i < targets.length; i++) {
            console.log("=====================================");
            console.log("i: ", i);
            console.log("targets: ", targets[i]);
            console.log("values: ", values[i]);
            console.log("payloads:");
            console.logBytes(payloads[i]);
        }
        console.log("predecessor:");
        console.logBytes32(predecessor);
        console.log("salt:");
        console.logBytes32(salt);
        console.log("delay: ", delay);
        console.log("=====================================");

        // skip(delay);

        // vm.prank(actors.wallets.YNSecurityCouncil);
        // timelockController.executeBatch(targets, values, payloads, predecessor, salt);
    }

    function _printBurnerRole() private view {
        console.log("=====================================");
        console.log("ynEigen(yneigen).BURNER_ROLE(): ");
        console.logBytes32(ynEigen(yneigenProxy).BURNER_ROLE());
        console.log("=====================================");
    }
// targets -- [0x31456Eef519b7ab236e3638297Ed392390bf304F,0x4248392db8Ee31aA579822207d059A28A38c4510,0x18ED5129bCEfA996B4cade4e614c8941De3126d2,0x5c20D1a85C7d9acB503135a498E26Eb55d806552,0x010c60d663fddDAA076F0cE63f6692f0b5605fE5,0x9E9ce6D0fD72c7A31Eb7D99d8eCEA4b35a4FD088]
// values -- [0,0,0,0,0,0]
// payloads -- [0x9623609d000000000000000000000000071bdc8edcdd66730f45a3d3a6f794faa37c75ed000000000000000000000000e04d7deebf7ee127d5a06ed09f537ae03393bc2600000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000000,0x9623609d000000000000000000000000ad31546adbfe1ecd7137310508f112039a35b6f7000000000000000000000000345c63028f17d8da727595914fc64a4cc9cb649900000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000000,0x9623609d0000000000000000000000005c20d1a85c7d9acb503135a498e26eb55d8065520000000000000000000000003e1435cd3e13423de06c0ce4f9b8deb19a74f7b900000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000000,0xa39cebe9000000000000000000000000ea7de917660a7f42742e371e4c33f39433d92c5d,0x9623609d000000000000000000000000a0a11a9b84bf87c0323bc183715a22ec7881b7fc0000000000000000000000008fd057567d9ff56a42315f8bc1e31fde5c01f89d000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000642c3bb44a00000000000000000000000069a5fb8999ef1325e211611421d9d15b4c99b6150000000000000000000000008dd4c8f8553f2ff5ac57725ce165f848668d93950000000000000000000000000e36e2bcd71059e02822dfe52cba900730b07c0700000000000000000000000000000000000000000000000000000000,0x9623609d0000000000000000000000007d0c1f604571a1c015684e6c15f2ddec432c5e74000000000000000000000000365f901dfd546d7b9a4a8c3cca4a826a3ee000b20000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000002429b6eca90000000000000000000000008dd4c8f8553f2ff5ac57725ce165f848668d939500000000000000000000000000000000000000000000000000000000]
// =====================================
//   i:  0
//   targets:  0x31456Eef519b7ab236e3638297Ed392390bf304F
//   values:  0
//   payloads:
//   0x9623609d000000000000000000000000071bdc8edcdd66730f45a3d3a6f794faa37c75ed000000000000000000000000e04d7deebf7ee127d5a06ed09f537ae03393bc2600000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000000
//   =====================================
//   i:  1
//   targets:  0x4248392db8Ee31aA579822207d059A28A38c4510
//   values:  0
//   payloads:
//   0x9623609d000000000000000000000000ad31546adbfe1ecd7137310508f112039a35b6f7000000000000000000000000345c63028f17d8da727595914fc64a4cc9cb649900000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000000
//   =====================================
//   i:  2
//   targets:  0x18ED5129bCEfA996B4cade4e614c8941De3126d2
//   values:  0
//   payloads:
//   0x9623609d0000000000000000000000005c20d1a85c7d9acb503135a498e26eb55d8065520000000000000000000000003e1435cd3e13423de06c0ce4f9b8deb19a74f7b900000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000000
//   =====================================
//   i:  3
//   targets:  0x5c20D1a85C7d9acB503135a498E26Eb55d806552
//   values:  0
//   payloads:
//   0xa39cebe9000000000000000000000000ea7de917660a7f42742e371e4c33f39433d92c5d
//   =====================================
//   i:  4
//   targets:  0x010c60d663fddDAA076F0cE63f6692f0b5605fE5
//   values:  0
//   payloads:
//   0x9623609d000000000000000000000000a0a11a9b84bf87c0323bc183715a22ec7881b7fc0000000000000000000000008fd057567d9ff56a42315f8bc1e31fde5c01f89d000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000642c3bb44a00000000000000000000000069a5fb8999ef1325e211611421d9d15b4c99b6150000000000000000000000008dd4c8f8553f2ff5ac57725ce165f848668d93950000000000000000000000000e36e2bcd71059e02822dfe52cba900730b07c0700000000000000000000000000000000000000000000000000000000
//   =====================================
//   i:  5
//   targets:  0x9E9ce6D0fD72c7A31Eb7D99d8eCEA4b35a4FD088
//   values:  0
//   payloads:
//   0x9623609d0000000000000000000000007d0c1f604571a1c015684e6c15f2ddec432c5e74000000000000000000000000365f901dfd546d7b9a4a8c3cca4a826a3ee000b20000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000002429b6eca90000000000000000000000008dd4c8f8553f2ff5ac57725ce165f848668d939500000000000000000000000000000000000000000000000000000000
//   predecessor:
//   0x0000000000000000000000000000000000000000000000000000000000000000
//   salt:
//   0x0000000000000000000000000000000000000000000000000000000000000000
//   delay:  900
//   =====================================
//   =====================================
//   =====================================
//   _redemptionAssetsVaultProxy:  0x69A5fb8999ef1325e211611421D9D15B4c99B615
//   _redemptionAssetsVaultImpl:  0xf107F4425fbDF7917CedEB49854A4e76cB55B45d
//   _withdrawalQueueManagerProxy:  0x9B41B70c1C873b7A5b27318DBc5841D42bD604f3
//   _withdrawalQueueManagerImpl:  0x8302F1222b10b1D0E8f6acDf93179B44656c6b67
//   _wrapperProxy:  0x8dD4C8f8553F2Ff5Ac57725Ce165F848668D9395
//   _wrapperImpl:  0xccac878de03cCa903067B5C91B3C8C1102863A2E
//   _ynEigenImpl:  0xe04D7dEEBF7Ee127D5A06eD09F537AE03393bC26
//   _assetRegistryImpl:  0x345C63028f17d8DA727595914FC64A4cC9cB6499
//   _tokenStakingNodesManagerImpl:  0x3e1435Cd3e13423de06C0CE4F9B8deb19A74f7B9
//   _eigenStrategyManagerImpl:  0x8fD057567D9fF56A42315F8BC1e31FDe5c01F89d
//   _ynEigenDepositAdapterImpl:  0x365F901dfD546D7b9a4a8C3Cca4a826a3eE000B2
//   =====================================
//   =====================================
}