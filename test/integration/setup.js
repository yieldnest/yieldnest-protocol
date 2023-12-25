const { ethers, upgrades } = require('hardhat');
const {getContractAt} = require("@nomiclabs/hardhat-ethers/internal/helpers");


async function setup() {
  const [deployer] = await ethers.getSigners();

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
        depositContract: depositContract.address
      }]
  );
  await stakingNodesManager.deployed();

  console.log("Initializing StakingNodesManager contract");


  const ynETHFactory = await ethers.getContractFactory('ynETH');
  const ynETH = await deployAndInitializeTransparentUpgradeableProxy(
      ynETHFactory,
      'ynETH',
      [],
      deployer,
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

  const upgraded = await upgrades.upgradeProxy(
    await instance.address, factory, {
      call: { fn: 'initialize', args: initArgs}
    }
  );

  return instance;
}

module.exports = setup;

