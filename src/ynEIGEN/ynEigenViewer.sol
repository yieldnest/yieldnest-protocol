// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {IERC20, IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {IynEigen} from "../interfaces/IynEigen.sol";
import {IRateProvider} from "../interfaces/IRateProvider.sol";
import {ITokenStakingNodesManager,ITokenStakingNode} from "../interfaces/ITokenStakingNodesManager.sol";

import {AssetRegistry} from "./AssetRegistry.sol";

contract ynEigenViewer {
    
    struct AssetInfo {
        address asset;
        string name;
        string symbol;
        uint256 ratioOfTotalAssets;
        uint256 totalBalance;
    }
    
    AssetRegistry public immutable assetRegistry;
    IynEigen public immutable ynEIGEN;
    ITokenStakingNodesManager public immutable tokenStakingNodesManager;
    IRateProvider public immutable rateProvider;

    uint256 public constant DECIMALS = 1_000_000;
    uint256 public constant UNIT = 1 ether;

    constructor(address _assetRegistry, address _ynEIGEN, address _tokenStakingNodesManager, address _rateProvider) {
        assetRegistry = AssetRegistry(_assetRegistry);
        ynEIGEN = IynEigen(_ynEIGEN);
        tokenStakingNodesManager = ITokenStakingNodesManager(_tokenStakingNodesManager);
        rateProvider = IRateProvider(_rateProvider);
    }

    function getAllStakingNodes() external view returns (ITokenStakingNode[] memory) {
        return tokenStakingNodesManager.getAllNodes();
    }

    function getYnEigenAssets() external view returns (AssetInfo[] memory _assetsInfo) {
        IERC20[] memory _assets = assetRegistry.getAssets();
        uint256 _assetsLength = _assets.length;
        _assetsInfo = new AssetInfo[](_assetsLength);

        uint256 _totalAssets = ynEIGEN.totalAssets();
        for (uint256 i = 0; i < _assetsLength; ++i) {
            uint256 _balance = assetRegistry.convertToUnitOfAccount(_assets[i], ynEIGEN.assetBalance(_assets[i]));
            _assetsInfo[i] = AssetInfo({
                asset: address(_assets[i]),
                name: IERC20Metadata(address(_assets[i])).name(),
                symbol: IERC20Metadata(address(_assets[i])).symbol(),
                ratioOfTotalAssets: (_balance > 0 && _totalAssets > 0) ? _balance * DECIMALS / _totalAssets : 0,
                totalBalance: _balance
            });
        }
    }
}