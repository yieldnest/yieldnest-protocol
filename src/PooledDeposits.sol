import "./interfaces/IynETH.sol";

contract PooledDeposits {
    mapping(address => uint256) public balances;
    uint256 public depositEndTime;
    bool public depositsActive = true;

    event DepositReceived(address indexed depositor, uint256 amount);
    event DepositsFinalized(address depositor, uint256 totalAmount, uint256 ynETHAmount);

    IynETH public ynETH;

    constructor(IynETH _ynETH, uint256 _depositEndTime) {
        ynETH = _ynETH;
        depositEndTime = _depositEndTime;
    }

    function deposit() public payable {
        require(block.timestamp <= depositEndTime, "Deposits period has not ended");
        require(msg.value > 0, "Deposit must be greater than 0");
        balances[msg.sender] += msg.value;
        emit DepositReceived(msg.sender, msg.value);
    }

    function finalizeDeposits(address[] calldata depositors) external {
        require(block.timestamp > depositEndTime, "Deposits period has not ended");
        
        for (uint i = 0; i < depositors.length; i++) {
            address depositor = depositors[i];
            uint256 depositAmountPerDepositor = balances[depositor];
            uint256 shares = ynETH.depositETH{value: depositAmountPerDepositor}(depositor);
            emit DepositsFinalized(depositor, depositAmountPerDepositor, shares);
        }
    }

    receive() external payable {
        deposit();
    }
}
