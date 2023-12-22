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
    const depositAmount = ethers.utils.parseEther('1');

    await contracts.ynETH.connect(addr1).depositETH(addr1.address, {value: depositAmount});

    const initialBalance = await ethers.provider.getBalance(contracts.stakingNodesManager.address);

    await contracts.ynETH.connect(contracts.stakingNodesManager).withdrawETH(depositAmount, {gasPrice: 0});

    const finalBalance = await ethers.provider.getBalance(contracts.stakingNodesManager.address);
    expect(finalBalance).to.be.equal(initialBalance.add(depositAmount));
  });

  it.only('should make three sequential deposits and assert balance and totalSupply after each deposit', async function () {
    const depositAmount = ethers.utils.parseEther('1');

    let shares = await contracts.ynETH.previewDeposit(depositAmount);
    console.log({ depositAmount: depositAmount.toString(), shares: shares.toString() });
    await contracts.ynETH.connect(addr1).depositETH(addr1.address, {value: depositAmount});
    let balance = await contracts.ynETH.balanceOf(addr1.address);
    let totalSupply = await contracts.ynETH.totalSupply();
    expect(balance).to.be.equal(depositAmount);
    expect(totalSupply).to.be.equal(depositAmount);

    shares = await contracts.ynETH.previewDeposit(depositAmount);
    console.log({ depositAmount: depositAmount.toString(), shares: shares.toString() });
    await contracts.ynETH.connect(addr1).depositETH(addr1.address, {value: depositAmount});
    balance = await contracts.ynETH.balanceOf(addr1.address);
    totalSupply = await contracts.ynETH.totalSupply();
    expect(balance).to.be.equal(depositAmount.mul(2));
    expect(totalSupply).to.be.equal(depositAmount.mul(2));

    shares = await contracts.ynETH.previewDeposit(depositAmount);
    console.log({ depositAmount: depositAmount.toString(), shares: shares.toString() });
    await contracts.ynETH.connect(addr1).depositETH(addr1.address, {value: depositAmount});
    balance = await contracts.ynETH.balanceOf(addr1.address);
    totalSupply = await contracts.ynETH.totalSupply();
    expect(balance).to.be.equal(depositAmount.mul(3));
    expect(totalSupply).to.be.equal(depositAmount.mul(3));
  });

});
