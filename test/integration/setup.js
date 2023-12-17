const { ethers } = require('hardhat');


async function setup() {
  const [deployer, stakingNodeManagerSigner] = await ethers.getSigners();

  const ynETHFactory = await ethers.getContractFactory('ynETH');
  const ynETH = await deployTransparentUpgradeableProxy(ynETHFactory, 'ynETH', [], deployer);
  await ynETH.deployed();

  const DepositPoolFactory = await ethers.getContractFactory('DepositPool');
  const depositPool = await deployTransparentUpgradeableProxy(DepositPoolFactory, 'DepositPool', [], deployer);
  await depositPool.deployed();

  const MockDepositContractFactory = await ethers.getContractFactory('MockDepositContract');
  const depositContract = await MockDepositContractFactory.deploy();
  await depositContract.deployed();

  const OracleFactory = await ethers.getContractFactory('Oracle');
  const oracle = await OracleFactory.deploy();
  await oracle.deployed();

  await oracle.initialize({
    stakingNodesManager: stakingNodeManagerSigner.address
  });

  await ynETH.initialize({
    admin: deployer.address,
    depositPool: depositPool.address,
  });

  await depositPool.initialize({
    admin: deployer.address,
    ynETH: ynETH.address,
    stakingNodesManager: stakingNodeManagerSigner.address,
    oracle: oracle.address
  });

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

