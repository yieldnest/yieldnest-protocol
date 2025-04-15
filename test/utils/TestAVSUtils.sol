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
import {Vm} from "forge-std/Vm.sol";
import {IDelegationManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IAllocationManager} from "lib/eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";

contract TestAVSUtils  {


    struct AVSSetupParams {
        address avs;
        address operator;
        address delegator;
        ITokenStakingNode tokenStakingNode;
        IStrategy[] strategies;
        uint32 operatorSetId;
        string metadataURI;
        uint64[] magnitudes;
    }
    /**
     * @notice Sets up an AVS, registers an operator, and allocates shares
     * @param vm The forge VM instance
     * @param delegationManager The EigenLayer delegation manager
     * @param allocationManager The EigenLayer allocation manager
     * @param params The parameters for AVS setup including:
     *        - avs: Address of the AVS
     *        - operator: Address of the operator to register
     *        - delegator: Address of the delegator
     *        - tokenStakingNode: The token staking node contract
     *        - strategies: Array of strategies to allocate
     *        - operatorSetId: ID for the operator set
     *        - metadataURI: Metadata URI for the AVS
     *        - magnitudes: Allocation magnitudes for each strategy
     */
    function setupAVSAndRegisterOperator(
        Vm vm,
        IDelegationManager delegationManager,
        IAllocationManager allocationManager,
        AVSSetupParams memory params
    ) public {
        // Create AVS
        address avs = address(new MockAVSRegistrar());
        // Update metadata URI for the AVS
        vm.prank(params.avs);
        allocationManager.updateAVSMetadataURI(params.avs, params.metadataURI);

        // Register operator if not already registered
        if (!delegationManager.isOperator(params.operator)) {
            vm.prank(params.operator);
            delegationManager.registerAsOperator(address(0), 0, "ipfs://some-ipfs-hash");
        }

        //Delegate to operator
        if (params.delegator != address(0) && params.tokenStakingNode != ITokenStakingNode(address(0))) {
            ISignatureUtilsMixinTypes.SignatureWithExpiry memory signature;
            bytes32 approverSalt;
            vm.prank(params.delegator);
            params.tokenStakingNode.delegate(params.operator, signature, approverSalt);
        }

        // Create operator sets for the AVS
        IAllocationManagerTypes.CreateSetParams[] memory createSetParams = new IAllocationManagerTypes.CreateSetParams[](1);
        createSetParams[0] = IAllocationManagerTypes.CreateSetParams({
            operatorSetId: params.operatorSetId,
            strategies: params.strategies
        });
        
        vm.prank(avs);
        allocationManager.createOperatorSets(params.avs, createSetParams);

        // Register for operator set
        IAllocationManagerTypes.RegisterParams memory registerParams = IAllocationManagerTypes.RegisterParams({
            avs: avs,
            operatorSetIds: new uint32[](1),
            data: new bytes(0)
        });
        registerParams.operatorSetIds[0] = params.operatorSetId;
        vm.prank(params.operator);
        allocationManager.registerForOperatorSets(params.operator, registerParams);

        // Wait for allocation delay to pass
        vm.roll(block.number +  AllocationManagerStorage(address(allocationManager)).ALLOCATION_CONFIGURATION_DELAY() + 1);
        
        // Allocate shares to make them slashable
        IAllocationManagerTypes.AllocateParams[] memory allocateParams = new IAllocationManagerTypes.AllocateParams[](1);
        allocateParams[0] = IAllocationManagerTypes.AllocateParams({
            operatorSet: OperatorSet({
                avs: avs,
                id: params.operatorSetId
            }),
            strategies: params.strategies,
            newMagnitudes: params.magnitudes
        });
        
        vm.prank(params.operator);
        allocationManager.modifyAllocations(params.operator, allocateParams);
    }

    /**
     * @notice Slashes an operator for a specific strategy
     * @param vm The forge VM instance
     * @param allocationManager The AllocationManager instance
     * @param avs The AVS address
     * @param operator The operator address
     * @param operatorSetId The operator set ID
     * @param strategy The strategy to slash
     * @param wadsToSlash The amount to slash in WAD (18 decimals)
     */
    function slashOperator(
        Vm vm,
        IAllocationManager allocationManager,
        address avs,
        address operator,
        uint32 operatorSetId,
        IStrategy strategy,
        uint256 wadsToSlash
    ) public {
        IAllocationManagerTypes.SlashingParams memory slashingParams = IAllocationManagerTypes.SlashingParams({
            operator: operator,
            operatorSetId: operatorSetId,
            strategies: new IStrategy[](1),
            wadsToSlash: new uint256[](1),
            description: "test"
        });
        slashingParams.strategies[0] = strategy;
        slashingParams.wadsToSlash[0] = wadsToSlash;
        
        vm.prank(avs);
        allocationManager.slashOperator(avs, slashingParams);
    }
}