require("@nomiclabs/hardhat-waffle");
require("hardhat-gas-reporter");

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  solidity: {
    version: "0.8.4",
    settings: {
      optimizer: {
        enabled: true,
        runs: 2000
      },
    },
  },
  gasReporter: {
    enabled: process.env.GAS_REPORT,
  }
};
