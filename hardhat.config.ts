import { HardhatUserConfig, vars } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";

const ANKR_API_KEY = vars.get("ANKR_API_KEY");

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.28",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
      viaIR: true,
    },
  },

  networks: {
    "electroneum-testnet": {
      url: `https://rpc.ankr.com/electroneum_testnet/${ANKR_API_KEY}`,
      accounts: vars.has("PRIVATE_KEY") ? [vars.get("PRIVATE_KEY")] : [],
    },
  },
  etherscan: {
    apiKey: {
      "electroneum-testnet": "empty",
    },
    customChains: [
      {
        network: "electroneum-testnet",
        chainId: 5201420,
        urls: {
          apiURL: "https://testnet-blockexplorer.electroneum.com/api",
          browserURL: "https://testnet-blockexplorer.electroneum.com",
        },
      },
    ],
  },
};

export default config;
