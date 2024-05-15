import { IynETH } from "src/interfaces/IynETH.sol";
import { Initializable } from "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";


contract ReferralDepositAdapter is Initializable {

    /// @notice Allows the contract to receive ETH.
    error DirectDepositNotAllowed();

    IynETH public ynETH;

    event ReferralDepositProcessed(address indexed depositor, address indexed receiver, uint256 amount, address indexed referrer);

    function initialize(IynETH _ynETH) public initializer {
        require(address(_ynETH) != address(0), "ynETH cannot be zero");
        ynETH = _ynETH;
    }

    /// @notice Proxies a deposit call to the ynETH with referral information.
    /// @param receiver The address that will receive the ynETH shares.
    /// @param referrer The address of the referrer.
    function depositWithReferral(address receiver, address referrer) external payable {
        require(msg.value > 0, "Deposit amount must be greater than zero");
        require(receiver != address(0), "Receiver address cannot be zero");
        require(referrer != address(0), "Referrer address cannot be zero");
        uint256 shares = ynETH.depositETH{value: msg.value}(receiver);

        emit ReferralDepositProcessed(msg.sender, receiver, shares, referrer);
    }

    receive() external payable {
        revert DirectDepositNotAllowed();
    }
}
