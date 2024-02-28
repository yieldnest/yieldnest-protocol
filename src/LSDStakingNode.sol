// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IBeacon} from "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ILSDStakingNode} from "./interfaces/ILSDStakingNode.sol";
import {IynLSD} from "./interfaces/IynLSD.sol";
import {IStakingNode} from "./interfaces/IStakingNode.sol";
import {IStrategyManager} from "./external/eigenlayer/v0.1.0/interfaces/IStrategyManager.sol";
import {IStrategy} from "./external/eigenlayer/v0.1.0/interfaces/IStrategy.sol";

interface ILSDStakingNodeEvents {
    event DepositToEigenlayer(IERC20 indexed asset, IStrategy indexed strategy, uint amount, uint eigenShares);
}


contract LSDStakingNode is ILSDStakingNode, Initializable, ReentrancyGuardUpgradeable, ILSDStakingNodeEvents {

    error UnsupportedAsset(IERC20 token);
    error ZeroAmount();

   IynLSD public ynLSD;
   uint public nodeId;

   function initialize(Init memory init) public initializer {
       __ReentrancyGuard_init();
       ynLSD = init.ynLSD;
       nodeId = init.nodeId;
   }

   function depositAssetsToEigenlayer(
        IERC20[] memory assets,
        uint[] memory amounts
    )
        external
        nonReentrant
        onlyLSDRestakingManager
    {
        IStrategyManager strategyManager = ynLSD.strategyManager();

        for (uint i = 0; i < assets.length; i++) {
            IERC20 asset = assets[i];
            uint amount = amounts[i];
            IStrategy strategy = ynLSD.strategies(assets[i]);
            if (address(strategy) == address(0)) {
                revert UnsupportedAsset(asset);
            }

            ynLSD.retrieveAsset(nodeId, assets[i], amount);

            uint256 balance = asset.balanceOf(address(this));

            asset.approve(address(strategyManager), amount);

            uint eigenShares = strategyManager.depositIntoStrategy(IStrategy(strategy), asset, amount);
            emit DepositToEigenlayer(assets[i], strategy, amount, eigenShares);
        }
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  MODIFIERS  ---------------------------------------
    //--------------------------------------------------------------------------------------

    modifier onlyLSDRestakingManager() {
        require(ynLSD.hasLSDRestakingManagerRole(msg.sender), "Caller is not an LSD restaking manager");
        _;
    }

    //--------------------------------------------------------------------------------------
    //----------------------------------  BEACON IMPLEMENTATION  ---------------------------
    //--------------------------------------------------------------------------------------

    /**
      Beacons slot value is defined here:
      https://github.com/OpenZeppelin/openzeppelin-contracts/blob/afb20119b33072da041c97ea717d3ce4417b5e01/contracts/proxy/ERC1967/ERC1967Upgrade.sol#L142
     */
    function implementation() public view returns (address) {
        bytes32 slot = bytes32(uint256(keccak256('eip1967.proxy.beacon')) - 1);
        address implementationVariable;
        assembly {
            implementationVariable := sload(slot)
        }

        IBeacon beacon = IBeacon(implementationVariable);
        return beacon.implementation();
    }
}
