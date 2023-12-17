const { expect } = require('chai');
const setup = require('../setup');
const { ethers } = require('hardhat');

describe.only('DepositPool integration tests', function () {
  let contracts;
  let owner;
  let addr1;
  let addr2;

  before(async function () {
    contracts = await setup();
    [owner, addr1, addr2, _] = await ethers.getSigners();
  });

  it('should deposit and receive ynETH', async function () {
    const depositAmount = ethers.utils.parseEther('1');
    await contracts.depositPool.connect(addr1).deposit(0, {value: depositAmount});
    const balance = await contracts.ynETH.balanceOf(addr1.address);
    expect(balance).to.be.equal(depositAmount);
  });
});
