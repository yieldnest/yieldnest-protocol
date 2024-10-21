// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {TransparentUpgradeableProxy, ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {RedemptionAssetsVault} from "src/ynEIGEN/RedemptionAssetsVault.sol";
import {LSDWrapper} from "src/ynEIGEN/LSDWrapper.sol";
import {WithdrawalQueueManager} from "src/WithdrawalQueueManager.sol";
import {IRedeemableAsset} from "src/interfaces/IRedeemableAsset.sol";
import {IRedemptionAssetsVault} from "src/interfaces/IRedemptionAssetsVault.sol";
import {IAssetRegistry} from "src/interfaces/IAssetRegistry.sol";
import {IynEigen} from "src/interfaces/IynEigen.sol";
import {ynEigen} from "src/ynEIGEN/ynEigen.sol";

import "forge-std/console.sol";

import "./BaseYnEigenScript.s.sol";

// ---- Usage ----

// deploy:
// forge script script/ynEigen/YnUpgrader.s.sol:YnUpgrader --verify --slow --legacy --etherscan-api-key $KEY --rpc-url $RPC_URL --broadcast

// verify:
// --constructor-args $(cast abi-encode "constructor(address)" 0x5C1E6bA712e9FC3399Ee7d5824B6Ec68A0363C02)
// forge verify-contract --etherscan-api-key $KEY --watch --chain-id $CHAIN_ID --compiler-version $FULL_COMPILER_VER --verifier-url $VERIFIER_URL $ADDRESS $PATH:$FILE_NAME

contract YnUpgrader is BaseYnEigenScript {

    address yneigen = 0xcc40b0BB00199Cdd15f7df9dC4E2B60AB273b56E;
    address assetRegistry = 0x32Df3aC2fFD2CD53a4AAb8b7EB68798033B41EAF;
    address tokenStakingNodeImpl = 0x63f01b695c67B764e823F972bc61fcAFbac5102b;

    function run() public {

        vm.startBroadcast(vm.envUint("DEPLOYER_PRIVATE_KEY"));

        // deploy RedemptionAssetsVault
        TransparentUpgradeableProxy _redemptionAssetsVaultProxy;
        address _redemptionAssetsVaultImpl;
        {
            _redemptionAssetsVaultImpl = address(new RedemptionAssetsVault());
            _redemptionAssetsVaultProxy = new TransparentUpgradeableProxy(
                _redemptionAssetsVaultImpl,
                actors.admin.PROXY_ADMIN_OWNER,
                ""
            );
        }

        // deploy WithdrawalQueueManager
        TransparentUpgradeableProxy _withdrawalQueueManagerProxy;
        address _withdrawalQueueManagerImpl;
        {
            _withdrawalQueueManagerImpl = address(new WithdrawalQueueManager());
            _withdrawalQueueManagerProxy = new TransparentUpgradeableProxy(
                _withdrawalQueueManagerImpl,
                actors.admin.PROXY_ADMIN_OWNER,
                ""
            );
        }

        // deploy wrapper
        TransparentUpgradeableProxy _wrapperProxy;
        address _wrapperImpl;
        {
            _wrapperImpl = address(new LSDWrapper(
                chainAddresses.lsd.WSTETH_ADDRESS,
                chainAddresses.lsd.WOETH_ADDRESS,
                chainAddresses.lsd.OETH_ADDRESS,
                chainAddresses.lsd.STETH_ADDRESS
            ));
            _wrapperProxy = new TransparentUpgradeableProxy(
                _wrapperImpl,
                actors.admin.PROXY_ADMIN_OWNER,
                abi.encodeWithSignature("initialize()")
            );
        }

        // initialize RedemptionAssetsVault
        {
            RedemptionAssetsVault.Init memory _init = RedemptionAssetsVault.Init({
                admin: actors.admin.PROXY_ADMIN_OWNER,
                redeemer: address(_withdrawalQueueManagerProxy),
                ynEigen: IynEigen(address(yneigen)),
                assetRegistry: IAssetRegistry(assetRegistry)
            });
            RedemptionAssetsVault(address(_redemptionAssetsVaultProxy)).initialize(_init);
        }

        // initialize WithdrawalQueueManager
        {
            WithdrawalQueueManager.Init memory _init = WithdrawalQueueManager.Init({
                name: "ynLSDe Withdrawal Manager",
                symbol: "ynLSDeWM",
                redeemableAsset: IRedeemableAsset(yneigen),
                redemptionAssetsVault: IRedemptionAssetsVault(address(_redemptionAssetsVaultProxy)),
                admin: actors.admin.PROXY_ADMIN_OWNER,
                withdrawalQueueAdmin: actors.ops.WITHDRAWAL_MANAGER,
                redemptionAssetWithdrawer: actors.ops.REDEMPTION_ASSET_WITHDRAWER,
                requestFinalizer:  actors.ops.REQUEST_FINALIZER,
                withdrawalFee: 0,
                feeReceiver: actors.admin.FEE_RECEIVER
            });
            WithdrawalQueueManager(address(_withdrawalQueueManagerProxy)).initialize(_init);
        }

        vm.stopBroadcast();

        console.log("=====================================");
        console.log("=====================================");
        // console.log("_redemptionAssetsVaultProxy: ", address(_redemptionAssetsVaultProxy));
        // console.log("_redemptionAssetsVaultImpl: ", address(_redemptionAssetsVaultImpl));
        // console.log("_withdrawalQueueManagerProxy: ", address(_withdrawalQueueManagerProxy));
        // console.log("_withdrawalQueueManagerImpl: ", address(_withdrawalQueueManagerImpl));
        // console.log("_wrapperProxy: ", address(_wrapperProxy));
        // console.log("_wrapperImpl: ", address(_wrapperImpl));
        _printUpgradeTokenStakingNodeImplementationData();
        _printBurnerRole();
        console.log("=====================================");
        console.log("=====================================");

    }

    function _printUpgradeTokenStakingNodeImplementationData() private view {
        bytes memory _data = abi.encodeWithSignature(
            "upgradeTokenStakingNode(address)",
            tokenStakingNodeImpl
        );
        console.log("=====================================");
        console.log("_printUpgradeTokenStakingNodeImplementationData");
        console.logBytes(_data);
        console.log("=====================================");
    }

    function _printBurnerRole() private view {
        console.log("=====================================");
        console.log("ynEigen(yneigen).BURNER_ROLE(): ");
        console.logBytes32(ynEigen(yneigen).BURNER_ROLE());
        console.log("=====================================");
    }

//     =====================================
//   =====================================
//   _redemptionAssetsVaultProxy:  0xF5efA92F85457Ed22722783917B55318b75815bf
//   _redemptionAssetsVaultImpl:  0xD82d61C2905595f554233De5cDb947979802267C
//   _withdrawalQueueManagerProxy:  0xeCA746232f297bBD968B4eF240fb28c40BE5CCB7
//   _withdrawalQueueManagerImpl:  0xcADC2A8Ccf396088f8D7520Ae8fD249CcfCC20Db
//   _wrapperProxy:  0x63Bc6100DF15a5553715d453570d07f62B400D85
//   _wrapperImpl:  0x2E66Fc93a48877cAdE526dB164afA04EBe9be449
}