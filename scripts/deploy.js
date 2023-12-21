
const hre = require("hardhat");
const fs = require('fs');
const contractAddresses = require('./contractAddresses');

async function main() {
    const [deployer] = await hre.ethers.getSigners();

    // set deployer to be the manager 
    const stakingNodesManager = deployer;

    const networkName = hre.network.name;

    const gasPrice = await hre.ethers.provider.getGasPrice();
    const fastGasPrice = gasPrice.mul(2);
    const overrides = {
        gasPrice: fastGasPrice
    };

    const { WETH_ADDRESS } = contractAddresses[networkName];

    console.log("Deploying contracts with the account:", deployer.address);

    const Oracle = await hre.ethers.getContractFactory("Oracle");
    const oracle = await Oracle.deploy();
    await oracle.deployed();

    console.log("Oracle deployed to:", oracle.address);

    const ynETH = await hre.ethers.getContractFactory("ynETH");
    const ynETHContract = await ynETH.deploy();
    await ynETHContract.deployed();

    console.log("ynETH deployed to:", ynETHContract.address);


    const ynETHInitializeParams = {
        admin: deployer.address,
        ynETH: ynETHContract.address,
        oracle: oracle.address,
        wETH: WETH_ADDRESS,
        stakingNodesManager: stakingNodesManager.address
    };

    console.log("Initializing ynETHContract with params:", ynETHInitializeParams);
    await ynETHContract.initialize(ynETHInitializeParams);

    console.log("ynETH initialized successfully");

    const oracleInitializeParams = {
        stakingNodesManager: stakingNodesManager.address
    };

    console.log("Initializing Oracle with params:", oracleInitializeParams);
    await oracle.initialize(oracleInitializeParams);

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
        depositPool: depositPool.address
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
