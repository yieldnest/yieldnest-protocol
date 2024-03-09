import "../../../src/external/chainlink/AggregatorV3Interface.sol";


contract AggregatorV3Mock is AggregatorV3Interface {
    uint8 private _decimals;
    string private _description;
    uint256 private _version;
    uint80 private _roundId;
    int256 private _answer;
    uint256 private _startedAt;
    uint256 private _updatedAt;
    uint80 private _answeredInRound;
    address public owner;
    struct Init {
        uint80 roundId;
        int256 answer;
        uint256 startedAt;
        uint256 updatedAt;
        uint80 answeredInRound;
    }

    constructor(Init memory init) {

        _roundId = init.roundId;
        _answer = init.answer;
        _startedAt = init.startedAt;
        _updatedAt = init.updatedAt;
        _answeredInRound = init.answeredInRound;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Not the owner");
        _;
    }

    function decimals() external view override returns (uint8) {
        return _decimals;
    }

    function description() external view override returns (string memory) {
        return _description;
    }

    function version() external view override returns (uint256) {
        return _version;
    }

    function getRoundData(uint80 roundIdInput) external view override returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) {
        require(roundIdInput == _roundId, "Round ID does not exist");
        return (_roundId, _answer, _startedAt, _updatedAt, _answeredInRound);
    }

    function latestRoundData() external view override returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) {
        return (_roundId, _answer, _startedAt, _updatedAt, _answeredInRound);
    }

    function setLatestRoundData(
        uint80 roundIdInput,
        int256 answerInput,
        uint256 startedAtInput,
        uint256 updatedAtInput,
        uint80 answeredInRoundInput
    ) external onlyOwner {
        _roundId = roundIdInput;
        _answer = answerInput;
        _startedAt = startedAtInput;
        _updatedAt = updatedAtInput;
        _answeredInRound = answeredInRoundInput;
    }

    function setDecimals(uint8 decimalsInput) external onlyOwner {
        _decimals = decimalsInput;
    }

    function setDescription(string calldata descriptionInput) external onlyOwner {
        _description = descriptionInput;
    }

    function setVersion(uint256 versionInput) external onlyOwner {
        _version = versionInput;
    }
}
