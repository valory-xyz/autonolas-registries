# Solana integration.
## Pre-requisites
Solana version: `solana-cli 1.14.19 (src:5704dd6e; feat:1879391783)`

Solana config example:
```
Config File: $HOME/.config/solana/cli/config.yml
RPC URL: http://localhost:8899
WebSocket URL: ws://localhost:8900/ (computed)
Keypair Path: $HOME/.config/solana/id.json
Commitment: confirmed
```

Solang version: `v0.3.0`

## Compile the code
```
yarn
npm run build
```
The compiled program `.so` file and the idl `.json` file will be put in the `test` folder.

## Run tests
In a separate window run a validator:
```
solana-test-validator -r
```

Setup and run tests:
```
npm run setup
npm run test
```

Note that the `setup` command will create a program `.key` file in the `test` folder. If the code has changed, the setup
needs to be run again, preferrably with the validator turned off / turned on, as it would clear all the data.

Also note that for the correct anchor setup, the necessary `payer.key` keypair is created during the `setup` phase.

## Deployment
The program is deployed on Solana network with the following addresses:
- devnet: [AUX6DBER9z1HyeW7g4cu6ArHRDJdSQFAvSEL7PzWBSpw](https://explorer.solana.com/address/AUX6DBER9z1HyeW7g4cu6ArHRDJdSQFAvSEL7PzWBSpw?cluster=devnet)

### Deployment procedure
`deployer` and `programKey` were created using the solana keygen cli function. For example, for the program Id the following
command was used: `solana-keygen grind --starts-with AU:1`. `deployer` was made a default keypair path.
`deployer` needs to have a balance that is enough to deploy the program and perform following actions.
On the devnet one can use `solana airdrop 1` - this will airdrop 1 SOL to the default keypair.

- Create a data storage account separately that points to the program Id:
```
cd scripts
node create_data_storage_account.js
```

- Deploy solana program:
```
solana program deploy --url https://api.devnet.solana.com -v --program-id AUX6DBER9z1HyeW7g4cu6ArHRDJdSQFAvSEL7PzWBSpw.json ServiceRegistrySolana.so
```

- Initialize required program parameters:
```
node initialize.js
```

- Add funds to the pda account using the `transfer` method to finish its initialization.