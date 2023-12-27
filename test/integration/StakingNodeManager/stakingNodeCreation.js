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

  it('should create StakingNode', async function () {

    const stakingNode = await contracts.stakingNodeManager.createStakingNode({from: owner});
    expect(stakingNode).to.exist;



  });

  it('should be able to withdrawETH as StakingNodeManager and check balance', async function () {
  });
});
