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

  it('should deposit and receive ynETH', async function () {
    const depositAmount = ethers.utils.parseEther('1');
    await contracts.ynETH.connect(addr1).depositETH(addr1.address, {value: depositAmount});
    const balance = await contracts.ynETH.balanceOf(addr1.address);
    expect(balance).to.be.equal(depositAmount);

    const totalSupply = await contracts.ynETH.totalSupply();
    expect(totalSupply).to.be.equal(depositAmount);
  });

  it('should be able to withdrawETH as StakingNodeManager and check balance', async function () {
  });
});
