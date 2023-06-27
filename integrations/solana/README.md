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
```bash
yarn
npm run build
```
The compiled program `.so` file and the idl `.json` file will be put in the `test` folder.
Notes: <br>
```bash
If the tag @program_id is already set in product mode (program id) in the source code, then comment it out.
Before deployment, return it back and recompile.
contracts/ServiceRegistrySolana.sol
//@program_id("AUbXARyxJiDhGKgNvii6YkXT92AQZxFrZvFuGTkRtisa")
contract ServiceRegistrySolana {
```

## Run tests
In a separate window run a validator:
```bash
solana-test-validator -r
```

Setup and run tests:
```bash
npm run setup
npm run test
```

Note that the `setup` command will create a program `.key` file in the `test` folder. If the code has changed, the setup
needs to be run again, preferrably with the validator turned off / turned on, as it would clear all the data.

Also note that for the correct anchor setup, the necessary `payer.key` keypair is created during the `setup` phase.

## Deployment
The program is deployed on Solana network with the following addresses:
- devnet: [AUtGCjdye7nFRe7Zn3i2tU86WCpw2pxSS5gty566HWT6](https://solscan.io/account/AUtGCjdye7nFRe7Zn3i2tU86WCpw2pxSS5gty566HWT6?cluster=devnet)
- devnet storage account:[7uiPSypNbSLeMopSU7VSEgoKUHr7yBAWU6nPsBUEpVD](https://solscan.io/account/7uiPSypNbSLeMopSU7VSEgoKUHr7yBAWU6nPsBUEpVD?cluster=devnet)

### Deployment procedure
`deployer` and `programKey` were created using the solana keygen cli function. For example, for the program Id the following
command was used: `solana-keygen grind --starts-with AU:1`. `deployer` was made a default keypair path.
`deployer` needs to have a balance that is enough to deploy the program and perform following actions.
On the devnet one can use `solana airdrop 1` - this will airdrop 1 SOL to the default keypair.

The program bytecode is written into `ServiceRegistrySolana.so`, and its IDL (ABI) is in `ServiceRegistrySolana.json` file.
Use them to connect to the program on-chain and perform necessary web3 requests.

- Create a data storage account separately that points to the program Id:
```bash
cd scripts
node create_data_storage_account.js
```

- Deploy solana program:
```bash
cwd=$(pwd)
solana config set --keypair $cwd/deE9943tv6GqmWRmMgf1Nqt384UpzX4FrMvKrt34mmt.json
solana program deploy --url https://api.devnet.solana.com -v --program-id AUtGCjdye7nFRe7Zn3i2tU86WCpw2pxSS5gty566HWT6.json ServiceRegistrySolana.so
```

- Initialize required program parameters:
```bash
node initialize.js
```

- Add funds to the pda account using the `transfer` method to finish its initialization.
