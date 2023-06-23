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
- devnet: AUgdetq6LMewUPfLb1tYRmhZk5TDfqDJ2jJoZXyhomhh

