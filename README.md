# Autonolas Registries

## Introduction

This repository contains the Autonolas component / agent / service registries part of the on-chain protocol.

Autonolas registries provide the functionality to mint agent `components` and canonical `agents` via the ERC721 standard.
It stores instances associated with components and agents, supplies a set of read-only functions to inquire the state
of entities.

The registries also provide the capability of creating `services` that are based on canonical agents. Each service
instance bears a set of canonical agent Ids it is composed of with the number of agent instances for each Id. For the
service deployment `operators` supply agent instances to a specific service via registration. Once all the required
agent instances are provided by operators, the service can be deployed forming a multisig contract governed by
a group of agent instances.

In order to generalize `components` / `agents` / `services`, they are referred sometimes as `units`.

A graphical overview of the whole on-chain architecture is available here:

![architecture](https://github.com/valory-xyz/autonolas-registries/blob/main/docs/On-chain_architecture_v6.png)

An overview of the design, details on how securing services with ETH or a custom ERC20 token, how service owners can opt for a set of authorized operators,
as well as how DAOs can manage their autonomous services are provided [here](https://github.com/valory-xyz/autonolas-registries/blob/main/docs/AgentServicesFunctionality.pdf).

We have a core periphery architecture for both the components/agents and services. The core contracts are ERC721s primarily accessed via the peripheral manager contracts.

An overview of the state machine governing service management and usage is provided [here](https://github.com/valory-xyz/autonolas-registries/blob/main/docs/FSM.md).

A more detailed set of registries definitions are provided [here](https://github.com/valory-xyz/autonolas-registries/blob/main/docs/definitions.md).

An overview of the registries contracts related to staking can be found [here](https://github.com/valory-xyz/autonolas-registries/blob/main/docs/StakingSmartContracts.pdf). Details on Olas staking are provided [here](https://staking.olas.network/poaa-whitepaper.pdf).


- Abstract contracts:
  - [GenericRegistry](https://github.com/valory-xyz/autonolas-registries/blob/main/contracts/GenericRegistry.sol)
  - [UnitRegistry](https://github.com/valory-xyz/autonolas-registries/blob/main/contracts/UnitRegistry.sol)
  - [GenericManager](https://github.com/valory-xyz/autonolas-registries/blob/main/contracts/GenericManager.sol)
  - [ServiceStakingBase.sol](https://github.com/valory-xyz/autonolas-registries/blob/main/contracts/staking/ServiceStakingBase.sol)
- Core contracts:
  - [AgentRegistry](https://github.com/valory-xyz/autonolas-registries/blob/main/contracts/AgentRegistry.sol)
  - [ComponentRegistry](https://github.com/valory-xyz/autonolas-registries/blob/main/contracts/ComponentRegistry.sol)
  - ServiceRegistry [L1](https://github.com/valory-xyz/autonolas-registries/blob/main/contracts/ServiceRegistry.sol)
    [L2](https://github.com/valory-xyz/autonolas-registries/blob/main/contracts/ServiceRegistryL2.sol)
  - [ServiceRegistryTokenUtility](https://github.com/valory-xyz/autonolas-registries/blob/main/contracts/ServiceRegistryTokenUtility.sol)
- Periphery contracts:
  - [RegistriesManager](https://github.com/valory-xyz/autonolas-registries/blob/main/contracts/RegistriesManager.sol)
  - [ServiceManager](https://github.com/valory-xyz/autonolas-registries/blob/main/contracts/ServiceManager.sol)
  - [ServiceManagerToken](https://github.com/valory-xyz/autonolas-registries/blob/main/contracts/ServiceManagerToken.sol)
- Utility contracts:
  - [OperatorSignedHashes](https://github.com/valory-xyz/autonolas-registries/blob/main/contracts/utils/OperatorSignedHashes.sol)
  - [OperatorWhitelist](https://github.com/valory-xyz/autonolas-registries/blob/main/contracts/utils/OperatorWhitelist.sol)

- Staking related contracts:
  - [StakingBase.sol](https://github.com/valory-xyz/autonolas-registries/blob/main/contracts/staking/StakingBase.sol)
  - [StakingNativeToken.sol](https://github.com/valory-xyz/autonolas-registries/blob/main/contracts/staking/StakingNativeToken.sol)
  - [StakingToken.sol](https://github.com/valory-xyz/autonolas-registries/blob/main/contracts/staking/StakingToken.sol)
  - [StakingFactory.sol](https://github.com/valory-xyz/autonolas-registries/blob/main/contracts/staking/StakingFactory.sol)
  - [StakingProxy.sol](https://github.com/valory-xyz/autonolas-registries/blob/main/contracts/staking/StakingProxy.sol)
  - [StakingVerifier.sol](https://github.com/valory-xyz/autonolas-registries/blob/main/contracts/staking/StakingVerifier.sol)
  - [StakingActivityChecker.sol](https://github.com/valory-xyz/autonolas-registries/blob/main/contracts/staking/StakingActivityChecker.sol)


In order to deploy a service, its registered agent instances form a consensus mechanism via the means of multisigs using the generic multisig interface.
One of the most well-known multisigs is Gnosis Safe. The Gnosis interface implementation of a generic multisig interface is provided here:
- [GnosisSafeMultisig](https://github.com/valory-xyz/autonolas-registries/blob/main/contracts/multisigs/GnosisSafeMultisig.sol)

Another multisig implementation allows to upgrade / downgrade the number of agent instances that govern the same Gnosis Safe multisig instance between different service re-deployments.
Please note that the initial multisig instance must already exist from a previous service deployment.
In order to use that option, registered agent instances forming a consensus are required to return the multisig instance ownership to the service owner.
Then, the service owner must terminate the service, update the number of desired agent instances and move it into a new `active-registration` state.
Once all agent instances are registered, the service owner re-deploys the service by giving up their ownership of the multisig with registered agent instances and by setting a new multisig instance threshold.
The implementation of such multisig is provided here:
- [GnosisSafeSameAddressMultisig](https://github.com/valory-xyz/autonolas-registries/blob/main/contracts/multisigs/GnosisSafeSameAddressMultisig.sol)

To verify the multisig data when redeploying the service using the GnosisSafeSameAddressMultisig contract while changing service multisig owners (with updated agent instance addresses),
see the guidelines and corresponding scripts [here](https://github.com/valory-xyz/autonolas-registries/blob/main/scripts/multisig/)

As more multisigs come into play, their underlying implementation of the generic multisig will be added.

## Development

### Prerequisites
- This repository follows the standard [`Hardhat`](https://hardhat.org/tutorial/) development process.
- The code is written on Solidity starting from version `0.8.15`.
- The standard versions of Node.js along with Yarn are required to proceed further (confirmed to work with Yarn `1.22.19` and npx/npm `10.1.0` and node `v18.17.0`).

### Install the dependencies
The project has submodules to get the dependencies. Make sure you run `git clone --recursive` or init the submodules yourself.
The dependency list is managed by the `package.json` file, and the setup parameters are stored in the `hardhat.config.js` file.
Simply run the following command to install the project:
```
yarn install
```

### Core components
The contracts, deployment scripts and tests are located in the following folders respectively:
```
contracts
scripts
test
```

### Compile the code and run
Compile the code:
```
npx hardhat compile
```
Run the tests:
```
npx hardhat test
```
Run tests with forge:
```
forge test --hh -vvv
```

### Test with instrumented code
[Scribble](https://docs.scribble.codes/) annotated contracts are located in https://github.com/valory-xyz/autonolas-registries/blob/main/contracts/scribble.

Install Scribble in order to instrument the code:
```
npm install -g eth-scribble
```
Arm (instrument) the code, run tests and disarm the code:
```
scribble contracts/scribble/ServiceRegistryAnnotated.sol --output-mode files --arm
npx hardhat test
scribble contracts/scribble/ServiceRegistryAnnotated.sol --disarm
```
Alternatively, run a simple scribble script:
```
./scripts/scribble.sh scribble/ServiceRegistryAnnotated.sol
```

### Docker image

```
docker build . -t valory/autonolas-registries
```

```
docker run -it -d -p 8545:8545 --name chain valory/autonolas-registries
```

### Linters
- [`ESLint`](https://eslint.org) is used for JS code.
- [`solhint`](https://github.com/protofire/solhint) is used for Solidity linting.


### Github Workflows
The PR process is managed by github workflows, where the code undergoes
several steps in order to be verified. Those include:
- code installation
- running linters
- running tests

## Deployment
The deployment of contracts to the test- and main-net is split into step-by-step series of scripts for more control and checkpoint convenience.
The description of deployment procedure can be found here: [deployment](https://github.com/valory-xyz/autonolas-registries/blob/main/scripts/deployment).

The finalized contract ABIs for deployment and their number of optimization passes are located here: [ABIs](https://github.com/valory-xyz/autonolas-registries/blob/main/abis).
Each folder there contains contracts compiled with the solidity version before their deployment.

For testing purposes, the hardhat node deployment script is located [here](https://github.com/valory-xyz/autonolas-registries/blob/main/deploy).

If you want to use custom contracts in the registry image, read [here](https://github.com/valory-xyz/autonolas-registries/blob/main/docs/running_with_custom_contracts.md).

### Audits
The audit is provided as development matures. The latest audit report can be found here: [audits](https://github.com/valory-xyz/autonolas-registries/blob/main/audits).
A list of known vulnerabilities can be found here: [Vulnerabilities list](https://github.com/valory-xyz/autonolas-registries/blob/main/docs/Vulnerabilities_list_registries.pdf)

## Deployed Protocol
The list of contract addresses for different chains and their full contract configuration can be found [here](https://github.com/valory-xyz/autonolas-registries/blob/main/docs/configuration.json).

In order to test the protocol setup on all the deployed chains, the audit script is implemented. Make sure to export
required API keys for corresponding chains (see the script for more information). The audit script can be run as follows:
```
node scripts/audit_chains/audit_contracts_setup.js
```

### Mainnet snapshot of registries
In order to get the current snapshot of all the registries, the following script is provided [here](https://github.com/valory-xyz/autonolas-registries/blob/main/scripts/mainnet_snapshot.js).
The script can be run with the following command:
```
npx hardhat run scripts/mainnet_snapshot.js --network mainnet
```
Please note that for the correct mainnet interaction the `ALCHEMY_API_KEY` needs to be exported as an environment variable.

NOTE: whilst the snapshot does maintain the exact dependency structure between components, agents and services, it does not conserve the ownership structure.

## Protocol-owned-services
A specific service can be owned by a DAO-governed protocol. In order to construct a DAO proposal for the service (re-)deployment,
the following step-by-step guide is advised to be observed [here](https://github.com/valory-xyz/autonolas-registries/blob/main/docs/DAO_service_deloyment_FSM.pdf).

## Integrations on non-EVM blockchains
### Solana
The light protocol with a similar functionality to ServiceRegistryL2 is implemented as part of the Solana integration network.
The ServiceRegistrySolana program is developed [here](https://github.com/valory-xyz/autonolas-registries/blob/main/integrations/solana).


## Acknowledgements
The registries contracts were inspired and based on the following sources:
- [Rari-Capital](https://github.com/Rari-Capital/solmate). Last known audited version: `a9e3ea26a2dc73bfa87f0cb189687d029028e0c5`;
- [Safe Ecosystem](https://github.com/safe-global/safe-contracts). Last known audited version: `c19d65f4bc215d18a137dc4d787873d99333c4d5`;
- [OpenZeppelin](https://github.com/OpenZeppelin/openzeppelin-contracts).
