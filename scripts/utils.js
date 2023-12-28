const { upgrades, ethers } = require("hardhat");
const hre = require('hardhat');

async function deployAndInitializeTransparentUpgradeableProxy(factory, name, args, admin, initArgs) {

    console.log(`Deploy and initialize proxy for ${name}`)
    const instance = await upgrades.deployProxy(factory, initArgs);

    await instance.deployed();
  
    const contractInstance = await ethers.getContractAt(name, instance.address);
  
    return contractInstance;
  
  }

  async function getProxyImplementation(proxy) {
    const slot = '0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc';
    const storageValue = await ethers.provider.getStorageAt(proxy.address, slot);
    return storageValue;

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

async function retryVerify(contractName, contractAddress, constructorArguments) {
    while (true) {
        try {
            await hre.run("verify:verify", {
                address: contractAddress,
                constructorArguments: constructorArguments,
            });
            console.log(`${contractName} verified successfully`);
            break;
        } catch (error) {
            console.error(`Error verifying ${contractName}, retrying in 10 seconds`, error);
            await new Promise(resolve => setTimeout(resolve, 10000));
        }
    }
}

  module.exports = {
    deployAndInitializeTransparentUpgradeableProxy,
    deployProxy,
    upgradeProxy,
    getProxyImplementation,
    retryVerify
  };
