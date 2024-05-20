import {BaseScript} from "script/BaseScript.s.sol";
import {TransparentUpgradeableProxy} from "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ReferralDepositAdapter} from "src/ReferralDepositAdapter.sol";
import {ActorAddresses} from "script/Actors.sol";
import {ContractAddresses} from "script/ContractAddresses.sol";
import {console} from "lib/forge-std/src/console.sol";

contract DeployReferralDepositAdapter is BaseScript {



    function saveDeployment(ReferralDepositAdapter referralDepositAdapter) public virtual {
        string memory json = "deployment";

        // contract addresses
        serializeProxyElements(json, "ReferralDepositAdapter", address(referralDepositAdapter)); 

        ActorAddresses.Actors memory actors = getActors();
        // actors
        vm.serializeAddress(json, "PROXY_ADMIN_OWNER", address(actors.admin.PROXY_ADMIN_OWNER));
        vm.serializeAddress(json, "ADMIN", address(actors.admin.ADMIN));
        vm.serializeAddress(json, "STAKING_ADMIN", address(actors.admin.STAKING_ADMIN));
        vm.serializeAddress(json, "STAKING_NODES_OPERATOR", address(actors.ops.STAKING_NODES_OPERATOR));
        vm.serializeAddress(json, "VALIDATOR_MANAGER", address(actors.ops.VALIDATOR_MANAGER));
        vm.serializeAddress(json, "FEE_RECEIVER", address(actors.admin.FEE_RECEIVER));
        vm.serializeAddress(json, "PAUSE_ADMIN", address(actors.ops.PAUSE_ADMIN));
        vm.serializeAddress(json, "UNPAUSE_ADMIN", address(actors.admin.UNPAUSE_ADMIN));
        vm.serializeAddress(json, "LSD_RESTAKING_MANAGER", address(actors.ops.LSD_RESTAKING_MANAGER));
        vm.serializeAddress(json, "STAKING_NODE_CREATOR", address(actors.ops.STAKING_NODE_CREATOR));
        vm.serializeAddress(json, "ORACLE_ADMIN", address(actors.admin.ORACLE_ADMIN));
        vm.serializeAddress(json, "DEPOSIT_BOOTSTRAPPER", address(actors.eoa.DEPOSIT_BOOTSTRAPPER));

        string memory finalJson = vm.serializeAddress(json, "DEFAULT_SIGNER", address((actors.eoa.DEFAULT_SIGNER)));
        vm.writeJson(finalJson, getDeploymentFile());

        console.log("Deployment JSON file written successfully:", getDeploymentFile());
    }

    function getDeploymentFile() internal override view returns (string memory) {
        string memory root = vm.projectRoot();
        return string.concat(root, "/deployments/ReferralDepositAdapter-", vm.toString(block.chainid), ".json");
    }
    

    function run() external {
       

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        address publicKey = vm.addr(deployerPrivateKey);
        console.log("Deployer Public Key:", publicKey);

        // ynETH.sol ROLES
        ActorAddresses.Actors memory actors = getActors();

        address _broadcaster = vm.addr(deployerPrivateKey);
        console.log("Broadcaster Address:", _broadcaster);

        vm.startBroadcast(deployerPrivateKey);

        TransparentUpgradeableProxy referralDepositAdapterProxy;
        ReferralDepositAdapter referralDepositAdapter;

        address logic = address(new ReferralDepositAdapter());

        referralDepositAdapterProxy = new TransparentUpgradeableProxy(logic, actors.admin.PROXY_ADMIN_OWNER, "");
        referralDepositAdapter = ReferralDepositAdapter(payable(address(referralDepositAdapterProxy)));

        vm.stopBroadcast();

        saveDeployment(referralDepositAdapter);
    }
}
