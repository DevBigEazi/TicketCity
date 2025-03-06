import { HardhatUserConfig, vars } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";

const ALCHEMY_API_KEY = vars.get("ALCHEMY_API_KEY");
const BASESCAN_API_KEY = vars.get("BASESCAN_API_KEY");

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
    baseSepolia: {
      url: `https://base-sepolia.g.alchemy.com/v2/${ALCHEMY_API_KEY}`,
      accounts: vars.has("PRIVATE_KEY") ? [vars.get("PRIVATE_KEY")] : [],
    },
  },
  etherscan: {
    apiKey: BASESCAN_API_KEY,
    customChains: [
      {
        network: "baseSepolia",
        chainId: 84532,
        urls: {
          apiURL: "https://api-sepolia.basescan.org/api",
          browserURL: "https://sepolia.basescan.org",
        },
      },
    ],
  },
};

export default config;

// import { HardhatUserConfig, vars } from "hardhat/config";
// import "@nomicfoundation/hardhat-toolbox";

// // const ALCHEMY_API_KEY = vars.get("ALCHEMY_API_KEY");

// const config: HardhatUserConfig = {
//   solidity: {
//     version: "0.8.28",
//     settings: {
//       optimizer: {
//         enabled: true,
//         runs: 200,
//       },
//       viaIR: true,
//     },
//   },

//   networks: {
//     electroneumTestnet: {
//       url: "https://rpc.ankr.com/electroneum_testnet",
//       accounts: vars.has("PRIVATE_KEY") ? [vars.get("PRIVATE_KEY")] : [],
//     },
//   },
//   etherscan: {
//     apiKey: {
//       electroneumTestnet: "empty",
//     },
//     customChains: [
//       {
//         network: "electroneumTestnet",
//         chainId: 5201420,
//         urls: {
//           apiURL: "https://blockexplorer.electroneum.com/api",
//           browserURL: "https://blockexplorer.electroneum.com",
//         },
//       },
//     ],
//   },
// };

// export default config;
