require("@nomicfoundation/hardhat-toolbox");
require("hardhat-preprocessor");
require("@nomicfoundation/hardhat-foundry");
const fs = require("fs");
require('dotenv').config();

const config = {
  solidity: "0.8.21",
  networks: {
    goerli: {
      url: `https://goerli.infura.io/v3/${process.env.INFURA_PROJECT_ID}`,
      accounts: [`0x${process.env.PRIVATE_KEY}`]
    }
  }
}

module.exports = config;
