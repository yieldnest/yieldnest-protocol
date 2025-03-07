// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IERC20, IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IwstETH} from "../external/lido/IwstETH.sol";
import {IynEigen} from "../interfaces/IynEigen.sol";
import {IRateProvider} from "../interfaces/IRateProvider.sol";
import {ITokenStakingNodesManager,ITokenStakingNode} from "../interfaces/ITokenStakingNodesManager.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {AssetRegistry} from "./AssetRegistry.sol";
import {IEigenStrategyManager} from "../interfaces/IEigenStrategyManager.sol";


contract ynEigenViewer {

    //--------------------------------------------------------------------------------------
    //----------------------------------  STRUCTS  -----------------------------------------
    //--------------------------------------------------------------------------------------
    
    struct AssetInfo {
        address asset;
        string name;
        string symbol;
        uint256 rate;
        uint256 ratioOfTotalAssets;
        uint256 totalBalanceInUnitOfAccount;
        uint256 totalBalanceInAsset;
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  ERRORS  ------------------------------------------
    //--------------------------------------------------------------------------------------

    error ArrayLengthMismatch(uint256 expected, uint256 actual);

    //--------------------------------------------------------------------------------------
    //----------------------------------  CONSTANTS  ---------------------------------------
    //--------------------------------------------------------------------------------------

    uint256 public constant DECIMALS = 1_000_000;
    uint256 public constant UNIT = 1 ether;

    //--------------------------------------------------------------------------------------
    //----------------------------------  VARIABLES  ---------------------------------------
    //--------------------------------------------------------------------------------------
    
    /* solhint-disable immutable-vars-naming */
    AssetRegistry public immutable assetRegistry;
    IynEigen public immutable ynEIGEN;
    ITokenStakingNodesManager public immutable tokenStakingNodesManager;
    IRateProvider public immutable rateProvider;
    /* solhint-enable immutable-vars-naming */

    //--------------------------------------------------------------------------------------
    //----------------------------------  INITIALIZATION  ----------------------------------
    //--------------------------------------------------------------------------------------

    constructor(address _assetRegistry, address _ynEIGEN, address _tokenStakingNodesManager, address _rateProvider) {
        assetRegistry = AssetRegistry(_assetRegistry);
        ynEIGEN = IynEigen(_ynEIGEN);
        tokenStakingNodesManager = ITokenStakingNodesManager(_tokenStakingNodesManager);
        rateProvider = IRateProvider(_rateProvider);
    }

    /**
     * @notice Retrieves all staking nodes from the TokenStakingNodesManager
     * @dev This function calls the getAllNodes() function of the tokenStakingNodesManager contract
     * @return An array of ITokenStakingNode interfaces representing all staking nodes
     */
    function getAllStakingNodes() external view returns (ITokenStakingNode[] memory) {
        return tokenStakingNodesManager.getAllNodes();
    }

    /**
     * @notice Retrieves information about all assets in the ynEigen system
     * @dev This function fetches asset data from the asset registry and ynEigen system
     *      and computes various metrics for each asset
     * @return _assetsInfo An array of AssetInfo structs containing detailed information about each asset
     */
    function getYnEigenAssets() external view returns (AssetInfo[] memory _assetsInfo) {
        IERC20[] memory _assets = assetRegistry.getAssets();
        uint256 _assetsLength = _assets.length;
        _assetsInfo = new AssetInfo[](_assetsLength);

        uint256[] memory assetBalances = assetRegistry.getAllAssetBalances();
        // Assert that the lengths of _assets and assetBalances are the same
        if (_assetsLength != assetBalances.length) {
            revert ArrayLengthMismatch(_assetsLength, assetBalances.length);
        }

        uint256 _totalAssets = ynEIGEN.totalAssets();

        for (uint256 i = 0; i < _assetsLength; ++i) {
            uint256 assetBalance = assetBalances[i];
            uint256 _balance = assetRegistry.convertToUnitOfAccount(_assets[i], assetBalance);
            _assetsInfo[i] = AssetInfo({
                asset: address(_assets[i]),
                name: IERC20Metadata(address(_assets[i])).name(),
                symbol: IERC20Metadata(address(_assets[i])).symbol(),
                rate: rateProvider.rate(address(_assets[i])),
                ratioOfTotalAssets: (_balance > 0 && _totalAssets > 0) ? _balance * DECIMALS / _totalAssets : 0,
                totalBalanceInUnitOfAccount: _balance,
                totalBalanceInAsset: assetBalance
            });
        }
    }

    function previewDeposit(IERC20 asset, uint256 amount) external view returns (uint256 shares) {
        IEigenStrategyManager eigenStrategyManager = IEigenStrategyManager(ynEIGEN.yieldNestStrategyManager());
        address oETH = address(eigenStrategyManager.oETH());
        address stETH = address(eigenStrategyManager.stETH());
        address woETH = address(eigenStrategyManager.woETH());
        address wstETH = address(eigenStrategyManager.wstETH());

        if (address(asset) == oETH) {
            // Convert oETH to woETH
            uint256 woETHAmount = IERC4626(woETH).convertToShares(amount);
            return ynEIGEN.previewDeposit(IERC20(woETH), woETHAmount);
        } else if (address(asset) == stETH) {
            // Convert stETH to wstETH
            uint256 wstETHAmount = IwstETH(wstETH).getWstETHByStETH(amount);
            return ynEIGEN.previewDeposit(IERC20(wstETH), wstETHAmount);
        } else {
            // For all other assets, use the standard previewDeposit function
            return ynEIGEN.previewDeposit(IERC20(asset), amount);
        }
    }
    
    function getRate() external view returns (uint256) {
        uint256 _totalSupply = ynEIGEN.totalSupply();
        uint256 _totalAssets = ynEIGEN.totalAssets();
        if (_totalSupply == 0 || _totalAssets == 0) return 1 ether;
        return 1 ether * _totalAssets / _totalSupply;
    }
}