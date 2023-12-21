const { ethers } = require('hardhat');


async function setup() {
  const [deployer, stakingNodeManagerSigner] = await ethers.getSigners();

  const ynETHFactory = await ethers.getContractFactory('ynETH');
  const ynETH = await deployTransparentUpgradeableProxy(ynETHFactory, 'ynETH', [], deployer);
  await ynETH.deployed();

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

  console.log("Initializing ynETH contract");
  await ynETH.initialize({
    admin: deployer.address,
    stakingNodesManager: stakingNodeManagerSigner.address,
    oracle: oracle.address,
    wETH: weth.address
  });

  console.log("Returning deployed contracts");
  return {
    ynETH,
    weth
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

