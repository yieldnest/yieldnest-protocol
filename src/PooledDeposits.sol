import "./interfaces/IynETH.sol";

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract PooledDeposits is Initializable, OwnableUpgradeable {

    error DepositMustBeGreaterThanZero();
    error YnETHIsSet();
    error YnETHNotSet();

    mapping(address => uint256) public balances;

    event DepositReceived(address indexed depositor, uint256 amount);
    event DepositsFinalized(address indexed depositor, uint256 totalAmount, uint256 ynETHAmount);

    IynETH public ynETH;

    function initialize(address initialOwner) public initializer {
        __Ownable_init(initialOwner);
    }

    function setYnETH(IynETH _ynETH) public onlyOwner {
        ynETH = _ynETH;
    }

    function deposit() public payable {
        if (address(ynETH) != address(0)) revert YnETHIsSet();
        if (msg.value == 0) revert DepositMustBeGreaterThanZero();
        balances[msg.sender] += msg.value;
        emit DepositReceived(msg.sender, msg.value);
    }

    function finalizeDeposits(address[] calldata depositors) external onlyOwner {
        if (address(ynETH) == address(0)) revert YnETHNotSet();
        
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
