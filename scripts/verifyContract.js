const { retryVerify, getProxyImplementation } = require('./utils');


async function main() {

    const v  = await getProxyImplementation({ address: '0x30baab973Da2B1913c190903348ba76C3f5Bf8B1' } );
    console.log({
        v
    });
    return;

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

