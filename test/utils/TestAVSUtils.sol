// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {ynEigenIntegrationBaseTest} from "test/integration/ynEIGEN/ynEigenIntegrationBaseTest.sol";
import {TestAssetUtils} from "test/utils/TestAssetUtils.sol";
import {IStrategy} from "lib/eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {ITokenStakingNode} from "src/interfaces/ITokenStakingNode.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {ISignatureUtilsMixinTypes} from "lib/eigenlayer-contracts/src/contracts/interfaces/ISignatureUtilsMixin.sol";
import {MockAVSRegistrar} from "lib/eigenlayer-contracts/src/test/mocks/MockAVSRegistrar.sol";
import {IAllocationManagerTypes} from "lib/eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {AllocationManagerStorage} from "lib/eigenlayer-contracts/src/contracts/core/AllocationManagerStorage.sol";
import {OperatorSet} from "lib/eigenlayer-contracts/src/contracts/libraries/OperatorSetLib.sol";



contract TestAVSUtils  {


    struct AVSSetupParams {
        address avs;
        address operator;
        address delegator;
        ITokenStakingNode tokenStakingNode;
        IStrategy[] strategies;
        uint32 operatorSetId;
        string metadataURI;
    }

    /**
     * @notice Sets up an AVS, registers an operator, and allocates shares
     * @param vm The forge VM instance
     * @param eigenLayer The EigenLayer instance
     * @param params The parameters for AVS setup
     */
    function setupAVSAndRegisterOperator(
        Vm vm,
        IEigenLayerContracts eigenLayer,
        AVSSetupParams memory params
    ) public {
        // Update metadata URI for the AVS
        vm.prank(params.avs);
        eigenLayer.allocationManager.updateAVSMetadataURI(params.avs, params.metadataURI);

        // Register operator if not already registered
        if (!eigenLayer.delegationManager.isOperator(params.operator)) {
            vm.prank(params.operator);
            eigenLayer.delegationManager.registerAsOperator(address(0), 0, "ipfs://some-ipfs-hash");
        }

        // Delegate to operator
        ISignatureUtilsMixinTypes.SignatureWithExpiry memory signature;
        bytes32 approverSalt;
        vm.prank(params.delegator);
        params.tokenStakingNode.delegate(params.operator, signature, approverSalt);

        // Create operator sets for the AVS
        IAllocationManagerTypes.CreateSetParams[] memory createSetParams = new IAllocationManagerTypes.CreateSetParams[](1);
        createSetParams[0] = IAllocationManagerTypes.CreateSetParams({
            operatorSetId: params.operatorSetId,
            strategies: params.strategies
        });
        
        vm.prank(params.avs);
        eigenLayer.allocationManager.createOperatorSets(params.avs, createSetParams);

        // Register for operator set
        IAllocationManagerTypes.RegisterParams memory registerParams = IAllocationManagerTypes.RegisterParams({
            avs: params.avs,
            operatorSetIds: new uint32[](1),
            data: new bytes(0)
        });
        registerParams.operatorSetIds[0] = params.operatorSetId;
        vm.prank(params.operator);
        eigenLayer.allocationManager.registerForOperatorSets(params.operator, registerParams);
    }

    /**
     * @notice Allocates shares for an operator to an AVS
     * @param vm The forge VM instance
     * @param eigenLayer The EigenLayer instance
     * @param operator The operator address
     * @param avs The AVS address
     * @param operatorSetId The operator set ID
     * @param strategies The strategies to allocate
     * @param magnitudes The magnitudes to allocate for each strategy
     */
    function allocateShares(
        Vm vm,
        IEigenLayerContracts eigenLayer,
        address operator,
        address avs,
        uint32 operatorSetId,
        IStrategy[] memory strategies,
        uint64[] memory magnitudes
    ) public {
        require(strategies.length == magnitudes.length, "Strategies and magnitudes length mismatch");
        
        IAllocationManagerTypes.AllocateParams[] memory allocateParams = new IAllocationManagerTypes.AllocateParams[](1);
        allocateParams[0] = IAllocationManagerTypes.AllocateParams({
            operatorSet: OperatorSet({
                avs: avs,
                id: operatorSetId
            }),
            strategies: strategies,
            newMagnitudes: magnitudes
        });
        
        vm.prank(operator);
        eigenLayer.allocationManager.modifyAllocations(operator, allocateParams);
    }

    /**
     * @notice Slashes an operator for a specific strategy
     * @param vm The forge VM instance
     * @param eigenLayer The EigenLayer instance
     * @param avs The AVS address
     * @param operator The operator address
     * @param operatorSetId The operator set ID
     * @param strategy The strategy to slash
     * @param wadsToSlash The amount to slash in WAD (18 decimals)
     * @param description The description of the slashing
     */
    function slashOperator(
        Vm vm,
        IEigenLayerContracts eigenLayer,
        address avs,
        address operator,
        uint32 operatorSetId,
        IStrategy strategy,
        uint256 wadsToSlash,
        string memory description
    ) public {
        IAllocationManagerTypes.SlashingParams memory slashingParams = IAllocationManagerTypes.SlashingParams({
            operator: operator,
            operatorSetId: operatorSetId,
            strategies: new IStrategy[](1),
            wadsToSlash: new uint256[](1),
            description: description
        });
        slashingParams.strategies[0] = strategy;
        slashingParams.wadsToSlash[0] = wadsToSlash;
        
        vm.prank(avs);
        eigenLayer.allocationManager.slashOperator(avs, slashingParams);
    }
}