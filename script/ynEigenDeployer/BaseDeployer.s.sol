// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {ContractAddresses} from "./addresses/ContractAddresses.sol";
import {ActorAddresses} from "./addresses/Actors.sol";
import {BaseYnEigenScript} from "script/BaseYnEigenScript.s.sol";
import {BaseScript} from "script/BaseScript.s.sol";
import "forge-std/Script.sol";

import "forge-std/console.sol";

struct Asset {
    address addr;
    string name;
    address strategyAddress;
}

struct InputStruct {
    Asset[] assets;
    uint256 chainId;
    string name;
    address rateProvider;
    string symbol;
}

contract BaseDeployer is Script, BaseScript, ContractAddresses, ActorAddresses {
    using stdJson for string;

    error IncorrectChainId(uint256 specifiedChainId, uint256 actualChainId);

    InputStruct public inputs;

    string public json;
    string public path;

    address internal _deployer;
    uint256 internal _privateKey;
    uint256 internal _chainId;
    string internal _network;

    function _loadState() internal {
        _loadActorAddresses();
        _loadContractAddresses();

        if (block.chainid == 31_337) {
            _privateKey = vm.envUint("ANVIL_ONE");
            _deployer = vm.addr(_privateKey);
        } else {
            _privateKey = vm.envUint("PRIVATE_KEY");
            _deployer = vm.addr(_privateKey);
        }

        console.log("\n");
        console.log("Deployer address:", _deployer);
        console.log("Deployer balance:", _deployer.balance);
    }

    function _loadJson(string memory _path) internal returns (string memory) {
        string memory root = vm.projectRoot();
        path = string(abi.encodePacked(root, _path));
        json = vm.readFile(path);
        return json;
    }

    function _loadJsonData() internal {
        InputStruct memory _inputs;
        bytes memory data = vm.parseJson(json);
        _inputs = abi.decode(data, (InputStruct));

        // corrects wierd artifacts from decoding the struct
        _inputs.chainId = json.readUint(string(abi.encodePacked(".chainId")));
        _inputs.symbol = json.readString(string(abi.encodePacked(".symbol")));
        _inputs.name = json.readString(string(abi.encodePacked(".name")));
        _inputs.rateProvider = json.readAddress(string(abi.encodePacked(".rateProvider")));
        this.loadStructIntoMemory(_inputs);
    }

    /**
     * @dev this function is required to load the JSON input struct into storage untill that feature is added to foundry
     */
    function loadStructIntoMemory(InputStruct calldata inputStruct) external {
        inputs = inputStruct;
    }

    function _checkNetworkParams() internal virtual {
        console.log("ChainId:", inputs.chainId);
        if (block.chainid != inputs.chainId) revert IncorrectChainId(inputs.chainId, block.chainid);
    }
}
