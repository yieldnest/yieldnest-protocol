const { expect } = require('chai');
const { ethers } = require('hardhat');

describe('ynETH', function () {
  let ynETH;
  let owner;
  let addr1;
  let addr2;
  let addrs;

  beforeEach(async function () {
    const ynETHFactory = await ethers.getContractFactory("ynETH");
    [owner, addr1, addr2, ...addrs] = await ethers.getSigners();
    ynETH = await ynETHFactory.deploy();
    await ynETH.deployed();
  });

  describe("Deployment", function () {
    it("Should set the right owner", async function () {
      expect(await ynETH.owner()).to.equal(owner.address);
    });

    it("Should assign the total supply of tokens to the owner", async function () {
      const ownerBalance = await ynETH.balanceOf(owner.address);
      expect(await ynETH.totalSupply()).to.equal(ownerBalance);
    });
  });

  describe("Transactions", function () {
    it("Should transfer tokens between accounts", async function () {
      await ynETH.transfer(addr1.address, 50);
      const addr1Balance = await ynETH.balanceOf(addr1.address);
      expect(addr1Balance).to.equal(50);

      await ynETH.connect(addr1).transfer(addr2.address, 50);
      const addr2Balance = await ynETH.balanceOf(addr2.address);
      expect(addr2Balance).to.equal(50);
    });

    it("Should fail if sender doesn’t have enough tokens", async function () {
      const initialOwnerBalance = await ynETH.balanceOf(owner.address);

      await expect(
        ynETH.connect(addr1).transfer(owner.address, 1)
      ).to.be.revertedWith("Not enough tokens");

      expect(await ynETH.balanceOf(owner.address)).to.equal(initialOwnerBalance);
    });

    it("Should update balances after transfers", async function () {
      const initialOwnerBalance = await ynETH.balanceOf(owner.address);

      await ynETH.transfer(addr1.address, 100);
      await ynETH.transfer(addr2.address, 50);

      const finalOwnerBalance = await ynETH.balanceOf(owner.address);
      expect(finalOwnerBalance).to.equal(initialOwnerBalance - 150);

      const addr1Balance = await ynETH.balanceOf(addr1.address);
      expect(addr1Balance).to.equal(100);

      const addr2Balance = await ynETH.balanceOf(addr2.address);
      expect(addr2Balance).to.equal(50);
    });
  });
});
