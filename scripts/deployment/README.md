# Deployment scripts
This folder contains the scripts to deploy Autonolas registries. These scripts correspond to the steps specified in full deployment procedures
as described in [deployment.md](https://github.com/valory-xyz/autonolas-registries/blob/main/docs/deployment.md) and
in [deploymentL2.md](https://github.com/valory-xyz/autonolas-registries/blob/main/docs/deploymentL2.md) specifically for L2 networks.

## Observations
- There are several files with global parameters based on the corresponding network. In order to work with the configuration, please copy `gobals_network.json` file to file the `gobals.json` one, where `network` is the corresponding network. For example: `cp gobals_goerli.json gobals.json`.
- Please note: if you encounter the `Unknown Error 0x6b0c`, then it is likely because the ledger is not connected or logged in.
- The script to change ownership of the registries to Timelock (`deploy_10_14_change_ownerships.js`) will be done after the DAO members voting.

## Steps to engage
The project has submodules to get the dependencies. Make sure you run `git clone --recursive` or init the submodules yourself.
The dependency list is managed by the `package.json` file, and the setup parameters are stored in the `hardhat.config.js` file.
Simply run the following command to install the project:
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

The Gnosis Safe contracts addresses are provided in order to deploy a Gnosis Safe multisig implementation contract. The deployment
accounts for the address of the Gnosis Safe master copy [v1.3.0](https://github.com/safe-global/safe-deployments/blob/main/src/assets/v1.3.0/gnosis_safe.json).

Other values in the `JSON` file are related to the registries. The deployed contract addresses will be added / updated during the scripts run.

The script file name identifies the number of deployment steps taken from / to the number in the file name. For example:
- `deploy_01_component_registry.js` will complete step 1 from [deployment.md](https://github.com/valory-xyz/autonolas-registries/blob/main/docs/deployment.md);
- `deploy_10_14_change_ownerships.js` will complete steps 10 to 14.

NOTE: All the scripts MUST be strictly run in the sequential order from smallest to biggest numbers.

Export network-related API keys defined in `hardhat.config.js` file that correspond to the required network.

To run the script, use the following command:
`npx hardhat run scripts/deployment/script_name --network network_type`,
where `script_name` is a script name, i.e. `deploy_01_component_registry.js`, `network_type` is a network type corresponding to the `hardhat.config.js` network configuration.

## Validity checks and contract verification
Each script controls the obtained values by checking them against the expected ones. Also, each script has a contract verification procedure.
If a contract is deployed with arguments, these arguments are taken from the corresponding `verify_number_and_name` file, where `number_and_name` corresponds to the deployment script number and name.

## Multisig implementation deployment
The script to deploy multisig implementation (`verify_06_gnosis_safe_multisig.js`) utilizes information about the multisig read from the file `multisigImplementation.json`.
Create this file or copy it from the one with pre-defined parameters (i.e., `scripts/deployment/gnosis_safe_multisig.json`).

## L2 deployment
The L2 Light Protocol deployment procedure is described in [deploymentL2.md](https://github.com/valory-xyz/autonolas-registries/blob/main/docs/deploymentL2.md).
The deployment scripts are located in the corresponding folder: [deployment L2](https://github.com/valory-xyz/autonolas-registries/blob/main/scripts/deployment/l2).

## Deployment of supplemental contracts
For deploying supplemental contracts listed in [deployment.md](https://github.com/valory-xyz/autonolas-registries/blob/main/docs/deployment.md),
run all the scripts sequentially from `deploy_15_operator_whitelist.js` to `deploy_18_change_managers.js`.
The script `deploy_19_20_change_ownerships.js` can be run after the approval of an off-chain vote.


