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
  - [ServiceRegistry](https://github.com/valory-xyz/autonolas-registries/blob/main/contracts/ServiceRegistry.sol)
- Periphery contracts:
  - [RegistriesManager](https://github.com/valory-xyz/autonolas-registries/blob/main/contracts/RegistriesManager.sol)
  - [ServiceManager](https://github.com/valory-xyz/autonolas-registries/blob/main/contracts/ServiceManager.sol)

Services are based on a deployment of agents via the means of multisigs using the generic multisig interface.
One of the most well-known multisigs is Gnosis Safe. The Gnosis interface implementation of a generic multisig interface is provided here:

- [GnosisSafeMultisig](https://github.com/valory-xyz/autonolas-registries/blob/main/contracts/multisigs/GnosisSafeMultisig.sol)

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

### Audits
The audit is provided as development matures. The latest audit report can be found here: [audits](https://github.com/valory-xyz/autonolas-registries/blob/main/audits).

### Linters
- [`ESLint`](https://eslint.org) is used for JS code.
- [`solhint`](https://github.com/protofire/solhint) is used for Solidity linting.


### Github Workflows
The PR process is managed by github workflows, where the code undergoes
several steps in order to be verified. Those include:
- code installation
- running linters
- running tests


## Acknowledgements
The registries contracts were inspired and based on the following sources:
- [Rari-Capital](https://github.com/Rari-Capital/solmate). Last known audited version: `a9e3ea26a2dc73bfa87f0cb189687d029028e0c5`;
- [OpenZeppelin](https://github.com/OpenZeppelin/openzeppelin-contracts).
