// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "../interfaces/eigenlayer/IEigenPodManager.sol";

contract MockEigenPodManager is IEigenPodManager {

    /**
     * @notice Creates an EigenPod for the sender.
     * @dev Function will revert if the `msg.sender` already has an EigenPod.
     * @dev Returns EigenPod address 
     */
    function createPod() external override returns (address) {
        revert("createPod is not supported");
    }

    /**
     * @notice Stakes for a new beacon chain validator on the sender's EigenPod.
     * Also creates an EigenPod for the sender if they don't have one already.
     * @param pubkey The 48 bytes public key of the beacon chain validator.
     * @param signature The validator's signature of the deposit data.
     * @param depositDataRoot The root/hash of the deposit data for the validator's deposit.
     */
    function stake(bytes calldata pubkey, bytes calldata signature, bytes32 depositDataRoot) external payable override {
        revert("stake is not supported");
    }

    /**
     * @notice Changes the `podOwner`'s shares by `sharesDelta` and performs a call to the DelegationManager
     * to ensure that delegated shares are also tracked correctly
     * @param podOwner is the pod owner whose balance is being updated.
     * @param sharesDelta is the change in podOwner's beaconChainETHStrategy shares
     * @dev Callable only by the podOwner's EigenPod contract.
     * @dev Reverts if `sharesDelta` is not a whole Gwei amount
     */
    function recordBeaconChainETHBalanceUpdate(address podOwner, int256 sharesDelta) external override {
        revert("recordBeaconChainETHBalanceUpdate is not supported");
    }

    /**
     * @notice Updates the oracle contract that provides the beacon chain state root
     * @param newBeaconChainOracle is the new oracle contract being pointed to
     * @dev Callable only by the owner of this contract (i.e. governance)
     */
    function updateBeaconChainOracle(IBeaconChainOracle newBeaconChainOracle) external override {
        revert("updateBeaconChainOracle is not supported");
    }

    /// @notice Returns the address of the `podOwner`'s EigenPod if it has been deployed.
    function ownerToPod(address podOwner) external view override returns (IEigenPod) {
        revert("ownerToPod is not supported");
    }

    /// @notice Returns the address of the `podOwner`'s EigenPod (whether it is deployed yet or not).
    function getPod(address podOwner) external view override returns (IEigenPod) {
        revert("getPod is not supported");
    }

    /// @notice The ETH2 Deposit Contract
    function ethPOS() external view override returns (IETHPOSDeposit) {
        revert("ethPOS is not supported");
    }

    /// @notice Beacon proxy to which the EigenPods point
    function eigenPodBeacon() external view override returns (IBeacon) {
        revert("eigenPodBeacon is not supported");
    }

    /// @notice Oracle contract that provides updates to the beacon chain's state
    function beaconChainOracle() external view override returns (IBeaconChainOracle) {
        revert("beaconChainOracle is not supported");
    }

    /// @notice Returns the beacon block root at `timestamp`. Reverts if the Beacon block root at `timestamp` has not yet been finalized.
    function getBlockRootAtTimestamp(uint64 timestamp) external view override returns (bytes32) {
        revert("getBlockRootAtTimestamp is not supported");
    }

    /// @notice EigenLayer's StrategyManager contract
    function strategyManager() external view override returns (IStrategyManager) {
        revert("strategyManager is not supported");
    }

    /// @notice EigenLayer's Slasher contract
    function slasher() external view override returns (ISlasher) {
        revert("slasher is not supported");
    }

    /// @notice Returns 'true' if the `podOwner` has created an EigenPod, and 'false' otherwise.
    function hasPod(address podOwner) external view override returns (bool) {
        revert("hasPod is not supported");
    }

    /// @notice Returns the number of EigenPods that have been created
    function numPods() external view override returns (uint256) {
        revert("numPods is not supported");
    }

    /// @notice Returns the maximum number of EigenPods that can be created
    function maxPods() external view override returns (uint256) {
        revert("maxPods is not supported");
    }

    /**
     * @notice Mapping from Pod owner owner to the number of shares they have in the virtual beacon chain ETH strategy.
     * @dev The share amount can become negative. This is necessary to accommodate the fact that a pod owner's virtual beacon chain ETH shares can
     * decrease between the pod owner queuing and completing a withdrawal.
     * When the pod owner's shares would otherwise increase, this "deficit" is decreased first _instead_.
     * Likewise, when a withdrawal is completed, this "deficit" is decreased and the withdrawal amount is decreased; We can think of this
     * as the withdrawal "paying off the deficit".
     */
    function podOwnerShares(address podOwner) external view override returns (int256) {
        revert("podOwnerShares is not supported");
    }

    /// @notice returns canonical, virtual beaconChainETH strategy
    function beaconChainETHStrategy() external view override returns (IStrategy) {
        revert("beaconChainETHStrategy is not supported");
    }

    /**
     * @notice Used by the DelegationManager to remove a pod owner's shares while they're in the withdrawal queue.
     * Simply decreases the `podOwner`'s shares by `shares`, down to a minimum of zero.
     * @dev This function reverts if it would result in `podOwnerShares[podOwner]` being less than zero, i.e. it is forbidden for this function to
     * result in the `podOwner` incurring a "share deficit". This behavior prevents a Staker from queuing a withdrawal which improperly removes excessive
     * shares from the operator to whom the staker is delegated.
     * @dev Reverts if `shares` is not a whole Gwei amount
     */
    function removeShares(address podOwner, uint256 shares) external override {
        revert("removeShares is not supported");
    }

    /**
     * @notice Increases the `podOwner`'s shares by `shares`, paying off deficit if possible.
     * Used by the DelegationManager to award a pod owner shares on exiting the withdrawal queue
     * @dev Returns the number of shares added to `podOwnerShares[podOwner]` above zero, which will be less than the `shares` input
     * in the event that the podOwner has an existing shares deficit (i.e. `podOwnerShares[podOwner]` starts below zero)
     * @dev Reverts if `shares` is not a whole Gwei amount
     */
    function addShares(address podOwner, uint256 shares) external override returns (uint256) {
        revert("addShares is not supported");
    }

    /**
     * @notice Used by the DelegationManager to complete a withdrawal, sending tokens to some destination address
     * @dev Prioritizes decreasing the podOwner's share deficit, if they have one
     * @dev Reverts if `shares` is not a whole Gwei amount
     */
    function withdrawSharesAsTokens(address podOwner, address destination, uint256 shares) external override {
        revert("withdrawSharesAsTokens is not supported");
    }


        /// @notice Address of the `PauserRegistry` contract that this contract defers to for determining access control (for pausing).
    function pauserRegistry() external view returns (IPauserRegistry) {
        revert("pauserRegistry is not supported");
    }


        /**
         * @notice This function is used to pause an EigenLayer contract's functionality.
         * It is permissioned to the `pauser` address, which is expected to be a low threshold multisig.
         * @param newPausedStatus represents the new value for `_paused` to take, which means it may flip several bits at once.
         * @dev This function can only pause functionality, and thus cannot 'unflip' any bit in `_paused` from 1 to 0.
         */
        function pause(uint256 newPausedStatus) external override {
            revert("pause is not supported");
        }

        /**
         * @notice Alias for `pause(type(uint256).max)`.
         */
        function pauseAll() external override {
            revert("pauseAll is not supported");
        }

        /**
         * @notice This function is used to unpause an EigenLayer contract's functionality.
         * It is permissioned to the `unpauser` address, which is expected to be a high threshold multisig or governance contract.
         * @param newPausedStatus represents the new value for `_paused` to take, which means it may flip several bits at once.
         * @dev This function can only unpause functionality, and thus cannot 'flip' any bit in `_paused` from 0 to 1.
         */
        function unpause(uint256 newPausedStatus) external override {
            revert("unpause is not supported");
        }

        /// @notice Returns the current paused status as a uint256.
        function paused() external view override returns (uint256) {
            revert("paused is not supported");
        }

        /// @notice Returns 'true' if the `indexed`th bit of `_paused` is 1, and 'false' otherwise
        function paused(uint8 index) external view override returns (bool) {
            revert("paused is not supported");
        }

        /// @notice Allows the unpauser to set a new pauser registry
        function setPauserRegistry(IPauserRegistry newPauserRegistry) external override {
            revert("setPauserRegistry is not supported");
        }
}
