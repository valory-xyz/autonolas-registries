# Autonolas Registries

## Introduction

This repository contains the Autonolas component / agent / service registries part of the on-chain protocol.

A graphical overview of the whole on-chain architecture is available here:

![architecture](https://github.com/valory-xyz/autonolas-registries/blob/main/docs/On-chain_architecture_v2.png?raw=true)
Please note that `buOLAS` and `Sale` contracts are not part on the diagram.

We follow the standard registries setup by OpenZeppelin. Our registries token is a voting escrow token (`veOLAS`) created by locking `OLAS`.

An overview of the design is provided [here](https://github.com/valory-xyz/autonolas-registries/blob/main/docs/Audit_AgentServicesFunctionality.pdf?raw=true).

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
- The code is written on Solidity `0.8.14`.
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
- [OpenZeppelin](https://github.com/OpenZeppelin/openzeppelin-contracts).
