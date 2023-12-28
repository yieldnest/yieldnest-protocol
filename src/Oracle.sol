pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./interfaces/IOracle.sol";
import "./interfaces/IDepositPool.sol";
import "./interfaces/IStakingNodesManager.sol";

contract Oracle is Initializable, IOracle {

    IDepositPool depositPool;
    IStakingNodesManager stakingNodesManager;

    struct Init {
        IStakingNodesManager stakingNodesManager;
    }

    constructor() {
       //  _disableInitializers();
    }

    function initialize(Init memory init) public initializer {
        stakingNodesManager = init.stakingNodesManager;
    }

    /*
      TODO: implement oracle that measures:
      
      1. Beacon Chain balances 
      2. Eigen Layer balances
    */
    function latestAnswer() public view returns (Answer memory answer) {
        // TODO: implement with full values
    }
}

