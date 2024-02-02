const { expect } = require('chai');
const setup = require('../setup');
const { ethers } = require('hardhat');

describe('StakingNode creation and usage', function () {
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

  it('should register validators', async function () {

    const { stakingNodesManager } = contracts;
    const depositAmount = ethers.utils.parseEther('32');
    await contracts.ynETH.connect(addr1).depositETH(addr1.address, {value: depositAmount});
    const balance = await contracts.ynETH.balanceOf(addr1.address);
    expect(balance).to.be.equal(depositAmount);

    console.log('Creating staking node...');
    await contracts.stakingNodesManager.createStakingNode();

    const nodeId = '0';

    const depositData = [
      {
        publicKey: '0x' + '00'.repeat(48),
        signature: '0x' + '00'.repeat(96),
        nodeId
      }
    ];

    console.log('Getting withdrawal credentials...', nodeId);
    const withdrawalCredentials = await stakingNodesManager.getWithdrawalCredentials(nodeId);

    console.log('Generating deposit data root for each deposit data...');
    for (const data of depositData) {
      const amount = depositAmount.div(depositData.length);
      const depositDataRoot = await stakingNodesManager.generateDepositRoot(data.publicKey, data.signature, withdrawalCredentials, amount);
      data.depositDataRoot = depositDataRoot;
    }
    
    console.log('Registering validators...');
    const depositRoot = '0x' + '00'.repeat(32);
    await contracts.stakingNodesManager.registerValidators(depositRoot, depositData);

  });

  it('should upgrade StakingNode implementation', async function () {
    const { stakingNodesManager } = contracts;


    console.log('Creating staking node...');
    const stakingNode = await contracts.stakingNodesManager.createStakingNode();
    const stakingNodeAddress = await contracts.stakingNodesManager.nodes(0);
    const stakingNodeInstance = await ethers.getContractAt('StakingNode', stakingNodeAddress);
    const eigenPodAddress = await stakingNodeInstance.eigenPod();
    console.log('EigenPod address: ', eigenPodAddress);

    const MockStakingNodeFactory = await ethers.getContractFactory('MockStakingNode');
    const mockStakingNode = await MockStakingNodeFactory.deploy();
    await mockStakingNode.deployed();

    console.log('Upgrading StakingNode implementation...');
    await stakingNodesManager.registerStakingNodeImplementationContract(mockStakingNode.address);

    const upgradedImplementationAddress = await stakingNodesManager.implementationContract();
    expect(upgradedImplementationAddress).to.equal(mockStakingNode.address);

    console.log('Fetching EigenPod address after upgrade...');
    const newEigenPodAddress = await stakingNodeInstance.eigenPod();
    console.log('New EigenPod address: ', newEigenPodAddress);
    expect(newEigenPodAddress).to.equal(eigenPodAddress);

    console.log('Loading MockStakingNode at stakingNodeInstance address...');
    const mockStakingNodeInstance = await ethers.getContractAt('MockStakingNode', stakingNodeAddress);
    console.log('Calling redundant function...');
    const redundantFunctionResult = await mockStakingNodeInstance.redundantFunction();
    console.log('Redundant function result: ', redundantFunctionResult);
    expect(redundantFunctionResult).to.equal(1234567);
  });

});
