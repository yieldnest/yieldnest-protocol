const { upgrades } = require("hardhat");

async function deployAndInitializeTransparentUpgradeableProxy(factory, name, args, admin, initArgs) {

    console.log(`Deploy and initialize proxy for ${name}`)
    const instance = await upgrades.deployProxy(factory, initArgs);

    await instance.deployed();
  
    const contractInstance = await ethers.getContractAt(name, instance.address);
  
    return contractInstance;
  
  }
  
  async function deployProxy(factory, name, admin) {
  
    console.log(`Deploy proxy for ${name}`)
    const instance = await upgrades.deployProxy(factory);

    await instance.deployed();
  
    const contractInstance = await ethers.getContractAt(name, instance.address);
  
    return contractInstance;
  }
  
  async function upgradeProxy(proxy, factory, name, initArgs) {

    console.log(`Upgrade proxy for ${name}`)
    const upgraded = await upgrades.upgradeProxy(
        proxy.address, factory, {
          call: { fn: 'initialize', args: initArgs}
        }
    );
  
    console.log(`Upgraded ${name}`);
  
    // const contractInstance = await ethers.getContractAt(name, proxy.address);
  
    return upgraded;
  }

  module.exports = {
    deployAndInitializeTransparentUpgradeableProxy,
    deployProxy,
    upgradeProxy
  };
