// SPDX-License-Identifier: LZBL-1.2
pragma solidity ^0.8.20;

import {ERC4626, ERC20, IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {Constants} from "@layerzero/contracts/libraries/Constants.sol";
import {IL1Vault} from "./interfaces/IL1Vault.sol";

/**
 * This contract is not part of the syncpool, but serves as an example for the interaction
 * between the syncpool and the vault.
 */
contract L1VaultETH is ERC4626, ReentrancyGuard, AccessControl, IL1Vault {
    using EnumerableSet for EnumerableSet.AddressSet;

    uint256 public ethBalance;

    event DepositDummyETH(address indexed token, address indexed syncpool, uint256 assets, uint256 shares);

    bytes32 public constant SYNC_POOL_ROLE = keccak256("SYNC_POOL_ROLE");

    EnumerableSet.AddressSet private _dummyETHs;

    constructor() ERC4626(IERC20(Constants.ETH_ADDRESS)) ERC20("L1VaultETH", "vETH") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function addDummyETH(address token) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_dummyETHs.add(token), "L1Vault: dummy token already added");
    }

    function removeDummyETH(address token) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_dummyETHs.remove(token), "L1Vault: dummy token not found");
    }

    function depositDummyETH(address token, uint256 assets)
        public
        nonReentrant
        onlyRole(SYNC_POOL_ROLE)
        returns (uint256)
    {
        require(_dummyETHs.contains(token), "L1Vault: dummy token not set");

        uint256 maxAssets = maxDeposit(msg.sender);
        if (assets > maxAssets) {
            revert ERC4626ExceededMaxDeposit(msg.sender, assets, maxAssets);
        }

        uint256 totalAssetsBefore = totalAssets();

        uint256 shares = previewDeposit(assets);

        SafeERC20.safeTransferFrom(IERC20(token), msg.sender, address(this), assets);

        _mint(msg.sender, shares);

        emit DepositDummyETH(token, msg.sender, assets, shares);

        require(totalAssets() >= totalAssetsBefore + assets, "L1Vault: invalid dummy deposit");

        return shares;
    }

    function swapDummyETH(address token, uint256 amount)
        public
        payable
        nonReentrant
        onlyRole(SYNC_POOL_ROLE)
        returns (uint256)
    {
        require(_dummyETHs.contains(token), "L1Vault: dummy token not set");
        require(msg.value == amount, "L1Vault: invalid ETH amount");

        uint256 totalAssetsBefore = totalAssets();

        ethBalance += amount;
        SafeERC20.safeTransfer(IERC20(token), msg.sender, amount);

        require(totalAssets() == totalAssetsBefore, "L1Vault: invalid dummy swap");

        return amount;
    }

    function _sendETH(address receiver, uint256 amount) internal {
        (bool success,) = receiver.call{value: amount}("");
        require(success, "L1Vault: ETH transfer failed");
    }

    receive() external payable {
        ethBalance += msg.value;
    }

    /**
     * ERC4626 changes
     */
    function depositETH(uint256 assets, address receiver) public payable nonReentrant returns (uint256) {
        return super.deposit(assets, receiver);
    }

    function mintETH(uint256 shares, address receiver) public payable nonReentrant returns (uint256) {
        return super.mint(shares, receiver);
    }

    function totalAssets() public view override returns (uint256 balance) {
        balance = ethBalance;

        address[] memory dummyETHs = _dummyETHs.values();

        for (uint256 i = 0; i < dummyETHs.length; i++) {
            balance += IERC20(dummyETHs[i]).balanceOf(address(this));
        }
    }

    function deposit(uint256, address) public pure override returns (uint256) {
        revert("L1Vault: use depositETH");
    }

    function mint(uint256, address) public pure override returns (uint256) {
        revert("L1Vault: use mintETH");
    }

    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal override {
        require(msg.value >= assets, "L1Vault: insufficient ETH sent");
        if (msg.value > assets) _sendETH(caller, msg.value - assets);

        ethBalance += assets;
        _mint(receiver, shares);

        emit Deposit(caller, receiver, assets, shares);
    }

    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares)
        internal
        override
    {
        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }

        ethBalance -= assets;
        _burn(owner, shares);

        _sendETH(receiver, assets);

        emit Withdraw(caller, receiver, owner, assets, shares);
    }
}
