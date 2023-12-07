import {IDepositPool} from "./interfaces/IDepositPool.sol";

contract DepositPool is IDepositPool {

    function stake(uint256 minynETHAmount) external payable {
        if (pauser.isStakingPaused()) {
            revert Paused();
        }

        if (msg.value < minimumStakeBound) {
            revert MinimumStakeBoundNotSatisfied();
        }

        uint256 ynETHMintAmount = ethToynETH(msg.value);
        if (ynETHMintAmount + ynETH.totalSupply() > maximumynETHSupply) {
            revert MaximumynETHSupplyExceeded();
        }
        if (ynETHMintAmount < minynETHAmount) {
            revert StakeBelowMinimumynETHAmount(ynETHMintAmount, minynETHAmount);
        }

        emit Staked(msg.sender, msg.value, ynETHMintAmount);
        ynETH.mint(msg.sender, ynETHMintAmount);
    }    
}
