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
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";


import "forge-std/console.sol";

import "./BaseYnEigenScript.s.sol";

// ---- Usage ----

// deploy:
// forge script script/ynEigen/YnUpgrader.s.sol:YnUpgrader --verify --slow --legacy --etherscan-api-key $KEY --rpc-url $RPC_URL --broadcast

// verify:
// --constructor-args $(cast abi-encode "constructor(address)" 0x5C1E6bA712e9FC3399Ee7d5824B6Ec68A0363C02)
// forge verify-contract --etherscan-api-key $KEY --watch --chain-id $CHAIN_ID --compiler-version $FULL_COMPILER_VER --verifier-url $VERIFIER_URL $ADDRESS $PATH:$FILE_NAME

contract YnUpgrader is BaseYnEigenScript {

    // // holesky
    // address yneigenProxy = 0x071bdC8eDcdD66730f45a3D3A6F794FAA37C75ED;
    // address assetRegistryProxy = 0xaD31546AdbfE1EcD7137310508f112039a35b6F7;
    // address ynEigenDepositAdapterProxy = 0x7d0c1F604571a1c015684e6c15f2DdEc432C5e74;
    // address eigenStrategyManagerProxy = 0xA0a11A9b84bf87c0323bc183715a22eC7881B7FC;
    // address tokenStakingNodesManagerProxy = 0x5c20D1a85C7d9acB503135a498E26Eb55d806552;
    // TimelockController timelockController = TimelockController(payable(address(0x62173555C27C67644C5634e114e42A63A59CD7A5)));
    // //

    // mainnet
    address yneigenProxy = 0x35Ec69A77B79c255e5d47D5A3BdbEFEfE342630c;
    address assetRegistryProxy = 0x323C933df2523D5b0C756210446eeE0fB84270fd;
    address ynEigenDepositAdapterProxy = 0x9e72155d301a6555dc565315be72D295c76753c0;
    address eigenStrategyManagerProxy = 0x92D904019A92B0Cafce3492Abb95577C285A68fC;
    address tokenStakingNodesManagerProxy = 0x6B566CB6cDdf7d140C59F84594756a151030a0C3;
    TimelockController timelockController = TimelockController(payable(address(0xbB73f8a5B0074b27c6df026c77fA08B0111D017A)));

    TransparentUpgradeableProxy redemptionAssetsVaultProxy;
    TransparentUpgradeableProxy withdrawalQueueManagerProxy;
    TransparentUpgradeableProxy wrapperProxy;

    function run() public {


        // Assert proxy admins for existing poxies
        assertProxyAdminOwnedByTimelock(yneigenProxy);
        assertProxyAdminOwnedByTimelock(assetRegistryProxy);
        assertProxyAdminOwnedByTimelock(ynEigenDepositAdapterProxy);
        assertProxyAdminOwnedByTimelock(eigenStrategyManagerProxy);
        assertProxyAdminOwnedByTimelock(tokenStakingNodesManagerProxy);

        vm.startBroadcast(vm.envUint("DEPLOYER_PRIVATE_KEY"));

        // deploy RedemptionAssetsVault
        address _redemptionAssetsVaultImpl;
        {
            _redemptionAssetsVaultImpl = address(new RedemptionAssetsVault());
            redemptionAssetsVaultProxy = new TransparentUpgradeableProxy(
                _redemptionAssetsVaultImpl,
                address(timelockController),
                ""
            );
        }

        // deploy WithdrawalQueueManager
        address _withdrawalQueueManagerImpl;
        {
            _withdrawalQueueManagerImpl = address(new WithdrawalQueueManager());
            withdrawalQueueManagerProxy = new TransparentUpgradeableProxy(
                _withdrawalQueueManagerImpl,
                address(timelockController),
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
                address(timelockController),
                abi.encodeWithSignature("initialize()")
            );
        }

        // Assert proxy admins for new proxies
        assertProxyAdminOwnedByTimelock(address(redemptionAssetsVaultProxy));
        assertProxyAdminOwnedByTimelock(address(withdrawalQueueManagerProxy));
        assertProxyAdminOwnedByTimelock(address(wrapperProxy));

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
                withdrawalQueueAdmin: actors.admin.ADMIN,
                redemptionAssetWithdrawer: actors.ops.REDEMPTION_ASSET_WITHDRAWER,
                requestFinalizer:  actors.ops.YNEIGEN_REQUEST_FINALIZER,
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
                actors.ops.YNEIGEN_WITHDRAWAL_MANAGER
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


    function assertProxyAdminOwnedByTimelock(address proxyAddress) internal view {
        address proxyAdminOwner = ProxyAdmin(getTransparentUpgradeableProxyAdminAddress(proxyAddress)).owner();
        require(proxyAdminOwner == address(timelockController), "Proxy admin not owned by timelock");
    }

    function _printBurnerRole() private view {
        console.log("=====================================");
        console.log("ynEigen(yneigen).BURNER_ROLE(): ");
        console.logBytes32(ynEigen(yneigenProxy).BURNER_ROLE());
        console.log("=====================================");
    }


// MAINNET

// == Logs ==
//   =====================================
//   i:  0
//   targets:  0x1bfF798A6072597c401f7C83A6a1096Ae5F0aFf7
//   values:  0
//   payloads:
//   0x9623609d00000000000000000000000035ec69a77b79c255e5d47d5a3bdbefefe342630c000000000000000000000000989c5e2509c501deb6195b9f525d9092514041b400000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000000
//   =====================================
//   i:  1
//   targets:  0xDf92BE359fB53846cCdaC8FFF1884314533949C7
//   values:  0
//   payloads:
//   0x9623609d000000000000000000000000323c933df2523d5b0c756210446eee0fb84270fd00000000000000000000000094db8f0d5bbccebf6d8288d06eb53bb80ca125bd00000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000000
//   =====================================
//   i:  2
//   targets:  0x850d012115fb4D90711F53e86B2945019Bf7F36C
//   values:  0
//   payloads:
//   0x9623609d0000000000000000000000006b566cb6cddf7d140c59f84594756a151030a0c300000000000000000000000081f34d0db58a7934549d9b2b1e76542ed9801b1f00000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000000
//   =====================================
//   i:  3
//   targets:  0x6B566CB6cDdf7d140C59F84594756a151030a0C3
//   values:  0
//   payloads:
//   0xa39cebe9000000000000000000000000c602682b9ebc9719181b7a2b2479291cba26f801
//   =====================================
//   i:  4
//   targets:  0x69C34FB00Ebc0d7ac09Ab7968D2Eb9a07C2eB301
//   values:  0
//   payloads:
//   0x9623609d00000000000000000000000092d904019a92b0cafce3492abb95577c285a68fc0000000000000000000000001776dea5799fc7ad10b6039f6e1927fefd731e85000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000642c3bb44a00000000000000000000000073bc33999c34a5126ca19dc900f22690c288d55e00000000000000000000000099db7619c018d61dbc2822767b63240d311d699200000000000000000000000015519e68ca7544d1c919a2a6e9065375a1f0c80a00000000000000000000000000000000000000000000000000000000
//   =====================================
//   i:  5
//   targets:  0x7D779806B0c6A0201984b82e57830B84a75c3C07
//   values:  0
//   payloads:
//   0x9623609d0000000000000000000000009e72155d301a6555dc565315be72d295c76753c00000000000000000000000008ef7a066bf2cf76bad826c1de8d314badf057b520000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000002429b6eca900000000000000000000000099db7619c018d61dbc2822767b63240d311d699200000000000000000000000000000000000000000000000000000000
//   predecessor:
//   0x0000000000000000000000000000000000000000000000000000000000000000
//   salt:
//   0x0000000000000000000000000000000000000000000000000000000000000000
//   delay:  259200
//   =====================================
//   =====================================
//   =====================================
//   _redemptionAssetsVaultProxy:  0x73bC33999C34a5126CA19dC900F22690C288D55e
//   _redemptionAssetsVaultImpl:  0x9892A40FE6e17d4C88a92b2e37c12981bAA6F14A
//   _withdrawalQueueManagerProxy:  0x8Face3283E20b19d98a7a132274B69C1304D60b4
//   _withdrawalQueueManagerImpl:  0xaac93A4ddE34CE9ad9dD8556B9faDd83380a5D64
//   _wrapperProxy:  0x99dB7619C018D61dBC2822767B63240d311d6992
//   _wrapperImpl:  0x7C31a924B01a20642aF2460d7Fe24A2FEf89074d
//   _ynEigenImpl:  0x989C5E2509C501deB6195b9f525d9092514041b4
//   _assetRegistryImpl:  0x94db8f0d5bBCCEBF6d8288d06eb53bB80cA125bd
//   _tokenStakingNodesManagerImpl:  0x81f34d0DB58A7934549D9B2B1E76542ED9801B1f
//   _eigenStrategyManagerImpl:  0x1776deA5799fc7ad10b6039f6E1927fEfd731E85
//   _ynEigenDepositAdapterImpl:  0x8Ef7a066bf2Cf76baD826C1De8D314badF057b52
//   _tokenStakingNodeImpl: 0xc602682b9ebc9719181b7a2b2479291cba26f801
//   =====================================
//   =====================================

// HOLESKY

// targets -- [0x31456Eef519b7ab236e3638297Ed392390bf304F,0x4248392db8Ee31aA579822207d059A28A38c4510,0x18ED5129bCEfA996B4cade4e614c8941De3126d2,0x5c20D1a85C7d9acB503135a498E26Eb55d806552,0x010c60d663fddDAA076F0cE63f6692f0b5605fE5,0x9E9ce6D0fD72c7A31Eb7D99d8eCEA4b35a4FD088]
// values -- [0,0,0,0,0,0]
// payloads -- [0x9623609d000000000000000000000000071bdc8edcdd66730f45a3d3a6f794faa37c75ed000000000000000000000000350793a4b8f19ae1a67e5b4f3646483847cb755000000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000000,0x9623609d000000000000000000000000ad31546adbfe1ecd7137310508f112039a35b6f7000000000000000000000000b8d77186574bb4951c20464dbbfb31c6b018c4b000000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000000,0x9623609d0000000000000000000000005c20d1a85c7d9acb503135a498e26eb55d8065520000000000000000000000003e07b130533a8d3285203c697d6ff2b25996397b00000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000000,0xa39cebe90000000000000000000000004486c96883ee436525e11cfb1b0f589c11ff75c6,0x9623609d000000000000000000000000a0a11a9b84bf87c0323bc183715a22ec7881b7fc0000000000000000000000000b02f50fb5c498eb63231f65844b88763b91c5c9000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000642c3bb44a000000000000000000000000d536087701fff805d20ee6651e55c90d645fd1a30000000000000000000000008f61bcb28c5b88e5f10ec5bb3c18f231d763a3090000000000000000000000000e36e2bcd71059e02822dfe52cba900730b07c0700000000000000000000000000000000000000000000000000000000,0x9623609d0000000000000000000000007d0c1f604571a1c015684e6c15f2ddec432c5e740000000000000000000000009e12251f0a7728d6804aba297a7ce725c4b77e4c0000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000002429b6eca90000000000000000000000008f61bcb28c5b88e5f10ec5bb3c18f231d763a30900000000000000000000000000000000000000000000000000000000]
// =====================================
//   i:  0
//   targets:  0x31456Eef519b7ab236e3638297Ed392390bf304F
//   values:  0
//   payloads:
//   0x9623609d000000000000000000000000071bdc8edcdd66730f45a3d3a6f794faa37c75ed000000000000000000000000350793a4b8f19ae1a67e5b4f3646483847cb755000000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000000
//   =====================================
//   i:  1
//   targets:  0x4248392db8Ee31aA579822207d059A28A38c4510
//   values:  0
//   payloads:
//   0x9623609d000000000000000000000000ad31546adbfe1ecd7137310508f112039a35b6f7000000000000000000000000b8d77186574bb4951c20464dbbfb31c6b018c4b000000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000000
//   =====================================
//   i:  2
//   targets:  0x18ED5129bCEfA996B4cade4e614c8941De3126d2
//   values:  0
//   payloads:
//   0x9623609d0000000000000000000000005c20d1a85c7d9acb503135a498e26eb55d8065520000000000000000000000003e07b130533a8d3285203c697d6ff2b25996397b00000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000000
//   =====================================
//   i:  3
//   targets:  0x5c20D1a85C7d9acB503135a498E26Eb55d806552
//   values:  0
//   payloads:
//   0xa39cebe90000000000000000000000004486c96883ee436525e11cfb1b0f589c11ff75c6
//   =====================================
//   i:  4
//   targets:  0x010c60d663fddDAA076F0cE63f6692f0b5605fE5
//   values:  0
//   payloads:
//   0x9623609d000000000000000000000000a0a11a9b84bf87c0323bc183715a22ec7881b7fc0000000000000000000000000b02f50fb5c498eb63231f65844b88763b91c5c9000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000642c3bb44a000000000000000000000000d536087701fff805d20ee6651e55c90d645fd1a30000000000000000000000008f61bcb28c5b88e5f10ec5bb3c18f231d763a3090000000000000000000000000e36e2bcd71059e02822dfe52cba900730b07c0700000000000000000000000000000000000000000000000000000000
//   =====================================
//   i:  5
//   targets:  0x9E9ce6D0fD72c7A31Eb7D99d8eCEA4b35a4FD088
//   values:  0
//   payloads:
//   0x9623609d0000000000000000000000007d0c1f604571a1c015684e6c15f2ddec432c5e740000000000000000000000009e12251f0a7728d6804aba297a7ce725c4b77e4c0000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000002429b6eca90000000000000000000000008f61bcb28c5b88e5f10ec5bb3c18f231d763a30900000000000000000000000000000000000000000000000000000000
//   predecessor:
//   0x0000000000000000000000000000000000000000000000000000000000000000
//   salt:
//   0x0000000000000000000000000000000000000000000000000000000000000000
//   delay:  900
//   =====================================
//   =====================================
//   =====================================
//   _redemptionAssetsVaultProxy:  0xd536087701fFf805d20ee6651E55C90D645fD1a3
//   _redemptionAssetsVaultImpl:  0x398e9AE08179E2e07dDD51C7DCB9d585F3abC31A
//   _withdrawalQueueManagerProxy:  0xaF8052DC454318D52A4478a91aCa14305590389f
//   _withdrawalQueueManagerImpl:  0xf1B38e1ef304dE9a289219DCA7350f8cEE36C509
//   _wrapperProxy:  0x8F61bcb28C5b88e5F10ec5bb3C18f231D763A309
//   _wrapperImpl:  0xAd13B029FaF660a45b6F81888bB2fd1EF235Ef30
//   _ynEigenImpl:  0x350793a4B8F19Ae1a67E5b4F3646483847CB7550
//   _assetRegistryImpl:  0xB8d77186574BB4951C20464DBBfB31C6b018c4B0
//   _tokenStakingNodesManagerImpl:  0x3E07B130533A8D3285203c697d6ff2b25996397B
//   _eigenStrategyManagerImpl:  0x0B02f50fB5c498eB63231f65844B88763b91C5C9
//   _ynEigenDepositAdapterImpl:  0x9E12251f0A7728d6804Aba297a7CE725C4B77e4c
//   =====================================
//   =====================================
}