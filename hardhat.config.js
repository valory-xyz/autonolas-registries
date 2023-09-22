/*global process*/

require("hardhat-contract-sizer");
require("hardhat-deploy");
require("hardhat-deploy-ethers");
require("hardhat-gas-reporter");
require("hardhat-tracer");
require("@nomicfoundation/hardhat-chai-matchers");
require("@nomiclabs/hardhat-ethers");
require("@nomiclabs/hardhat-etherscan");
require("@nomicfoundation/hardhat-toolbox");

const ALCHEMY_API_KEY_MAINNET = process.env.ALCHEMY_API_KEY_MAINNET;
const ALCHEMY_API_KEY_MATIC = process.env.ALCHEMY_API_KEY_MATIC;
const ALCHEMY_API_KEY_GOERLI = process.env.ALCHEMY_API_KEY_GOERLI;
const ALCHEMY_API_KEY_MUMBAI = process.env.ALCHEMY_API_KEY_MUMBAI;
let TESTNET_MNEMONIC = process.env.TESTNET_MNEMONIC;

const accounts = {
    mnemonic: TESTNET_MNEMONIC,
    path: "m/44'/60'/0'/0",
    initialIndex: 0,
    count: 20,
};

if (!TESTNET_MNEMONIC) {
    // Generated with bip39
    accounts.mnemonic = "velvet deliver grief train result fortune travel voice over subject subject staff nominee bone name";
    accounts.accountsBalance = "100000000000000000000000000";
}

const ETHERSCAN_API_KEY = process.env.ETHERSCAN_API_KEY;
const POLYGONSCAN_API_KEY = process.env.POLYGONSCAN_API_KEY;
const GNOSISSCAN_API_KEY = process.env.GNOSISSCAN_API_KEY;
const CHIADOSCAN_API_KEY = "10200";

module.exports = {
    networks: {
        local: {
            url: "http://localhost:8545",
        },
        mainnet: {
            url: "https://eth-mainnet.g.alchemy.com/v2/" + ALCHEMY_API_KEY_MAINNET,
            accounts: accounts,
            chainId: 1,
        },
        polygon: {
            url: "https://polygon-mainnet.g.alchemy.com/v2/" + ALCHEMY_API_KEY_MATIC,
            accounts: accounts,
            chainId: 137,
        },
        gnosis: {
            url: "https://rpc.gnosischain.com",
            accounts: accounts,
            chainId: 100,
        },
        goerli: {
            url: "https://eth-goerli.g.alchemy.com/v2/" + ALCHEMY_API_KEY_GOERLI,
            chainId: 5,
            accounts: accounts,
        },
        polygonMumbai: {
            url: "https://polygon-mumbai.g.alchemy.com/v2/" + ALCHEMY_API_KEY_MUMBAI,
            accounts: accounts,
        },
        chiado: {
            url: "https://rpc.chiadochain.net",
            accounts: accounts,
        },
        hardhat: {
            allowUnlimitedContractSize: true
        },
    },
    etherscan: {
        customChains: [
            {
                network: "chiado",
                chainId: 10200,
                urls: {
                    apiURL: "https://gnosis-chiado.blockscout.com/api",
                    browserURL: "https://gnosis-chiado.blockscout.com/",
                },
            },
            {
                network: "gnosis",
                chainId: 100,
                urls: {
                    apiURL: "https://api.gnosisscan.io/api",
                    browserURL: "https://gnosisscan.io/"
                },
            },
        ],
        apiKey: {
            mainnet: ETHERSCAN_API_KEY,
            polygon: POLYGONSCAN_API_KEY,
            gnosis: GNOSISSCAN_API_KEY,
            goerli: ETHERSCAN_API_KEY,
            polygonMumbai: POLYGONSCAN_API_KEY,
            chiado: CHIADOSCAN_API_KEY,
        }
    },
    solidity: {
        compilers: [
            {
                version: "0.8.19",
                settings: {
                    optimizer: {
                        enabled: true,
                        runs: 750,
                    },
                },
            }
        ]
    },
    gasReporter: {
        enabled: true
    }
};
