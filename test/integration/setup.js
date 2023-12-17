const { ethers } = require('hardhat');


async function setup() {
  console.log('Getting signers');
  const [deployer, stakingNodeManagerSigner] = await ethers.getSigners();

  console.log('Deploying ynETH');
  const ynETHFactory = await ethers.getContractFactory('ynETH');
  const ynETH = await deployTransparentUpgradeableProxy(ynETHFactory, 'ynETH', [], deployer);
  await ynETH.deployed();

  console.log('Deploying DepositPool');
  const DepositPoolFactory = await ethers.getContractFactory('DepositPool');
  const depositPool = await deployTransparentUpgradeableProxy(DepositPoolFactory, 'DepositPool', [], deployer);
  await depositPool.deployed();

  console.log('Deploying MockDepositContract');
  const MockDepositContractFactory = await ethers.getContractFactory('MockDepositContract');
  const depositContract = await MockDepositContractFactory.deploy();
  await depositContract.deployed();

  console.log('Initializing ynETH');
  await ynETH.initialize({
    admin: deployer.address,
    depositPool: depositPool.address,
  });

  console.log('Initializing DepositPool');
  await depositPool.initialize({
    admin: deployer.address,
    ynETH: ynETH.address,
    stakingNodesManager: stakingNodeManagerSigner.address
  });

  console.log('Done');

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

