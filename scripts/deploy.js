
const hre = require("hardhat");
const fs = require('fs');
const contractAddresses = require('./contractAddresses');
const { deployAndInitializeTransparentUpgradeableProxy, deployProxy, upgradeProxy } = require('./utils');



async function main() {
    const [deployer] = await hre.ethers.getSigners();

    // set deployer to be the manager 

    const networkName = hre.network.name;

    const gasPrice = await hre.ethers.provider.getGasPrice();
    const fastGasPrice = gasPrice.mul(3);
    const overrides = {
        gasPrice: fastGasPrice
    };

    const { WETH_ADDRESS, DEPOSIT_2_ADDRESS, EIGENLAYER_EIGENPOD_MANAGER_ADDRESS, EIGENLAYER_DELEGATION_MANAGER_ADDRESS, EIGENLAYER_STRATEGY_MANAGER_ADDRESS } = contractAddresses[networkName];

    console.log("Deploying contracts with the account:", deployer.address);

    const Oracle = await hre.ethers.getContractFactory("Oracle");
    const oracle = await Oracle.deploy(overrides);
    await oracle.deployed();

    console.log("Oracle deployed to:", oracle.address);

    const WETHFactory = await ethers.getContractFactory('WETH');
    const weth = await WETHFactory.deploy();
    await weth.deployed();
  
    const EmptyYnETHFactory = await ethers.getContractFactory('EmptyYnETH');
    let ynETH = await deployProxy(EmptyYnETHFactory, 'ynETH', deployer);
  
  
    console.log({
      ynETH: ynETH.address
    });
  
    console.log("Deploying StakingNodesManager contract");
    const StakingNodesManagerFactory = await ethers.getContractFactory('StakingNodesManager');
  
    const stakingNodesManager = await deployAndInitializeTransparentUpgradeableProxy(
        StakingNodesManagerFactory,
        'StakingNodesManager',
        [],
        deployer,
        [{
          admin: deployer.address,
          maxNodeCount: 10,
          depositContract: DEPOSIT_2_ADDRESS,
          eigenPodManager: EIGENLAYER_EIGENPOD_MANAGER_ADDRESS,
          ynETH: ynETH.address
        }]
    );
    await stakingNodesManager.deployed();
  
    console.log("Initializing StakingNodesManager contract");
  
    console.log("Deploying StakingNode contract");
    const StakingNodeFactory = await ethers.getContractFactory('StakingNode');
    const stakingNode = await StakingNodeFactory.deploy();
    await stakingNode.deployed();
  
    stakingNodesManager.registerStakingNodeImplementationContract(stakingNode.address);
  
    const ynETHFactory = await ethers.getContractFactory('ynETH');
    ynETH = await upgradeProxy(
        ynETH,
        ynETHFactory,
        'ynETH',
        [{
          admin: deployer.address,
          stakingNodesManager: stakingNodesManager.address,
          oracle: oracle.address,
          wETH: weth.address
        }]
    );
    await ynETH.deployed();

    const oracleInitializeParams = {
        stakingNodesManager: stakingNodesManager.address
    };

    console.log("Initializing Oracle with params:", oracleInitializeParams);
    const oracleInitTx = await oracle.initialize(oracleInitializeParams, overrides);
    await oracleInitTx.wait();

    console.log("Oracle initialized successfully");

    console.log("Contracts initialized successfully");

    console.log("Verifying contracts on etherscan");
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

    await retryVerify("ynETHContract", ynETHContract.address, []);
    await retryVerify("Oracle", oracle.address, []);
    console.log("Contracts verified successfully");

    const addresses = {
        ynETHContract: ynETHContract.address,
        oracle: oracle.address
    };

    fs.writeFileSync('goerli-addresses.json', JSON.stringify(addresses, null, 2));
    console.log("Addresses written to goerli-addresses.json");

}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
