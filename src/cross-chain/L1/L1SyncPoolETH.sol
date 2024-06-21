// SPDX-License-Identifier: LZBL-1.2
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IDummyToken} from "@layerzero/contracts/interfaces/IDummyToken.sol";
import {L1BaseSyncPoolUpgradeable, Constants} from "@layerzero/contracts/L1/L1BaseSyncPoolUpgradeable.sol";
import {IL1Vault} from "../mock/interfaces/IL1Vault.sol";

contract L1SyncPoolETH is L1BaseSyncPoolUpgradeable {
    error L1SyncPoolETH__OnlyETH();
    error L1SyncPoolETH__InvalidAmountIn();
    error L1SyncPoolETH__UnsetDummyToken();

    IL1Vault private _vault;

    mapping(uint32 => IDummyToken) private _dummyTokens;

    event VaultSet(address vault);
    event DummyTokenSet(uint32 originEid, address dummyToken);

    /**
     * @dev Constructor for L1 Sync Pool ETH
     * @param endpoint Address of the LayerZero endpoint
     */
    constructor(address endpoint) L1BaseSyncPoolUpgradeable(endpoint) {}

    /**
     * @dev Initialize the contract
     * @param vault Address of the vault
     * @param tokenOut Address of the main token
     * @param lockBox Address of the lock box
     * @param owner Address of the owner
     */
    function initialize(address vault, address tokenOut, address lockBox, address owner) external initializer {
        __L1BaseSyncPool_init(tokenOut, lockBox, owner);
        __Ownable_init(owner);

        _setVault(vault);
    }

    /**
     * @dev Get the vault address
     * @return The vault address
     */
    function getVault() public view returns (address) {
        return address(_vault);
    }

    /**
     * @dev Get the dummy token address for a given origin EID
     * @param originEid Origin EID
     * @return The dummy token address
     */
    function getDummyToken(uint32 originEid) public view virtual returns (address) {
        return address(_dummyTokens[originEid]);
    }

    /**
     * @dev Set the vault address
     * @param vault The vault address
     */
    function setVault(address vault) public onlyOwner {
        _setVault(vault);
    }

    /**
     * @dev Set the dummy token address for a given origin EID
     * @param originEid Origin EID
     * @param dummyToken The dummy token address
     */
    function setDummyToken(uint32 originEid, address dummyToken) public onlyOwner {
        _setDummyToken(originEid, dummyToken);
    }

    /**
     * @dev Internal function to set the vault address
     * @param vault The vault address
     */
    function _setVault(address vault) internal {
        _vault = IL1Vault(vault);

        emit VaultSet(vault);
    }

    /**
     * @dev Internal function to set the dummy token address for a given origin EID
     * @param originEid Origin EID
     * @param dummyToken The dummy token address
     */
    function _setDummyToken(uint32 originEid, address dummyToken) internal {
        _dummyTokens[originEid] = IDummyToken(dummyToken);

        emit DummyTokenSet(originEid, dummyToken);
    }

    /**
     * @dev Internal function to anticipate a deposit
     * Will mint the dummy tokens and deposit them to the L1 deposit pool
     * Will revert if:
     * - The token in is not ETH
     * - The dummy token is not set
     * @param originEid Origin EID
     * @param tokenIn Address of the token in
     * @param amountIn Amount in
     * @return actualAmountOut The actual amount of token received
     */
    function _anticipatedDeposit(uint32 originEid, bytes32, address tokenIn, uint256 amountIn, uint256)
        internal
        virtual
        override
        returns (uint256 actualAmountOut)
    {
        if (tokenIn != Constants.ETH_ADDRESS) revert L1SyncPoolETH__OnlyETH();

        IERC20 tokenOut = IERC20(getTokenOut());

        IL1Vault vault = _vault;
        IDummyToken dummyToken = _dummyTokens[originEid];

        if (address(dummyToken) == address(0)) revert L1SyncPoolETH__UnsetDummyToken();

        uint256 balanceBefore = tokenOut.balanceOf(address(this));

        dummyToken.mint(address(this), amountIn);
        dummyToken.approve(address(vault), amountIn);

        vault.depositDummyETH(address(dummyToken), amountIn);

        return tokenOut.balanceOf(address(this)) - balanceBefore;
    }

    /**
     * @dev Internal function to finalize a deposit
     * Will swap the dummy tokens for the actual ETH
     * Will revert if:
     * - The token in is not ETH
     * - The amount in is not equal to the value
     * - The dummy token is not set
     * @param originEid Origin EID
     * @param tokenIn Address of the token in
     * @param amountIn Amount in
     */
    function _finalizeDeposit(uint32 originEid, bytes32, address tokenIn, uint256 amountIn, uint256)
        internal
        virtual
        override
    {
        if (tokenIn != Constants.ETH_ADDRESS) revert L1SyncPoolETH__OnlyETH();
        if (amountIn != msg.value) revert L1SyncPoolETH__InvalidAmountIn();

        IL1Vault vault = _vault;
        IDummyToken dummyToken = _dummyTokens[originEid];

        if (address(dummyToken) == address(0)) revert L1SyncPoolETH__UnsetDummyToken();

        uint256 dummyBalance = dummyToken.balanceOf(address(vault));
        uint256 ethBalance = address(this).balance;

        uint256 swapAmount = ethBalance > dummyBalance ? dummyBalance : ethBalance;

        vault.swapDummyETH{value: swapAmount}(address(dummyToken), swapAmount);

        dummyToken.burn(swapAmount);
    }
}
