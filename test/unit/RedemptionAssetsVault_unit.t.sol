// SPDX-License-Identifier: BSD 3-Clause
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {RedemptionAssetsVault} from "src/ynEIGEN/RedemptionAssetsVault.sol";
import {IAssetRegistry} from "src/interfaces/IAssetRegistry.sol";
import {IynEigen} from "src/interfaces/IynEigen.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {TransparentUpgradeableProxy} from "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ETH_ASSET} from "src/Constants.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}
    
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MockAssetRegistry is IAssetRegistry {
    mapping(address => bool) public supportedAssets;
    IERC20[] public assets;
    
    mapping(address => uint256) public assetRates;

    function addAsset(IERC20 asset) external {
        supportedAssets[address(asset)] = true;
        assets.push(asset);
        // Default rate of 1:1
        assetRates[address(asset)] = 1e18;
    }
    
    function setAssetRate(IERC20 asset, uint256 rate) external {
        require(supportedAssets[address(asset)], "Asset not supported");
        assetRates[address(asset)] = rate;
    }

    function assetIsSupported(IERC20 asset) external view returns (bool) {
        return supportedAssets[address(asset)];
    }
    
    function getAssets() external view returns (IERC20[] memory) {
        return assets;
    }
    
    function convertToUnitOfAccount(IERC20 asset, uint256 amount) external view returns (uint256) {
        require(supportedAssets[address(asset)], "Asset not supported");
        return (amount * assetRates[address(asset)]) / 1e18;
    }
    
    function convertFromUnitOfAccount(IERC20 asset, uint256 amount) external view returns (uint256) {
        require(supportedAssets[address(asset)], "Asset not supported");
        return (amount * 1e18) / assetRates[address(asset)];
    }

    function assetData(IERC20) external pure returns (AssetData memory) {
        revert("unexpected call to assetData");
    }

    function disableAsset(IERC20) external pure {
        revert("unexpected call to disableAsset");
    }

    function deleteAsset(IERC20) external pure {
        revert("unexpected call to deleteAsset");
    }

    function totalAssets() external view returns (uint256) {
        return assets.length;
    }
}

contract RedemptionAssetsVaultUnitTest is Test {
    RedemptionAssetsVault public vault;
    MockAssetRegistry public assetRegistry;
    MockERC20 public token1;
    MockERC20 public token2;
    MockERC20 public token3;
    IynEigen public mockYnEigen;
    
    address public admin = address(0x1);
    address public redeemer = address(0x2);
    
    function setUp() public {
        // Deploy mock tokens
        token1 = new MockERC20("Mock Token 1", "MT1");
        token2 = new MockERC20("Mock Token 2", "MT2"); 
        token3 = new MockERC20("Mock Token 3", "MT3");
        
        // Deploy and setup asset registry
        assetRegistry = new MockAssetRegistry();
        assetRegistry.addAsset(IERC20(address(token1)));
        assetRegistry.addAsset(IERC20(address(token2)));
        assetRegistry.addAsset(IERC20(address(token3)));
        
        mockYnEigen = IynEigen(address(0x3));
        
        // Deploy vault implementation and proxy
        RedemptionAssetsVault vaultImplementation = new RedemptionAssetsVault();
        TransparentUpgradeableProxy vaultProxy = new TransparentUpgradeableProxy(
            address(vaultImplementation),
            admin,
            ""
        );
        vault = RedemptionAssetsVault(address(vaultProxy));
        
        // Initialize vault
        RedemptionAssetsVault.Init memory init = RedemptionAssetsVault.Init({
            admin: admin,
            redeemer: redeemer,
            ynEigen: mockYnEigen,
            assetRegistry: IAssetRegistry(address(assetRegistry))
        });
        
        vault.initialize(init);
    }

    function test_deposit(uint256 depositAmount) public {
        vm.assume(depositAmount > 0 && depositAmount <= 1000 ether);
        
        // Mint tokens to this contract
        token1.mint(address(this), depositAmount);
        
        // Approve vault to spend tokens
        token1.approve(address(vault), depositAmount);
        
        // Initial balance should be 0
        assertEq(vault.balances(address(token1)), 0);
        
        // Deposit tokens
        vault.deposit(depositAmount, address(token1));
        
        // Check vault balance is updated
        assertEq(vault.balances(address(token1)), depositAmount);
        
        // Check tokens were transferred
        assertEq(token1.balanceOf(address(vault)), depositAmount);
    }

    function test_deposit_revertIfAssetNotSupported() public {
        uint256 depositAmount = 1 ether;
        MockERC20 unsupportedToken = new MockERC20("Unsupported Token", "UT");
        
        // Mint tokens to this contract
        unsupportedToken.mint(address(this), depositAmount);
        
        // Approve vault to spend tokens
        unsupportedToken.approve(address(vault), depositAmount);
        
        // Try to deposit unsupported token
        vm.expectRevert(RedemptionAssetsVault.AssetNotSupported.selector);
        vault.deposit(depositAmount, address(unsupportedToken));
    }

    function test_previewClaim_multipleAssets(
        uint256 amount1,
        uint256 amount2,
        uint256 amount3,
        uint256 claimAmount
    ) public {
        vm.assume(amount1 > 0 && amount1 <= 1000 ether);
        vm.assume(amount2 > 0 && amount2 <= 1000 ether);
        vm.assume(amount3 > 0 && amount3 <= 1000 ether);
        
        uint256 totalAmount = amount1 + amount2 + amount3;
        vm.assume(claimAmount > 0 && claimAmount <= totalAmount);
        
        token1.mint(address(this), amount1);
        token2.mint(address(this), amount2);
        token3.mint(address(this), amount3);

        token1.approve(address(vault), amount1);
        token2.approve(address(vault), amount2);
        token3.approve(address(vault), amount3);

        vault.deposit(amount1, address(token1));
        vault.deposit(amount2, address(token2));
        vault.deposit(amount3, address(token3));

        // Preview claim for claim amount
        (IERC20[] memory assets, uint256[] memory amounts) = vault.previewClaim(claimAmount);

        // Should return amounts based on available balances
        assertEq(assets.length, 3);
        assertEq(amounts.length, 3);
        
        uint256 remainingClaim = claimAmount;
        if (amount1 >= remainingClaim) {
            assertEq(amounts[0], remainingClaim);
            assertEq(amounts[1], 0);
            assertEq(amounts[2], 0);
        } else {
            assertEq(amounts[0], amount1);
            remainingClaim -= amount1;
            if (amount2 >= remainingClaim) {
                assertEq(amounts[1], remainingClaim);
                assertEq(amounts[2], 0);
            } else {
                assertEq(amounts[1], amount2);
                remainingClaim -= amount2;
                assertEq(amounts[2], remainingClaim);
            }
        }
    }

    function test_previewClaim_revertInsufficientBalance() public {
        uint256 depositAmount = 5 ether;
        uint256 claimAmount = 10 ether;
        
        // Deposit token1
        token1.mint(address(this), depositAmount);
        token1.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, address(token1));

        // Try to preview claim for more than available
        vm.expectRevert(abi.encodeWithSelector(
            RedemptionAssetsVault.InsufficientAssetBalance.selector,
            ETH_ASSET,
            claimAmount,
            depositAmount
        ));
        vault.previewClaim(claimAmount);
    }

    function test_transferRedemptionAssets_matchesPreview(
        uint256 amount1,
        uint256 amount2,
        uint256 amount3,
        uint256 claimAmount
    ) public {
        vm.assume(amount1 > 0 && amount1 <= 1000 ether);
        vm.assume(amount2 > 0 && amount2 <= 1000 ether);
        vm.assume(amount3 > 0 && amount3 <= 1000 ether);
        
        uint256 totalAmount = amount1 + amount2 + amount3;
        vm.assume(claimAmount > 0 && claimAmount <= totalAmount);
        
        token1.mint(address(this), amount1);
        token2.mint(address(this), amount2);
        token3.mint(address(this), amount3);
        
        token1.approve(address(vault), amount1);
        token2.approve(address(vault), amount2);
        token3.approve(address(vault), amount3);
        
        vault.deposit(amount1, address(token1));
        vault.deposit(amount2, address(token2));
        vault.deposit(amount3, address(token3));


        // Get preview of claim
        (IERC20[] memory previewAssets, uint256[] memory previewAmounts) = vault.previewClaim(claimAmount);

        // Do actual withdrawal
        vm.prank(redeemer);
        vault.transferRedemptionAssets(redeemer, claimAmount, "");


        // Get actual withdrawal amounts by checking redeemer balances
        uint256[] memory withdrawnAmounts = new uint256[](3);
        withdrawnAmounts[0] = token1.balanceOf(redeemer);
        withdrawnAmounts[1] = token2.balanceOf(redeemer);
        withdrawnAmounts[2] = token3.balanceOf(redeemer);

        assertEq(withdrawnAmounts.length, previewAmounts.length, "Amount array lengths should match");

        for(uint256 i = 0; i < withdrawnAmounts.length; i++) {
            assertEq(withdrawnAmounts[i], previewAmounts[i], "Withdrawn amounts should match preview");
        }
    }

    function test_transferRedemptionAssets_revertIfNotRedeemer() public {
        uint256 amount = 1 ether;
        token1.mint(address(this), amount);
        token1.approve(address(vault), amount);
        vault.deposit(amount, address(token1));

        // Try to transfer as non-redeemer
        vm.expectRevert(abi.encodeWithSelector(
            RedemptionAssetsVault.NotRedeemer.selector,
            address(this)
        ));
        vault.transferRedemptionAssets(address(this), amount, "");
    }

    function test_withdrawRedemptionAssets_revertIfNotRedeemer() public {
        uint256 amount = 1 ether;
        token1.mint(address(this), amount);
        token1.approve(address(vault), amount);
        vault.deposit(amount, address(token1));

        // Try to withdraw as non-redeemer
        vm.expectRevert(abi.encodeWithSelector(
            RedemptionAssetsVault.NotRedeemer.selector,
            address(this)
        ));
        vault.withdrawRedemptionAssets(amount);
    }

    function test_transferRedemptionAssets_revertIfPaused() public {
        uint256 amount = 1 ether;
        token1.mint(address(this), amount);
        token1.approve(address(vault), amount);
        vault.deposit(amount, address(token1));

        // Pause contract
        vm.prank(admin);
        vault.pause();

        // Try to transfer when paused
        vm.prank(redeemer);
        vm.expectRevert(RedemptionAssetsVault.ContractPaused.selector);
        vault.transferRedemptionAssets(redeemer, amount, "");
    }

    function test_withdrawRedemptionAssets_revertIfPaused() public {
        uint256 amount = 1 ether;
        token1.mint(address(this), amount);
        token1.approve(address(vault), amount);
        vault.deposit(amount, address(token1));

        // Pause contract
        vm.prank(admin);
        vault.pause();

        // Try to withdraw when paused
        vm.prank(redeemer);
        vm.expectRevert(RedemptionAssetsVault.ContractPaused.selector);
        vault.withdrawRedemptionAssets(amount);
    }
}
