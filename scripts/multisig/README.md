#  Multisig data scripts
This folder contains the scripts to output calldatas for updating multisig owners. 


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

Modify the a `multisig_info.json` file with the following pre-defined parameters depending on the script being run.

Parameters of the `multisig_global.json` file:
- `agentInstances`: array with the new multisig owner addresses;
- `serviceMultisigAddress`: address of the multisig;
- `serviceOwnerAddress`: address of the actual (unique) multisig owner that will sign the message;
- `multisendAddress`: address of the multisend contract on the chain with Id `chainId`;
- `threshold`: threshold of the multisig when the new owners will be added (hardcoded to `1` in case of n-to-1 ownership change);
- `nonce`: nonce of the current multisig;
- `chainId`: the chain id. The user should refuse signing if it does not match the currently active chain.
- `approvedHash`: a flag for getting the signature if the hash is already approved in the multisig (`true`) or (`false`) otherwise (ignored in case of n-to-1 ownership change); 


Export network-related API keys defined in `hardhat.config.js` file that correspond to the required network.

To run the script, use the following command:
`npx hardhat run scripts/deployment/script_name --network network_type`,
where `script_name` is a script name, i.e. `change_service_multsig_owners_data.js`, `network_type` is a network type corresponding to the `hardhat.config.js` network configuration. 
Note that, on the local environment, it is not necessary to add `--network network_type`. 


## Current scripts

### Script 1: change_service_multsig_owners_data.js

This script simulates the 1-to-n change of the multisig ownership, namely, from the specified service owner to the new set
of agent instance addresses. The script `change_service_multsig_owners_data.js` has the following outputs: 
- `safeTx` that allows the current owner to give up ownership of the multisig, add the new owners, and update the multisig threshold;  
- `hash` of the `safeTx` that has to be approved by the current service multisig owner; 
- `signatureByte` that mocks the signature string or provides the required one for the approved hash transaction;
- `safeExecData` the multisend data  with the signature bytes that has to be executed by the multisig proxy;
- `packedData` the ServiceRegistry contract `deploy()` function bytes data.

### Script 2: agent_instances_give_up_multisig_ownership.js

This script simulates the n-to-1 change of the multisig ownership, namely, the original set of agent instance addresses gives up
their ownership to the sole service owner address. The script `agent_instances_give_up_multisig_ownership.js` has the following outputs:
- `safeTx` that allows the current set of multisig agent instance owners to give up their ownership in favor of the sole service owner address;
- `hash` of the `safeTx` that has to be signed by the `threshold` number of current multisig agent instance owners;




