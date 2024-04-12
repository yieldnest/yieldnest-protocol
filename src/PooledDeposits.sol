import "./interfaces/IynETH.sol";

error DepositsPeriodNotEnded();
error DepositMustBeGreaterThanZero();

contract PooledDeposits {
    mapping(address => uint256) public balances;
    uint256 public depositEndTime;

    event DepositReceived(address indexed depositor, uint256 amount);
    event DepositsFinalized(address indexed depositor, uint256 totalAmount, uint256 ynETHAmount);

    IynETH public ynETH;

    constructor(IynETH _ynETH, uint256 _depositEndTime) {
        ynETH = _ynETH;
        depositEndTime = _depositEndTime;
    }

    function deposit() public payable {
        if (block.timestamp > depositEndTime) revert DepositsPeriodNotEnded();
        if (msg.value == 0) revert DepositMustBeGreaterThanZero();
        balances[msg.sender] += msg.value;
        emit DepositReceived(msg.sender, msg.value);
    }

    function finalizeDeposits(address[] calldata depositors) external {
        if (block.timestamp <= depositEndTime) revert DepositsPeriodNotEnded();
        
        for (uint i = 0; i < depositors.length; i++) {
            address depositor = depositors[i];
            uint256 depositAmountPerDepositor = balances[depositor];
            if (depositAmountPerDepositor == 0) {
                continue;
            }
            balances[depositor] = 0;
            uint256 shares = ynETH.depositETH{value: depositAmountPerDepositor}(depositor);
            emit DepositsFinalized(depositor, depositAmountPerDepositor, shares);
        }
    }

    receive() external payable {
        deposit();
    }
}
