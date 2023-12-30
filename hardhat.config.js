require("@nomicfoundation/hardhat-toolbox");
require("hardhat-preprocessor");
require("@nomicfoundation/hardhat-foundry");
require('@openzeppelin/hardhat-upgrades');
require('hardhat-contract-sizer');

const fs = require("fs");
require('dotenv').config();


const networks = {
  hardhat: {
    gasPrice: 0,
    initialBaseFeePerGas: 0
  },
  goerli: {
    url: `https://goerli.infura.io/v3/${process.env.INFURA_PROJECT_ID}`,
    accounts: [`0x${process.env.PRIVATE_KEY}`]
  }
};

if (process.env.TEST_ENV_FORK) {
  networks.hardhat.forking = { url: process.env.TEST_ENV_FORK };
}


const config = {
  solidity: {
    compilers: [
      {
        version: "0.8.21"
      },
      {
        version: "0.4.24"
      }
    ]
  },
  networks,
  etherscan: {
    customChains: [
      {
        network: "goerli",
        chainId: 100,
        urls: {
          apiURL: "https://api.goerli.etherscan.io/api",
          browserURL: "goerli.etherscan.io/",
        },
      },
    ],
    apiKey: {
      goerli: process.env.ETHERSCAN_API_KEY
    }
  },
}

module.exports = config;
