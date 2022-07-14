# Deployment scripts
This folder contains the scripts to deploy Autonolas registries. These scripts correspond to the steps in the full deployment procedure (as described in [deployment.md](https://github.com/valory-xyz/autonolas-registries/blob/main/docs/deployment.md)).

## Observations
- There are several files with global parameters based on the corresponding network. In order to work with the configuration, please copy `gobals_network.json` file to file the `gobals.json` one, where `network` is the corresponding network. For example: `cp gobals_goerli.json gobals.json`.
- Please note: if you encounter the `Unknown Error 0x6b0c`, then it is likely because the ledger is not connected or logged in.

## Steps to engage
Make sure the project is installed with the
```
yarn install
```
command and compiled with the
```
npx hardhat compile
```
command as described in the [main readme](https://github.com/valory-xyz/autonolas-registries/blob/main/README.md).


Create a `globals.json` file in the root folder, or copy it from the file with pre-defined parameters (i.e., `scripts/deployment/globals_goerli.json` for the goerli testnet).

Parameters of the `globals.json` file:
- `contractVerification`: a flag for verifying contracts in deployment scripts (`true`) or skipping it (`false`);
- `useLedger`: a flag whether to use the hardware wallet (`true`) or proceed with the seed-phrase accounts (`false`);
- `derivationPath`: a string with the derivation path;
- `providerName`: a network type (see `hardhat.config.js` for the network configurations);
- `timelockAddress`: a Timelock contract address deployed during the `autonolas-governance` deployment.

The Gnosis Safe contracts are also provided in order to deploy a Gnosis Safe multisig implementation contract.
Other values are related to the registries. The deployed contract addresses will be added / updated during the scripts run.

The script file name identifies the number of deployment steps taken from / to the number in the file name. For example:
- `deploy_01_component_registry.js` will complete steps 1 from [deployment.md](https://github.com/valory-xyz/autonolas-registries/blob/main/docs/deployment.md);
- `deploy_07_14_change_ownerships.js` will complete steps 7 to 14.

NOTE: All the scripts MUST be strictly run in the sequential order from smallest to biggest numbers.

To run the script, use the following command:
`npx hardhat run scripts/deployment/script_name --network network_type`,
where `script_name` is a script name, i.e. `deploy_01_component_registry.js`, `network_type` is a network type corresponding to the `hardhat.config.js` network configuration.

## Validity checks and contract verification
Each script controls the obtained values by checking them against the expected ones. Also, each script has a contract verification procedure.
If a contract is deployed with arguments, these arguments are taken from the corresponding `verify_number_and_name` file, where `number_and_name` corresponds to the deployment script number and name.







