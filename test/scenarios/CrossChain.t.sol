// SPDX-License-Identifier: LZBL-1.2
pragma solidity ^0.8.20;

import "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import "@layerzerolabs/lz-evm-oapp-v2/contracts-upgradeable/oapp/libs/OptionsBuilder.sol";
import "@layerzerolabs/lz-evm-oapp-v2/contracts-upgradeable/oapp/interfaces/IOAppOptionsType3.sol";
import "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLibManager.sol";
import "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/UlnBase.sol";

import "@layerzero/test/TestHelper.sol";

import "@layerzero/test/utils/MockOracle.sol";
import "@layerzero/test/utils/MockRateLimiter.sol";
import "@layerzero/test/utils/MockLineaBridge.sol";
import "@layerzero/test/utils/MockModeBridge.sol";
import "@layerzero/test/utils/MockOFTAdapter.sol";

import "@layerzero/contracts/tokens/DummyTokenUpgradeable.sol";
import "@layerzero/contracts/tokens/MintableOFTUpgradeable.sol";
import "@layerzero/contracts/interfaces/IMessageService.sol";
import "@layerzero/contracts/interfaces/IL1Receiver.sol";

import "../../src/cross-chain/mock/L1VaultETH.sol";
import "../../src/cross-chain/L1/receivers/L1LineaReceiverETH.sol";
import "../../src/cross-chain/L1/receivers/L1ModeReceiverETH.sol";
import "../../src/cross-chain/L1/L1SyncPoolETH.sol";
import "../../src/cross-chain/L2/syncpools/L2LineaSyncPoolETH.sol";
import "../../src/cross-chain/L2/syncpools/L2ModeSyncPoolETH.sol";
import "../../src/cross-chain/L2/L2ExchangeRateProvider.sol";

enum CHAINS {
    ETHEREUM,
    MODE,
    LINEA
}

struct L1 {
    uint256 forkId;
    address vault;
    address tokenIn;
    address tokenOut;
    address oftToken; // = lockBox
    address syncPool;
    mapping(CHAINS => address) receivers;
    mapping(CHAINS => address) dummyETHs;
}

struct L2 {
    uint256 forkId;
    address tokenIn;
    address tokenOut;
    uint256 minSyncAmount;
    address rateLimiter;
    address rateProvider;
    uint64 depositFee;
    uint32 freshPeriod;
    address rateOracle;
    address syncPool;
}

interface ModeEvent {
    event MessagePassed(
        uint256 indexed nonce,
        address indexed sender,
        address indexed target,
        uint256 value,
        uint256 gasLimit,
        bytes data,
        bytes32 withdrawalHash
    );
}

contract CrossChainTest is TestHelper {
    using OptionsBuilder for bytes;

    L1 public ethereum;
    L2 public mode;
    L2 public linea;

    function setUp() public override {
        super.setUp();

        ethereum.forkId = vm.createFork(ETHEREUM.rpcUrl, ETHEREUM.forkBlockNumber);
        mode.forkId = vm.createFork(MODE.rpcUrl, MODE.forkBlockNumber);
        linea.forkId = vm.createFork(LINEA.rpcUrl, LINEA.forkBlockNumber);

        // DEPLOYMENT //

        // Ethereum
        {
            vm.selectFork(ethereum.forkId);

            address vault = _deployContract(type(L1VaultETH).creationCode, new bytes(0));
            address oftAdapter = _deployProxy(
                type(MockOFTAdapter).creationCode,
                abi.encode(vault, ETHEREUM.endpoint),
                abi.encodeCall(MockOFTAdapter.initialize, address(this))
            );
            address syncPool = _deployProxy(
                type(L1SyncPoolETH).creationCode,
                abi.encode(ETHEREUM.endpoint),
                abi.encodeCall(L1SyncPoolETH.initialize, (vault, vault, oftAdapter, address(this)))
            );

            ethereum.tokenIn = Constants.ETH_ADDRESS;
            ethereum.tokenOut = vault;
            ethereum.vault = vault;
            ethereum.oftToken = oftAdapter;
            ethereum.syncPool = syncPool;

            address modeReceiver = _deployProxy(
                type(L1ModeReceiverETH).creationCode,
                new bytes(0),
                abi.encodeCall(
                    L1ModeReceiverETHUpgradeable.initialize,
                    (address(syncPool), address(MODE.L1messenger), address(this))
                )
            );
            address lineaReceiver = _deployProxy(
                type(L1LineaReceiverETH).creationCode,
                new bytes(0),
                abi.encodeCall(
                    L1LineaReceiverETHUpgradeable.initialize,
                    (address(syncPool), address(LINEA.L1messenger), address(this))
                )
            );

            ethereum.receivers[CHAINS.MODE] = modeReceiver;
            ethereum.receivers[CHAINS.LINEA] = lineaReceiver;

            address modeDummyETH = _deployImmutableProxy(
                type(DummyTokenUpgradeable).creationCode,
                abi.encode(18),
                abi.encodeCall(DummyTokenUpgradeable.initialize, ("modeDummyETH", "modeETH", address(this)))
            );
            address lineaDummyETH = _deployImmutableProxy(
                type(DummyTokenUpgradeable).creationCode,
                abi.encode(18),
                abi.encodeCall(DummyTokenUpgradeable.initialize, ("lineaDummyETH", "lineaETH", address(this)))
            );

            ethereum.dummyETHs[CHAINS.MODE] = modeDummyETH;
            ethereum.dummyETHs[CHAINS.LINEA] = lineaDummyETH;

            vm.label(vault, "l1Vault");
            vm.label(oftAdapter, "l1OFTAdapter");
            vm.label(syncPool, "l1SyncPool");
            vm.label(modeReceiver, "l1ModeReceiver");
            vm.label(lineaReceiver, "l1LineaReceiver");
            vm.label(modeDummyETH, "l1modeDummyETH");
            vm.label(lineaDummyETH, "l1lineaDummyETH");
        }

        // Mode
        {
            vm.selectFork(mode.forkId);

            address rateProvider = _deployProxy(
                type(L2ExchangeRateProvider).creationCode,
                new bytes(0),
                abi.encodeCall(L2ExchangeRateProvider.initialize, address(this))
            );
            address oftToken = _deployImmutableProxy(
                type(MintableOFTUpgradeable).creationCode,
                abi.encode(MODE.endpoint),
                abi.encodeCall(MintableOFTUpgradeable.initialize, ("modeOFT", "OFT", address(this)))
            );
            address rateLimiter = _deployContract(type(MockRateLimiter).creationCode, new bytes(0));
            address rateOracle = _deployContract(type(MockOracle).creationCode, new bytes(0));

            mode.tokenIn = Constants.ETH_ADDRESS;
            mode.tokenOut = oftToken;
            mode.minSyncAmount = 1e18;
            mode.rateLimiter = rateLimiter;
            mode.rateProvider = rateProvider;
            mode.depositFee = 0.01e18; // 1%
            mode.freshPeriod = 24 hours;
            mode.rateOracle = rateOracle;

            address syncPool = _deployProxy(
                type(L2ModeSyncPoolETHUpgradeable).creationCode,
                abi.encode(ETHEREUM.endpoint),
                abi.encodeCall(
                    L2ModeSyncPoolETHUpgradeable.initialize,
                    (
                        rateProvider,
                        rateLimiter,
                        oftToken,
                        ETHEREUM.originEid,
                        MODE.L2messenger,
                        ethereum.receivers[CHAINS.MODE],
                        address(this)
                    )
                )
            );

            mode.syncPool = syncPool;

            vm.label(rateProvider, "modeRateProvider");
            vm.label(oftToken, "modeOFT");
            vm.label(rateLimiter, "modeRateLimiter");
            vm.label(rateOracle, "modeRateOracle");
            vm.label(syncPool, "modeSyncPool");
        }

        // Linea
        {
            vm.selectFork(linea.forkId);

            address rateProvider = _deployProxy(
                type(L2ExchangeRateProvider).creationCode,
                new bytes(0),
                abi.encodeCall(L2ExchangeRateProvider.initialize, address(this))
            );
            address oftToken = _deployImmutableProxy(
                type(MintableOFTUpgradeable).creationCode,
                abi.encode(LINEA.endpoint),
                abi.encodeCall(MintableOFTUpgradeable.initialize, ("lineaOFT", "OFT", address(this)))
            );
            address rateLimiter = _deployContract(type(MockRateLimiter).creationCode, new bytes(0));
            address rateOracle = _deployContract(type(MockOracle).creationCode, new bytes(0));

            linea.tokenIn = Constants.ETH_ADDRESS;
            linea.tokenOut = oftToken;
            linea.minSyncAmount = 1e18;
            linea.rateLimiter = rateLimiter;
            linea.rateProvider = rateProvider;
            linea.depositFee = 0.01e18; // 1%
            linea.freshPeriod = 24 hours;
            linea.rateOracle = rateOracle;

            address syncPool = _deployProxy(
                type(L2LineaSyncPoolETHUpgradeable).creationCode,
                abi.encode(ETHEREUM.endpoint),
                abi.encodeCall(
                    L2LineaSyncPoolETHUpgradeable.initialize,
                    (
                        rateProvider,
                        rateLimiter,
                        oftToken,
                        ETHEREUM.originEid,
                        LINEA.L2messenger,
                        ethereum.receivers[CHAINS.LINEA],
                        address(this)
                    )
                )
            );

            linea.syncPool = syncPool;

            vm.label(rateProvider, "lineaRateProvider");
            vm.label(oftToken, "lineaOFT");
            vm.label(rateLimiter, "lineaRateLimiter");
            vm.label(rateOracle, "lineaRateOracle");
            vm.label(syncPool, "lineaSyncPool");
        }

        // INITIALIZATION //

        // Ethereum
        {
            vm.selectFork(ethereum.forkId);

            DummyTokenUpgradeable(ethereum.dummyETHs[CHAINS.MODE]).grantRole(
                keccak256("MINTER_ROLE"), ethereum.syncPool
            );
            DummyTokenUpgradeable(ethereum.dummyETHs[CHAINS.LINEA]).grantRole(
                keccak256("MINTER_ROLE"), ethereum.syncPool
            );

            L1VaultETH(payable(ethereum.vault)).grantRole(keccak256("SYNC_POOL_ROLE"), ethereum.syncPool);

            L1VaultETH(payable(ethereum.vault)).addDummyETH(ethereum.dummyETHs[CHAINS.MODE]);
            L1VaultETH(payable(ethereum.vault)).addDummyETH(ethereum.dummyETHs[CHAINS.LINEA]);

            L1SyncPoolETH(ethereum.syncPool).setDummyToken(MODE.originEid, ethereum.dummyETHs[CHAINS.MODE]);
            L1SyncPoolETH(ethereum.syncPool).setDummyToken(LINEA.originEid, ethereum.dummyETHs[CHAINS.LINEA]);

            L1SyncPoolETH(ethereum.syncPool).setReceiver(MODE.originEid, ethereum.receivers[CHAINS.MODE]);
            L1SyncPoolETH(ethereum.syncPool).setReceiver(LINEA.originEid, ethereum.receivers[CHAINS.LINEA]);

            L1SyncPoolETH(ethereum.syncPool).setPeer(MODE.originEid, bytes32(uint256(uint160(mode.syncPool))));
            L1SyncPoolETH(ethereum.syncPool).setPeer(LINEA.originEid, bytes32(uint256(uint160(linea.syncPool))));

            MockOFTAdapter(ethereum.oftToken).setPeer(MODE.originEid, bytes32(uint256(uint160(mode.tokenOut))));
            MockOFTAdapter(ethereum.oftToken).setPeer(LINEA.originEid, bytes32(uint256(uint160(linea.tokenOut))));

            _setUpOApp(ethereum.oftToken, ETHEREUM.endpoint, ETHEREUM.send302, ETHEREUM.lzDvn, MODE.originEid);
            _setUpOApp(ethereum.oftToken, ETHEREUM.endpoint, ETHEREUM.send302, ETHEREUM.lzDvn, LINEA.originEid);

            // Deposit 1000 ETH to the vault and increase the rate to 1.04
            L1VaultETH(payable(ethereum.vault)).depositETH{value: 1_000e18}(1_000e18, address(this));
            (bool s,) = ethereum.vault.call{value: 40e18}("");
            require(s, "Playground::setUp: failed to send ETH to the vault");

            assertApproxEqAbs(L1VaultETH(payable(ethereum.vault)).previewRedeem(1e18), 1.04e18, 1, "setUp::1");
        }

        // Mode
        {
            vm.selectFork(mode.forkId);

            L2ExchangeRateProvider(mode.rateProvider).setRateParameters(
                mode.tokenIn, mode.rateOracle, mode.depositFee, mode.freshPeriod
            );

            MockOracle(mode.rateOracle).setPrice(1e18);

            L2ModeSyncPoolETH(mode.syncPool).setMinSyncAmount(mode.tokenIn, mode.minSyncAmount);
            L2ModeSyncPoolETH(mode.syncPool).setL1TokenIn(mode.tokenIn, ethereum.tokenIn);

            MintableOFTUpgradeable(mode.tokenOut).grantRole(keccak256("MINTER_ROLE"), mode.syncPool);

            L2ModeSyncPoolETH(mode.syncPool).setPeer(ETHEREUM.originEid, bytes32(uint256(uint160(ethereum.syncPool))));

            MintableOFTUpgradeable(mode.tokenOut).setPeer(
                ETHEREUM.originEid, bytes32(uint256(uint160(ethereum.oftToken)))
            );
            MintableOFTUpgradeable(mode.tokenOut).setPeer(LINEA.originEid, bytes32(uint256(uint160(linea.tokenOut))));

            _setUpOApp(mode.tokenOut, MODE.endpoint, MODE.send302, MODE.lzDvn, LINEA.originEid);
            _setUpOApp(mode.tokenOut, MODE.endpoint, MODE.send302, MODE.lzDvn, ETHEREUM.originEid);

            _setUpOApp(mode.syncPool, MODE.endpoint, MODE.send302, MODE.lzDvn, ETHEREUM.originEid);
        }

        // Linea
        {
            vm.selectFork(linea.forkId);

            L2ExchangeRateProvider(linea.rateProvider).setRateParameters(
                linea.tokenIn, linea.rateOracle, linea.depositFee, linea.freshPeriod
            );

            MockOracle(linea.rateOracle).setPrice(1e18);

            L2LineaSyncPoolETH(linea.syncPool).setMinSyncAmount(linea.tokenIn, linea.minSyncAmount);
            L2LineaSyncPoolETH(linea.syncPool).setL1TokenIn(linea.tokenIn, ethereum.tokenIn);

            MintableOFTUpgradeable(linea.tokenOut).grantRole(keccak256("MINTER_ROLE"), linea.syncPool);

            L2LineaSyncPoolETH(linea.syncPool).setPeer(ETHEREUM.originEid, bytes32(uint256(uint160(ethereum.syncPool))));

            MintableOFTUpgradeable(linea.tokenOut).setPeer(
                ETHEREUM.originEid, bytes32(uint256(uint160(ethereum.oftToken)))
            );
            MintableOFTUpgradeable(linea.tokenOut).setPeer(MODE.originEid, bytes32(uint256(uint160(mode.tokenOut))));

            _setUpOApp(linea.tokenOut, LINEA.endpoint, LINEA.send302, LINEA.lzDvn, MODE.originEid);
            _setUpOApp(linea.tokenOut, LINEA.endpoint, LINEA.send302, LINEA.lzDvn, ETHEREUM.originEid);

            _setUpOApp(linea.syncPool, LINEA.endpoint, LINEA.send302, LINEA.lzDvn, ETHEREUM.originEid);
        }
    }

    struct Deposit {
        uint256 amountIn;
        uint256 amountOut;
        bytes lzMessage;
        bytes nativeMessage;
    }

    function test_Deposit() public {
        Deposit memory modeDeposit;
        Deposit memory lineaDeposit;

        modeDeposit.amountIn = 1e18;
        lineaDeposit.amountIn = 5e18;

        // Mode : deposit 1 ETH
        {
            vm.selectFork(mode.forkId);

            uint256 expectedAmount =
                L2ExchangeRateProvider(mode.rateProvider).getConversionAmount(mode.tokenIn, modeDeposit.amountIn);
            L2ModeSyncPoolETH(mode.syncPool).deposit{value: modeDeposit.amountIn}(
                mode.tokenIn, modeDeposit.amountIn, expectedAmount
            );

            assertEq(IERC20(mode.tokenOut).balanceOf(address(this)), expectedAmount, "test_Deposit::1");

            modeDeposit.amountOut = expectedAmount;
        }

        // Linea : deposit 5 ETH
        {
            vm.selectFork(linea.forkId);

            MockOracle(linea.rateOracle).setPrice(1.04e18);

            uint256 expectedAmount =
                L2ExchangeRateProvider(linea.rateProvider).getConversionAmount(linea.tokenIn, lineaDeposit.amountIn);
            L2LineaSyncPoolETH(linea.syncPool).deposit{value: lineaDeposit.amountIn}(
                linea.tokenIn, lineaDeposit.amountIn, expectedAmount
            );

            assertEq(IERC20(linea.tokenOut).balanceOf(address(this)), expectedAmount, "test_Deposit::2");

            lineaDeposit.amountOut = expectedAmount;
        }

        assertGt(
            modeDeposit.amountOut * 1e18 / modeDeposit.amountIn,
            lineaDeposit.amountOut * 1e18 / lineaDeposit.amountIn,
            "test_Deposit::3"
        );

        // Mode : Sync
        {
            vm.selectFork(mode.forkId);

            MessagingFee memory fee = MessagingFee(1e18, 0);

            vm.recordLogs();
            (uint256 unsyncedAmountIn, uint256 unsyncedAmountOut) =
                L2ModeSyncPoolETH(mode.syncPool).sync{value: fee.nativeFee}(mode.tokenIn, new bytes(0), fee);
            Vm.Log[] memory entries = vm.getRecordedLogs();

            modeDeposit.lzMessage = abi.encode(mode.tokenIn, unsyncedAmountIn, unsyncedAmountOut);

            bytes32 guid = 0x1898b42b4a72de6377cc270b97d75e5f277c7d8197631a64b486f87a70717a5b;
            bytes memory data = abi.encode(MODE.originEid, guid, mode.tokenIn, unsyncedAmountIn, unsyncedAmountOut);
            modeDeposit.nativeMessage = abi.encodeCall(IL1Receiver.onMessageReceived, data);

            assertTrue(
                _verifyEvents(entries, ILayerZeroEndpointV2.PacketSent.selector, modeDeposit.lzMessage),
                "test_Deposit::4"
            );
            assertTrue(
                _verifyEvents(entries, ModeEvent.MessagePassed.selector, modeDeposit.nativeMessage), "test_Deposit::5"
            );

            assertEq(unsyncedAmountIn, modeDeposit.amountIn, "test_Deposit::6");
            assertEq(unsyncedAmountOut, modeDeposit.amountOut, "test_Deposit::7");

            assertEq(mode.syncPool.balance, 0, "test_Deposit::8");
        }

        // Linea : Sync
        {
            vm.selectFork(linea.forkId);

            MessagingFee memory fee = MessagingFee(1e18, 0);

            vm.recordLogs();
            (uint256 unsyncedAmountIn, uint256 unsyncedAmountOut) = L2LineaSyncPoolETH(linea.syncPool).sync{
                value: fee.nativeFee + 0.0001e18
            }(linea.tokenIn, new bytes(0), fee);
            Vm.Log[] memory entries = vm.getRecordedLogs();

            lineaDeposit.lzMessage = abi.encode(linea.tokenIn, unsyncedAmountIn, unsyncedAmountOut);

            bytes32 guid = 0x7322e098c029c7ac8fe295d576fcbfc931f6c67386c52892021c4cc39afa9e37;
            bytes memory data = abi.encode(LINEA.originEid, guid, linea.tokenIn, unsyncedAmountIn, unsyncedAmountOut);
            lineaDeposit.nativeMessage = abi.encodeCall(IL1Receiver.onMessageReceived, data);

            assertTrue(
                _verifyEvents(entries, ILayerZeroEndpointV2.PacketSent.selector, lineaDeposit.lzMessage),
                "test_Deposit::9"
            );
            assertTrue(
                _verifyEvents(entries, IMessageService.MessageSent.selector, lineaDeposit.nativeMessage),
                "test_Deposit::10"
            );

            assertEq(unsyncedAmountIn, lineaDeposit.amountIn, "test_Deposit::11");
            assertEq(unsyncedAmountOut, lineaDeposit.amountOut, "test_Deposit::12");

            assertEq(linea.syncPool.balance, 0, "test_Deposit::13");
        }

        // Ethereum : Receive Mode lz message
        {
            vm.selectFork(ethereum.forkId);

            uint256 totalAssets = L1VaultETH(payable(ethereum.vault)).totalAssets();
            uint256 totalSupply = IERC20(ethereum.vault).totalSupply();

            vm.deal(ETHEREUM.endpoint, modeDeposit.amountIn);

            vm.prank(ETHEREUM.endpoint);
            L1SyncPoolETH(ethereum.syncPool).lzReceive(
                Origin(MODE.originEid, bytes32(uint256(uint160(address(mode.syncPool)))), 0),
                bytes32(0),
                modeDeposit.lzMessage,
                address(0),
                new bytes(0)
            );

            uint256 unbackedAmount = L1SyncPoolETH(ethereum.syncPool).getTotalUnbackedTokens();

            assertGt(unbackedAmount, 0, "test_Deposit::14");

            assertEq(
                L1VaultETH(payable(ethereum.vault)).totalAssets(),
                totalAssets + modeDeposit.amountIn,
                "test_Deposit::15"
            );
            assertEq(
                IERC20(ethereum.vault).totalSupply(),
                totalSupply + modeDeposit.amountOut - unbackedAmount,
                "test_Deposit::16"
            );

            assertEq(
                IERC20(ethereum.dummyETHs[CHAINS.MODE]).balanceOf(ethereum.vault),
                modeDeposit.amountIn,
                "test_Deposit::17"
            );
            assertEq(
                IERC20(ethereum.tokenOut).balanceOf(ethereum.oftToken),
                modeDeposit.amountOut - unbackedAmount,
                "test_Deposit::18"
            );
        }

        // Ethereum : Receive Linea lz message
        {
            vm.selectFork(ethereum.forkId);

            uint256 totalAssets = L1VaultETH(payable(ethereum.vault)).totalAssets();
            uint256 totalSupply = IERC20(ethereum.vault).totalSupply();

            vm.deal(ETHEREUM.endpoint, lineaDeposit.amountIn);

            vm.prank(ETHEREUM.endpoint);
            L1SyncPoolETH(ethereum.syncPool).lzReceive(
                Origin(LINEA.originEid, bytes32(uint256(uint160(address(linea.syncPool)))), 0),
                bytes32(0),
                lineaDeposit.lzMessage,
                address(0),
                new bytes(0)
            );

            assertEq(L1SyncPoolETH(ethereum.syncPool).getTotalUnbackedTokens(), 0, "test_Deposit::19");

            assertEq(
                L1VaultETH(payable(ethereum.vault)).totalAssets(),
                totalAssets + lineaDeposit.amountIn,
                "test_Deposit::20"
            );
            uint256 fee = IERC20(ethereum.tokenOut).balanceOf(ethereum.syncPool);
            assertGt(fee, 0, "test_Deposit::21");
            assertGt(
                IERC20(ethereum.vault).totalSupply(), totalSupply + lineaDeposit.amountOut + fee, "test_Deposit::22"
            );

            assertEq(
                IERC20(ethereum.dummyETHs[CHAINS.LINEA]).balanceOf(ethereum.vault),
                lineaDeposit.amountIn,
                "test_Deposit::23"
            );
            assertEq(
                IERC20(ethereum.tokenOut).balanceOf(ethereum.oftToken),
                modeDeposit.amountOut + lineaDeposit.amountOut,
                "test_Deposit::24"
            );
        }

        // Ethereum : Receive Mode native message
        {
            vm.selectFork(ethereum.forkId);

            vm.deal(MODE.L1messenger, modeDeposit.amountIn);

            uint256 totalAssets = L1VaultETH(payable(ethereum.vault)).totalAssets();
            uint256 totalSupply = IERC20(ethereum.vault).totalSupply();
            uint256 dummySupply = IERC20(ethereum.dummyETHs[CHAINS.MODE]).totalSupply();
            uint256 balance = ethereum.vault.balance;

            {
                address mockBridge = _deployContract(type(MockModeBridge).creationCode, new bytes(0));
                vm.etch(MODE.L1messenger, mockBridge.code);
            }

            MockModeBridge(MODE.L1messenger).relayMessage(
                0, mode.syncPool, ethereum.receivers[CHAINS.MODE], modeDeposit.amountIn, 0, modeDeposit.nativeMessage
            );

            assertEq(L1VaultETH(payable(ethereum.vault)).totalAssets(), totalAssets, "test_Deposit::25");
            assertEq(IERC20(ethereum.vault).totalSupply(), totalSupply, "test_Deposit::26");
            assertEq(
                IERC20(ethereum.dummyETHs[CHAINS.MODE]).totalSupply(),
                dummySupply - modeDeposit.amountIn,
                "test_Deposit::27"
            );
            assertEq(ethereum.vault.balance, balance + modeDeposit.amountIn, "test_Deposit::28");
        }

        // Ethereum : Receive Linea native message
        {
            vm.selectFork(ethereum.forkId);

            vm.deal(LINEA.L1messenger, lineaDeposit.amountIn);

            uint256 totalAssets = L1VaultETH(payable(ethereum.vault)).totalAssets();
            uint256 totalSupply = IERC20(ethereum.vault).totalSupply();
            uint256 dummySupply = IERC20(ethereum.dummyETHs[CHAINS.LINEA]).totalSupply();
            uint256 balance = ethereum.vault.balance;

            {
                address mockBridge = _deployContract(type(MockLineaBridge).creationCode, new bytes(0));
                vm.etch(LINEA.L1messenger, mockBridge.code);
            }

            MockLineaBridge(LINEA.L1messenger).claimMessage(
                linea.syncPool,
                ethereum.receivers[CHAINS.LINEA],
                0,
                lineaDeposit.amountIn,
                payable(address(0)),
                lineaDeposit.nativeMessage,
                0
            );

            assertEq(L1VaultETH(payable(ethereum.vault)).totalAssets(), totalAssets, "test_Deposit::29");
            assertEq(IERC20(ethereum.vault).totalSupply(), totalSupply, "test_Deposit::30");
            assertEq(
                IERC20(ethereum.dummyETHs[CHAINS.LINEA]).totalSupply(),
                dummySupply - lineaDeposit.amountIn,
                "test_Deposit::31"
            );
            assertEq(ethereum.vault.balance, balance + lineaDeposit.amountIn, "test_Deposit::32");
        }
    }

    function _verifyEvents(Vm.Log[] memory entries, bytes32 selector, bytes memory data)
        internal
        pure
        returns (bool found)
    {
        bytes memory event_;

        for (uint256 i = 0; i < entries.length; i++) {
            bytes32 s = bytes32(entries[i].topics[0]);

            if (s == selector) event_ = entries[i].data;
        }

        bytes32 hash = keccak256(data);
        uint256 length = data.length;

        for (uint256 i = 0; i < event_.length; i++) {
            bytes32 h;
            assembly {
                h := keccak256(add(add(event_, 0x20), i), length)
            }

            if (h == hash) return true;
        }
    }

    function _setUpOApp(
        address originSyncPool,
        address originEndpoint,
        address originSend302,
        address originDvn,
        uint32 dstEid
    ) internal {
        EnforcedOptionParam[] memory enforcedOptions = new EnforcedOptionParam[](1);
        enforcedOptions[0] = EnforcedOptionParam({
            eid: dstEid,
            msgType: 0,
            options: OptionsBuilder.newOptions().addExecutorLzReceiveOption(1_000_000, 0)
        });

        L2LineaSyncPoolETH(originSyncPool).setEnforcedOptions(enforcedOptions);

        SetConfigParam[] memory params = new SetConfigParam[](1);
        address[] memory requiredDVNs = new address[](1);
        requiredDVNs[0] = originDvn;

        UlnConfig memory ulnConfig = UlnConfig({
            confirmations: 64,
            requiredDVNCount: 1,
            optionalDVNCount: 0,
            optionalDVNThreshold: 0,
            requiredDVNs: requiredDVNs,
            optionalDVNs: new address[](0)
        });

        params[0] = SetConfigParam(dstEid, 2, abi.encode(ulnConfig));

        ILayerZeroEndpointV2(originEndpoint).setConfig(originSyncPool, originSend302, params);
    }

    receive() external payable {}
}
