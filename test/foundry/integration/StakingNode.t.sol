import "./IntegrationBaseTest.sol";
import "forge-std/console.sol";
import "../../../src/interfaces/IStakingNode.sol";
import "../../../src/StakingNode.sol";

contract StakingNodeTest is IntegrationBaseTest {

    function testCreateNodeAndAssertETHBalanceWithoutRegisteredValidators() public {
        // Create a staking node
        IStakingNode stakingNodeInstance = stakingNodesManager.createStakingNode();

        uint actualETHBalance = stakingNodeInstance.getETHBalance();
        assertEq(actualETHBalance, 0, "ETH balance does not match expected value");
    }

    function setupStakingNode() public returns (IStakingNode, IEigenPod) {

        address addr1 = vm.addr(100);

        vm.deal(addr1, 100 ether);

        uint depositAmount = 32 ether;
        vm.prank(addr1);
        yneth.depositETH{value: depositAmount}(addr1);
        uint balance = yneth.balanceOf(addr1);

        IStakingNode stakingNodeInstance = stakingNodesManager.createStakingNode();

        uint nodeId = 0;

        IStakingNodesManager.DepositData[] memory depositData = new IStakingNodesManager.DepositData[](1);
        depositData[0] = IStakingNodesManager.DepositData({
            publicKey: ZERO_PUBLIC_KEY,
            signature: ZERO_SIGNATURE,
            nodeId: nodeId,
            depositDataRoot: bytes32(0)
        });

        bytes memory withdrawalCredentials = stakingNodesManager.getWithdrawalCredentials(nodeId);

        for (uint i = 0; i < depositData.length; i++) {
            uint amount = depositAmount / depositData.length;
            bytes32 depositDataRoot = stakingNodesManager.generateDepositRoot(depositData[i].publicKey, depositData[i].signature, withdrawalCredentials, amount);
            depositData[i].depositDataRoot = depositDataRoot;
        }
        
        bytes32 depositRoot = ZERO_DEPOSIT_ROOT;
        stakingNodesManager.registerValidators(depositRoot, depositData);

        uint actualETHBalance = stakingNodeInstance.getETHBalance();
        assertEq(actualETHBalance, depositAmount, "ETH balance does not match expected value");

        IEigenPod eigenPodInstance = stakingNodeInstance.eigenPod();

        return (stakingNodeInstance, eigenPodInstance);
    }

    function testCreateNodeAndAssertETHBalanceAfterDeposits() public {

        (IStakingNode stakingNodeInstance, IEigenPod eigenPodInstance) = setupStakingNode();

        // Collapsed variable declarations into direct usage within assertions and conditions

        // TODO: double check this is the desired state for a pod.
        // we can't delegate on mainnet at this time so one should be able to farm points without delegating
        assertEq(eigenPodInstance.restakedExecutionLayerGwei(), 0, "Restaked Gwei should be 0");
        assertEq(address(eigenPodManager), address(eigenPodInstance.eigenPodManager()), "EigenPodManager should match");
        assertEq(eigenPodInstance.podOwner(), address(stakingNodeInstance), "Pod owner address does not match");
        assertFalse(eigenPodInstance.hasRestaked(), "Pod should have fully restaked");
        assertEq(eigenPodInstance.mostRecentWithdrawalBlockNumber(), 0, "Most recent withdrawal block should be greater than 0");


        address payable eigenPodAddress = payable(address(eigenPodInstance));
        uint rewardsSweeped = 1 ether;
        vm.deal(eigenPodAddress, rewardsSweeped);

        // trigger withdraw before restaking succesfully
        stakingNodeInstance.withdrawBeforeRestaking();

        IDelayedWithdrawalRouter delayedWithdrawalRouter = stakingNodesManager.delayedWithdrawalRouter();
        uint withdrawalDelayBlocks = delayedWithdrawalRouter.withdrawalDelayBlocks();
        vm.roll(block.number + withdrawalDelayBlocks + 1);

        uint256 balanceBeforeClaim = address(yneth).balance;
        stakingNodeInstance.claimDelayedWithdrawals(type(uint256).max);
        uint256 balanceAfterClaim = address(yneth).balance;
        uint256 rewardsAmount = balanceAfterClaim - balanceBeforeClaim;

        assertEq(rewardsAmount, rewardsSweeped, "Rewards amount does not match expected value");
    }  

    function testStartWithdrawal() public {

        (IStakingNode stakingNodeInstance, IEigenPod eigenPodInstance) = setupStakingNode();


        uint withdrawalAmount = 1 ether;

        // TODO: see if you can simulate a full deposit verification to test withdrawal
        vm.expectRevert();
        stakingNodeInstance.startWithdrawal(withdrawalAmount);

        // TODO: reenable this code path to allow for withdrawal processing
        return;

        WithdrawalCompletionParams memory params = WithdrawalCompletionParams({
            middlewareTimesIndex: 0, // Assuming middlewareTimesIndex is not used in this context
            amount: withdrawalAmount,
            withdrawalStartBlock: uint32(block.number), // Current block number as the start block
            delegatedAddress: address(0), // Assuming no delegation address is needed for this withdrawal
            nonce: 0 // first nonce is 0
        });

        stakingNodeInstance.completeWithdrawal(params);
    }  
}

