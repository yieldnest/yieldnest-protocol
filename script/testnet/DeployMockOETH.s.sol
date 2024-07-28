import {ContractAddresses} from "script/ContractAddresses.sol";
import {ActorAddresses} from "script/Actors.sol";
import {BaseYnEigenScript} from "script/BaseYnEigenScript.s.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {IwstETH} from "src/external/lido/IwstETH.sol";
import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {MockOETH} from "test/mocks/MockOETH.sol";
import {MockWOETH} from "test/mocks/MockWOETH.sol";
import {TransparentUpgradeableProxy} from "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {BaseScript} from "script/BaseScript.s.sol";

import "forge-std/console.sol";


contract DeployOETH is BaseScript {
    function run() external {
    

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // ynETH.sol ROLES
        ActorAddresses.Actors memory actors = getActors();

        address _broadcaster = vm.addr(deployerPrivateKey);

        // solhint-disable-next-line no-console
        console.log("Default Signer Address:", _broadcaster);
        // solhint-disable-next-line no-console
        console.log("Current Block Number:", block.number);
        // solhint-disable-next-line no-console
        console.log("Current Chain ID:", block.chainid);


        vm.startBroadcast();

        address mockController = actors.eoa.MOCK_CONTROLLER;

        MockOETH mockOETHImplementation = new MockOETH();
        TransparentUpgradeableProxy mockOETHProxy = new TransparentUpgradeableProxy(
            address(mockOETHImplementation),
            mockController,
            ""
        );
        console.log("MockOETH deployed at:", address(mockOETHProxy));

        MockOETH mockOETH = MockOETH(address(mockOETHProxy));
        mockOETH.initialize(mockController, mockController);
        console.log("MockOETH initialized with controller:", mockController);

        MockWOETH mockWOETHImplementation = new MockWOETH();
        TransparentUpgradeableProxy mockWOETHProxy = new TransparentUpgradeableProxy(
            address(mockWOETHImplementation),
            mockController,
            ""
        );

        MockWOETH mockWOETH = MockWOETH(address(mockWOETHProxy));
        mockWOETH.initialize(ERC20(address(mockOETHProxy)));
        console.log("MockWOETH initialized with underlying MockOETH:", address(mockOETHProxy));


        console.log("MockWoETH deployed at:", address(mockWOETHProxy));
        vm.stopBroadcast();
    }
}
