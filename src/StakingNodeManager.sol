pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "./StakingNode.sol";

contract StakingNodeManager is Initializable, AccessControlUpgradeable {

    UpgradeableBeacon private upgradableBeacon;
    address public eigenPodManager;

    function createStakingNode(bool _createEigenPod) internal returns (address) {
        BeaconProxy proxy = new BeaconProxy(address(upgradableBeacon), "");
        StakingNode node = StakingNode(payable(proxy));
        node.initialize(address(this));
        if (_createEigenPod) {
            node.createEigenPod();
        }

        return address(node);
    }
}
