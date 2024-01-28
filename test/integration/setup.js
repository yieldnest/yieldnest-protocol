const { ethers, upgrades } = require('hardhat');
const {getContractAt} = require("@nomiclabs/hardhat-ethers/internal/helpers");
const { getProxyAdminAddress, deployProxy, deployAndInitializeTransparentUpgradeableProxy, upgradeProxy, retryVerifys } = require('../../scripts/utils');


async function setup() {
  const [deployer] = await ethers.getSigners();

  const MockEigenPodManagerFactory = await ethers.getContractFactory('MockEigenPodManager');
  const mockEigenPodManager = await MockEigenPodManagerFactory.deploy();
  await mockEigenPodManager.deployed();

  const MockDepositContractFactory = await ethers.getContractFactory('MockDepositContract');
  const depositContract = await MockDepositContractFactory.deploy();
  await depositContract.deployed();

  const OracleFactory = await ethers.getContractFactory('Oracle');
  const oracle = await OracleFactory.deploy();
  await oracle.deployed();

  const WETHFactory = await ethers.getContractFactory('WETH');
  const weth = await WETHFactory.deploy();
  await weth.deployed();

  const MockDelegationManagerFactory = await ethers.getContractFactory('MockDelegationManager');
  const mockDelegationManager = await MockDelegationManagerFactory.deploy();
  await mockDelegationManager.deployed();

  const MockStrategyManagerFactory = await ethers.getContractFactory('MockStrategyManager');
  const mockStrategyManager = await MockStrategyManagerFactory.deploy();
  await mockStrategyManager.deployed();

  const MockDelayedWithdrawalRouterFactory = await ethers.getContractFactory('MockDelayedWithdrawalRouter');
  const mockDelayedWithdrawalRouter = await MockDelayedWithdrawalRouterFactory.deploy();
  await mockDelayedWithdrawalRouter.deployed();

  const EmptyYnETHFactory = await ethers.getContractFactory('EmptyYnETH');
  let ynETH = await deployProxy(EmptyYnETHFactory, 'ynETH', deployer);

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
        ynETH: ynETH.address,
        delegationManager: mockDelegationManager.address,
        delayedWithdrawalRouter: mockDelayedWithdrawalRouter.address,
        strategyManager: mockStrategyManager.address
      }]
  );
  await stakingNodesManager.deployed();

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

  return {
    ynETH,
    weth,
    stakingNodesManager
  };
}

module.exports = setup;

