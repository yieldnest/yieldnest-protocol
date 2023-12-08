const { expect } = require("chai");
const { ethers } = require('hardhat');

describe("DepositPool", function() {
  it("Should initialize correctly", async function() {
    const DepositPool = await ethers.getContractFactory("DepositPool");
    const depositPool = await DepositPool.deploy();
    await depositPool.deployed();

    await depositPool.initialize();
  });

  it("Should allow deposits", async function() {
    const DepositPool = await ethers.getContractFactory("DepositPool");
    const depositPool = await DepositPool.deploy();
    await depositPool.deployed();
    const depositAmount = ethers.utils.parseEther("1");
    await depositPool.deposit('0', { value: depositAmount });
    expect(await depositPool.getDepositCount()).to.equal(1);
  });
});

