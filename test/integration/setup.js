const { ethers, upgrades } = require('hardhat');
const {getContractAt} = require("@nomiclabs/hardhat-ethers/internal/helpers");


async function setup() {
  const [deployer] = await ethers.getSigners();

  console.log("Deploying MockEigenPodManager contract");
  const MockEigenPodManagerFactory = await ethers.getContractFactory('MockEigenPodManager');
  const mockEigenPodManager = await MockEigenPodManagerFactory.deploy();
  await mockEigenPodManager.deployed();

  const MockDepositContractFactory = await ethers.getContractFactory('MockDepositContract');
  const depositContract = await MockDepositContractFactory.deploy();
  await depositContract.deployed();

  console.log("Deploying Oracle contract");
  const OracleFactory = await ethers.getContractFactory('Oracle');
  const oracle = await OracleFactory.deploy();
  await oracle.deployed();

  const WETHFactory = await ethers.getContractFactory('WETH');
  const weth = await WETHFactory.deploy();
  await weth.deployed();

  const EmptyYnETHFactory = await ethers.getContractFactory('EmptyYnETH');
  let ynETH = await deployProxy(EmptyYnETHFactory, 'ynETH', deployer);


  console.log({
    ynETH: ynETH.address
  });

  console.log("Deploying StakingNodesManager contract");
  const StakingNodesManagerFactory = await ethers.getContractFactory('StakingNodesManager');

  const stakingNodesManager = await deployAndInitializeTransparentUpgradeableProxy(
      StakingNodesManagerFactory,
      'StakingNodesManager',
      [],
      deployer,
      [{
        admin: deployer.address,
        maxNodeCount: 10,
        depositContract: depositContract.address,
        eigenPodManager: mockEigenPodManager.address,
        ynETH: ynETH.address
      }]
  );
  await stakingNodesManager.deployed();

  console.log("Initializing StakingNodesManager contract");

  console.log("Deploying StakingNode contract");
  const StakingNodeFactory = await ethers.getContractFactory('StakingNode');
  const stakingNode = await StakingNodeFactory.deploy();
  await stakingNode.deployed();

  stakingNodesManager.registerStakingNodeImplementationContract(stakingNode.address);

  const ynETHFactory = await ethers.getContractFactory('ynETH');
  ynETH = await upgradeProxy(
      ynETH,
      ynETHFactory,
      'ynETH',
      [{
        admin: deployer.address,
        stakingNodesManager: stakingNodesManager.address,
        oracle: oracle.address,
        wETH: weth.address
      }]
  );
  await ynETH.deployed();

  console.log("Returning deployed contracts");
  return {
    ynETH,
    weth,
    stakingNodesManager
  };
}

async function getProxyAdminAddress() {
  // Calculate the storage slot for the ProxyAdmin address
  const adminSlotHash = ethers.utils.keccak256(ethers.utils.toUtf8Bytes("eip1967.proxy.admin"));
  const adminStorageSlot = ethers.utils.hexZeroPad(ethers.utils.hexStripZeros(ethers.BigNumber.from(adminSlotHash).sub(1)), 32);

  // Read the storage slot from the proxy contract
  const adminAddress = await provider.getStorageAt(proxyAddress, adminStorageSlot);

  // Convert the storage slot data to an Ethereum address format
  const proxyAdminAddress = ethers.utils.getAddress(ethers.utils.hexStripZeros(adminAddress));
  console.log('ProxyAdmin Address:', proxyAdminAddress);
  return proxyAdminAddress;
}

async function deployAndInitializeTransparentUpgradeableProxy(factory, name, args, admin, initArgs) {

  const instance = await upgrades.deployProxy(factory, initArgs);

  const contractInstance = await ethers.getContractAt(name, instance.address);

  return contractInstance;

}

async function deployProxy(factory, name, admin) {

  const instance = await upgrades.deployProxy(factory);

  const contractInstance = await ethers.getContractAt(name, instance.address);

  return contractInstance;
}

async function upgradeProxy(proxy, factory, name, initArgs) {
  const upgraded = await upgrades.upgradeProxy(
      proxy.address, factory, {
        call: { fn: 'initialize', args: initArgs}
      }
  );

  console.log(`Upgraded ${name}`);

  // const contractInstance = await ethers.getContractAt(name, proxy.address);

  return upgraded;
}

module.exports = setup;

