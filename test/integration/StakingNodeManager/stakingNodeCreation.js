const { expect } = require('chai');
const setup = require('../setup');
const { ethers } = require('hardhat');

describe.only('StakingNode creation and usage', function () {
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

    const stakingNode = await contracts.stakingNodesManager.createStakingNode();

    const stakingNodeAddress = await contracts.stakingNodesManager.nodes(0);

    const stakingNodeInstance = await ethers.getContractAt('StakingNode', stakingNodeAddress);
    const eigenPodAddress = await stakingNodeInstance.eigenPod();

    const stakingNodesManagerAddress = await stakingNodeInstance.stakingNodesManager();
    expect(stakingNodesManagerAddress).to.equal(contracts.stakingNodesManager.address);

  });

  it('should create 2 StakingNodes', async function () {

    const stakingNode1 = await contracts.stakingNodesManager.createStakingNode();
    const stakingNodeAddress1 = await contracts.stakingNodesManager.nodes(0);
    const stakingNodeInstance1 = await ethers.getContractAt('StakingNode', stakingNodeAddress1);
    const eigenPodAddress1 = await stakingNodeInstance1.eigenPod();
    const stakingNodesManagerAddress1 = await stakingNodeInstance1.stakingNodesManager();
    expect(stakingNodesManagerAddress1).to.equal(contracts.stakingNodesManager.address);

    const stakingNode2 = await contracts.stakingNodesManager.createStakingNode();
    const stakingNodeAddress2 = await contracts.stakingNodesManager.nodes(1);
    const stakingNodeInstance2 = await ethers.getContractAt('StakingNode', stakingNodeAddress2);
    const eigenPodAddress2 = await stakingNodeInstance2.eigenPod();
    const stakingNodesManagerAddress2 = await stakingNodeInstance2.stakingNodesManager();
    expect(stakingNodesManagerAddress2).to.equal(contracts.stakingNodesManager.address);
  });

  it.only('should register validators', async function () {

    const depositAmount = ethers.utils.parseEther('64');
    await contracts.ynETH.connect(addr1).depositETH(addr1.address, {value: depositAmount});
    const balance = await contracts.ynETH.balanceOf(addr1.address);
    expect(balance).to.be.equal(depositAmount);

    const stakingNode1 = await contracts.stakingNodesManager.createStakingNode();


    const depositData = [
      {
        pubkey: '0x' + '00'.repeat(48),
        withdrawalCredentials: '0x' + '00'.repeat(32),
        signature: '0x' + '00'.repeat(96),
        depositDataRoot: '0x' + '00'.repeat(32)
      }
    ];
    const depositRoot = '0x' + '00'.repeat(32);
    await contracts.stakingNodesManager.registerValidators(depositRoot, depositData);


  });

});
