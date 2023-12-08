
const hre = require("hardhat");

async function main() {
    const [deployer] = await hre.ethers.getSigners();

    console.log("Deploying contracts with the account:", deployer.address);

    const ynETH = await hre.ethers.getContractFactory("ynETH");
    const ynETHContract = await ynETH.deploy();
    await ynETHContract.deployed();

    const DepositPool = await hre.ethers.getContractFactory("DepositPool");
    const depositPool = await DepositPool.deploy();
    await depositPool.deployed();

    console.log("ynETH deployed to:", ynETHContract.address);
    console.log("DepositPool deployed to:", depositPool.address);

    const ynETHInitializeParams = {
        admin: deployer.address,
        depositPool: depositPool.address
    };

    console.log("Initializing ynETHContract with params:", ynETHInitializeParams);
    await ynETHContract.initialize(ynETHInitializeParams);
    console.log("ynETHContract initialized successfully");

    const depositPoolInitializeParams = {
        admin: deployer.address,
        ynETH: ynETHContract.address,
        depositContract: depositPool.address
    };

    console.log("Initializing depositPool with params:", depositPoolInitializeParams);
    await depositPool.initialize(depositPoolInitializeParams);
    console.log("depositPool initialized successfully");

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
    await retryVerify("depositPool", depositPool.address, []);
    console.log("Contracts verified successfully");
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
