const { expect } = require('chai');
const setup = require('../setup');
const { ethers } = require('hardhat');

describe.only('DepositPool integration tests', function () {
  let contracts;
  let owner;
  let addr1;
  let addr2;

  beforeEach(async function () {
    contracts = await setup();
    [owner, addr1, addr2, _] = await ethers.getSigners();
  });

  afterEach(async function () {
    await ethers.provider.send('hardhat_reset', []);
  });

  it.only('should create StakingNode', async function () {

    const stakingNode = await contracts.stakingNodesManager.createStakingNode();

    const stakingNodeAddress = await contracts.stakingNodesManager.nodes(0);

    const stakingNodeInstance = await ethers.getContractAt('StakingNode', stakingNodeAddress);
    const eigenPodAddress = await stakingNodeInstance.eigenPod();

    const stakingNodesManagerAddress = await stakingNodeInstance.stakingNodesManager();
    expect(stakingNodesManagerAddress).to.equal(contracts.stakingNodesManager.address);

  });

  it('should be able to withdrawETH as StakingNodeManager and check balance', async function () {
  });
});
