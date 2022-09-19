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

![architecture](https://github.com/valory-xyz/autonolas-registries/blob/main/docs/On-chain_architecture_v3.drawio.png?raw=true)

An overview of the design is provided [here](https://github.com/valory-xyz/autonolas-registries/blob/main/docs/AgentServicesFunctionality.pdf?raw=true).

We have a core periphery architecture for both the components/agents and services. The core contracts are ERC721s primarily accessed via the peripheral manager contracts.

An overview of the state machine governing service management and usage is provided [here](https://github.com/valory-xyz/autonolas-registries/blob/main/docs/FSM.md).

A more detailed set of registries definitions are provided [here](https://github.com/valory-xyz/autonolas-registries/blob/main/docs/definitions.md).

- Abstract contracts:
  - [GenericRegistry](https://github.com/valory-xyz/autonolas-registries/blob/main/contracts/GenericRegistry.sol)
  - [UnitRegistry](https://github.com/valory-xyz/autonolas-registries/blob/main/contracts/UnitRegistry.sol)
  - [GenericManager](https://github.com/valory-xyz/autonolas-registries/blob/main/contracts/GenericManager.sol)
- Core contracts:
  - [AgentRegistry](https://github.com/valory-xyz/autonolas-registries/blob/main/contracts/AgentRegistry.sol)
  - [ComponentRegistry](https://github.com/valory-xyz/autonolas-registries/blob/main/contracts/ComponentRegistry.sol)
  - ServiceRegistry [L1](https://github.com/valory-xyz/autonolas-registries/blob/main/contracts/ServiceRegistry.sol),
    [L2](https://github.com/valory-xyz/autonolas-registries/blob/main/contracts/ServiceRegistry2.sol)
- Periphery contracts:
  - [RegistriesManager](https://github.com/valory-xyz/autonolas-registries/blob/main/contracts/RegistriesManager.sol)
  - [ServiceManager](https://github.com/valory-xyz/autonolas-registries/blob/main/contracts/ServiceManager.sol)

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

As more multisigs come into play, their underlying implementation of the generic multisig will be added.

## Development

### Prerequisites
- This repository follows the standard [`Hardhat`](https://hardhat.org/tutorial/) development process.
- The code is written on Solidity `0.8.15`.
- The standard versions of Node.js along with Yarn are required to proceed further (confirmed to work with Yarn `1.22.10` and npx/npm `6.14.11` and node `v12.22.0`).

### Install the dependencies
The project has submodules to get the dependencies. Make sure you run `git clone --recursive` or init the submodules yourself.
The dependency list is managed by the `package.json` file,
and the setup parameters are stored in the `hardhat.config.js` file.
Simply run the following command to install the project:
```
yarn install
```

### Core components
The contracts and tests are located in the following folders respectively:
```
contracts
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

For testing purposes, the hardhat node deployment script is located [here](https://github.com/valory-xyz/autonolas-registries/blob/main/deploy).

### Audits
The audit is provided as development matures. The latest audit report can be found here: [audits](https://github.com/valory-xyz/autonolas-registries/blob/main/audits).

## Deployed Protocol
The list of addresses can be found [here](https://github.com/valory-xyz/autonolas-registries/blob/main/docs/mainnet_addresses.json).

### Mainnet snapshot of registries
In order to get the current snapshot of all the registries, the following script is provided [here](https://github.com/valory-xyz/autonolas-registries/blob/main/scripts/mainnet_snapshot.js).
The script can be run with the following command:
```
npx hardhat run scripts/mainnet_snapshot.js --network mainnet
```
Please note that for the correct mainnet interaction the `ALCHEMY_API_KEY` needs to be exported as an environment variable.

NOTE: whilst the snapshot does maintain the exact dependency structure between components, agents and services, it does not conserve the ownership structure.

## Acknowledgements
The registries contracts were inspired and based on the following sources:
- [Rari-Capital](https://github.com/Rari-Capital/solmate). Last known audited version: `a9e3ea26a2dc73bfa87f0cb189687d029028e0c5`;
- [Safe Ecosystem](https://github.com/safe-global/safe-contracts). Last known audited version: `c19d65f4bc215d18a137dc4d787873d99333c4d5`;
- [OpenZeppelin](https://github.com/OpenZeppelin/openzeppelin-contracts).
