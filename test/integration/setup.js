const { ethers } = require('hardhat');


async function setup() {
  const [deployer] = await ethers.getSigners();

  const ynETHFactory = await ethers.getContractFactory('ynETH');
  const ynETH = await deployTransparentUpgradeableProxy(ynETHFactory, 'ynETH', [], deployer);
  await ynETH.deployed();

  const DepositPoolFactory = await ethers.getContractFactory('DepositPool');
  const depositPool = await deployTransparentUpgradeableProxy(DepositPoolFactory, 'DepositPool', [], deployer);
  await depositPool.deployed();

  // await ynETH.initialize(deployer.address);
  // await depositPool.initialize(deployer.address);

  return {
    ynETH,
    depositPool
  };
}

async function deployTransparentUpgradeableProxy(factory, name, args, admin) {
  const implementation = await factory.deploy(...args);
  await implementation.deployed();
  const TransparentUpgradeableProxyFactory = await ethers.getContractFactory('TransparentUpgradeableProxy');
  const proxy = await TransparentUpgradeableProxyFactory.deploy(implementation.address, admin.address, []);
  return await ethers.getContractAt(name, proxy.address);
}

module.exports = setup;

