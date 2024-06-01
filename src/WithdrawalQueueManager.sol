import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IRedemptionAdapter {
    function getRedemptionRate() external view returns (uint256);
    function transferRedeemableAsset(address to, uint256 amount) external;
    function transferRedemptionAsset(address to, uint256 amount) external;
}

contract WithdrawalQueueManager is ERC721, ReentrancyGuard, Ownable {
    IERC20 public redeemableAsset;
    IERC20 public redemptionAsset;
    IRedemptionAdapter public redemptionAdapter;

    uint256 private _tokenIdCounter;

    struct WithdrawalRequest {
        uint256 amount;
        uint256 redemptionRateAtRequestTime;
    }

    mapping(uint256 => WithdrawalRequest) public withdrawalRequests;

    event WithdrawalRequested(uint256 indexed tokenId, address requester, uint256 amount);
    event WithdrawalClaimed(uint256 indexed tokenId, address claimer, uint256 redeemedAmount);

    constructor(
        string memory name,
        string memory symbol,
        address _redeemableAsset,
        address _redemptionAsset,
        address _redemptionAdapter
    ) ERC721(name, symbol) {
        redeemableAsset = IERC20(_redeemableAsset);
        redemptionAsset = IERC20(_redemptionAsset);
        redemptionAdapter = IRedemptionAdapter(_redemptionAdapter);
    }

    function requestWithdrawal(uint256 amount) external nonReentrant {
        require(amount > 0, "WithdrawalQueueManager: amount must be greater than 0");
        require(redeemableAsset.transferFrom(msg.sender, address(this), amount), "WithdrawalQueueManager: Transfer failed");

        uint256 currentRate = redemptionAdapter.getRedemptionRate();
        uint256 tokenId = _tokenIdCounter++;
        withdrawalRequests[tokenId] = WithdrawalRequest({
            amount: amount,
            redemptionRateAtRequestTime: currentRate
        });

        redemptionAdapter.transferRedeemableAsset(address(this), request.amount);

        _mint(msg.sender, tokenId);
        emit WithdrawalRequested(tokenId, msg.sender, amount);
    }

    function claimWithdrawal(uint256 tokenId) external nonReentrant {
        require(_isApprovedOrOwner(msg.sender, tokenId), "WithdrawalQueueManager: caller is not owner nor approved");

        WithdrawalRequest storage request = withdrawalRequests[tokenId];
        uint256 redeemAmount = (request.amount * request.redemptionRateAtRequestTime) / 1e18; // Assuming rate is scaled by 1e18

        redemptionAdapter.transferRedemptionAsset(msg.sender, redeemAmount);

        _burn(tokenId);
        delete withdrawalRequests[tokenId];

        emit WithdrawalClaimed(tokenId, msg.sender, redeemAmount);
    }

    function setRedemptionAdapter(address newAdapter) external onlyOwner {
        redemptionAdapter = IRedemptionAdapter(newAdapter);
    }
}

