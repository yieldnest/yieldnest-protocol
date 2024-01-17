import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "../interfaces/eigenlayer/IDelegationManager.sol";

contract MockDelegationManager is IDelegationManager {

   function beaconChainETHStrategy() external view returns (IStrategy) {
        return IStrategy(address(0));
   }
    
  function registerAsOperator(
        OperatorDetails calldata registeringOperatorDetails,
        string calldata metadataURI
    ) external {
        revert("registerAsOperator not supported");
    }

    function modifyOperatorDetails(OperatorDetails calldata newOperatorDetails) external {
        revert("modifyOperatorDetails not supported");
    }

    function updateOperatorMetadataURI(string calldata metadataURI) external {
        revert("updateOperatorMetadataURI not supported");
    }

    function delegateTo(
        address operator,
        SignatureWithExpiry memory approverSignatureAndExpiry,
        bytes32 approverSalt
    ) external {
        revert("delegateTo not supported");
    }

    function delegateToBySignature(
        address staker,
        address operator,
        SignatureWithExpiry memory stakerSignatureAndExpiry,
        SignatureWithExpiry memory approverSignatureAndExpiry,
        bytes32 approverSalt
    ) external {
        revert("delegateToBySignature not supported");
    }

    function undelegate(address staker) external returns (bytes32 withdrawalRoot) {
        revert("undelegate not supported");
    }

    function queueWithdrawals(
        QueuedWithdrawalParams[] calldata queuedWithdrawalParams
    ) external returns (bytes32[] memory) {
        revert("queueWithdrawals not supported");
    }

    function completeQueuedWithdrawal(
        Withdrawal calldata withdrawal,
        IERC20[] calldata tokens,
        uint256 middlewareTimesIndex,
        bool receiveAsTokens
    ) external {
        revert("completeQueuedWithdrawal not supported");
    }

    function completeQueuedWithdrawals(
        Withdrawal[] calldata withdrawals,
        IERC20[][] calldata tokens,
        uint256[] calldata middlewareTimesIndexes,
        bool[] calldata receiveAsTokens
    ) external {
        revert("completeQueuedWithdrawals not supported");
    }

    function increaseDelegatedShares(
        address staker,
        IStrategy strategy,
        uint256 shares
    ) external {
        revert("increaseDelegatedShares not supported");
    }

    function decreaseDelegatedShares(
        address staker,
        IStrategy strategy,
        uint256 shares
    ) external {
        revert("decreaseDelegatedShares not supported");
    }

    function stakeRegistry() external view returns (IStakeRegistryStub) {
        revert("stakeRegistry not supported");
    }

    function delegatedTo(address staker) external view returns (address) {
        revert("delegatedTo not supported");
    }

    function operatorDetails(address operator) external view returns (OperatorDetails memory) {
        revert("operatorDetails not supported");
    }

    function earningsReceiver(address operator) external view returns (address) {
        revert("earningsReceiver not supported");
    }

    function delegationApprover(address operator) external view returns (address) {
        revert("delegationApprover not supported");
    }

    function stakerOptOutWindowBlocks(address operator) external view returns (uint256) {
        revert("stakerOptOutWindowBlocks not supported");
    }

    function operatorShares(address operator, IStrategy strategy) external view returns (uint256) {
        revert("operatorShares not supported");
    }

    function isDelegated(address staker) external view returns (bool) {
        revert("isDelegated not supported");
    }

    function isOperator(address operator) external view returns (bool) {
        revert("isOperator not supported");
    }

    function stakerNonce(address staker) external view returns (uint256) {
        revert("stakerNonce not supported");
    }

    function delegationApproverSaltIsSpent(address _delegationApprover, bytes32 salt) external view returns (bool) {
        revert("delegationApproverSaltIsSpent not supported");
    }

    function calculateCurrentStakerDelegationDigestHash(
        address staker,
        address operator,
        uint256 expiry
    ) external view returns (bytes32) {
        revert("calculateCurrentStakerDelegationDigestHash not supported");
    }

    function calculateStakerDelegationDigestHash(
        address staker,
        uint256 _stakerNonce,
        address operator,
        uint256 expiry
    ) external view returns (bytes32) {
        revert("calculateStakerDelegationDigestHash not supported");
    }

    function calculateDelegationApprovalDigestHash(
        address staker,
        address operator,
        address _delegationApprover,
        bytes32 approverSalt,
        uint256 expiry
    ) external view returns (bytes32) {
        revert("calculateDelegationApprovalDigestHash not supported");
    }

    function DOMAIN_TYPEHASH() external view returns (bytes32) {
        revert("DOMAIN_TYPEHASH not supported");
    }

    function STAKER_DELEGATION_TYPEHASH() external view returns (bytes32) {
        revert("STAKER_DELEGATION_TYPEHASH not supported");
    }

    function DELEGATION_APPROVAL_TYPEHASH() external view returns (bytes32) {
        revert("DELEGATION_APPROVAL_TYPEHASH not supported");
    }

    function domainSeparator() external view returns (bytes32) {
        revert("domainSeparator not supported");
    }
    
    function cumulativeWithdrawalsQueued(address staker) external view returns (uint256) {
        revert("cumulativeWithdrawalsQueued not supported");
    }

    function calculateWithdrawalRoot(Withdrawal memory withdrawal) external pure returns (bytes32) {
        revert("calculateWithdrawalRoot not supported");
    }

    function migrateQueuedWithdrawals(IStrategyManager.DeprecatedStruct_QueuedWithdrawal[] memory withdrawalsToQueue) external {
        revert("migrateQueuedWithdrawals not supported");
    }
}