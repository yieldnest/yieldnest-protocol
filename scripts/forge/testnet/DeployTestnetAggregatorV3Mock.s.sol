pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "./AggregatorV3Mock.sol";
import "../BaseScript.s.sol";

contract DeployTestnetAggregatorV3Mock is BaseScript {
    function run() external {

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address _broadcaster = vm.addr(deployerPrivateKey);
        console.log("Broadcasting from address:", _broadcaster);
        vm.startBroadcast(_broadcaster);

        AggregatorV3Mock.Init memory init = AggregatorV3Mock.Init({
            roundId: 1,
            answer: 1.1e18, // Price set to 1.1e18
            startedAt: block.timestamp, // Latest updated now
            updatedAt: block.timestamp, // Latest updated now
            answeredInRound: 1
        });

        AggregatorV3Mock aggregatorV3Mock = new AggregatorV3Mock(init);
        console.log("AggregatorV3Mock deployed at:", address(aggregatorV3Mock));

        vm.stopBroadcast();
    }
}
