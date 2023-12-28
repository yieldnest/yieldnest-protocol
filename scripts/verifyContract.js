const { retryVerify } = require('./utils');


async function main() {
    const contractAddress = "0xb3313c8778458dd58b7014bc2be48ca164813d54"; // replace with your contract address
    const constructorArguments = []; // replace with your constructor arguments if any
    await retryVerify("YourContractName", contractAddress, constructorArguments);
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });

