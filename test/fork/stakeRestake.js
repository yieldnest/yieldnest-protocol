const { expect } = require('chai');
const { ethers } = require('hardhat');
const { deploy } = require('../../scripts/deploy');

describe('YieldNest fork tests', function () {
  let contracts;
  let owner;
  let addr1;
  let addr2;

  beforeEach(async function () {
    [owner, addr1, addr2, _] = await ethers.getSigners();
  });


  it('deploy all contracts', async function () {
    contracts = await deploy();
  });
});
