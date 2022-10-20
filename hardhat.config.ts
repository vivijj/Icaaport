import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";

const config: HardhatUserConfig = {
  networks:{
    hardhat: {
      blockGasLimit: 8000000,
    },
    dev: {
      // this is the dev cortex network
      url: "http://0.0.0.0:8546/",
  },
  },
  solidity: "0.8.17",
};

export default config;
