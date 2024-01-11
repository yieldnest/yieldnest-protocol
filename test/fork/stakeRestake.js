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

    console.log(`Owners ${owner.address}`);
    //contracts = await deploy();

    console.log('Getting private key...');
    const privateKey = process.env.PRIVATE_KEY;
    console.log('Creating admin wallet...');
    const admin = new ethers.Wallet(privateKey, ethers.provider);

    console.log('Reading addresses from goerli-addresses.json...');
    const fs = require('fs');
    const addresses = JSON.parse(fs.readFileSync('goerli-addresses.json'));
    console.log('Getting ynETH contract...');
    const ynETH = await ethers.getContractAt("ynETH", addresses.ynETH);
    console.log('Getting StakingNodesManager contract...');
    const stakingNodesManager = await ethers.getContractAt("StakingNodesManager", addresses.stakingNodesManager);

    console.log('Deploying StakingNode contract...');
    const StakingNode = await ethers.getContractFactory("StakingNode");
    const stakingNodeDeployment = await StakingNode.deploy();
    await stakingNodeDeployment.deployed();
    console.log('Registering StakingNode implementation contract...');
    await stakingNodesManager.connect(admin).registerStakingNodeImplementationContract(stakingNodeDeployment.address);

    console.log('Getting node index...');
    const nodeIndex = 0;

    console.log('Getting node address...');
    const nodeAddress = await stakingNodesManager.nodes(nodeIndex);
    console.log(`Node address: ${nodeAddress}`);

    console.log('Getting StakingNode contract at node address...');
    const stakingNode = await ethers.getContractAt('StakingNode', nodeAddress);

    console.log('Getting Eigenpod address...');
    const eigenpodAddress = await stakingNode.eigenPod();
    console.log(`Eigenpod address: ${eigenpodAddress}`);

    console.log('Loading DelegationManager using stakingNodesManager...');
    const delegationManagerAddress = await stakingNodesManager.delegationManager();
    const delegationManager = await ethers.getContractAt('IDelegationManager', delegationManagerAddress);
    console.log('Calling delegatedTo for eigenpodAddress...');
    const delegatedTo = await delegationManager.delegatedTo(nodeAddress);
    console.log(`Delegated to: ${delegatedTo}`);


    console.log('Calling queueWithdrawals with 32 ether...');
    const tx = await stakingNode.connect(admin).queueWithdrawals(ethers.utils.parseEther("32"));
    await tx.wait();
    console.log('Withdrawals queued successfully.');

  });
});
