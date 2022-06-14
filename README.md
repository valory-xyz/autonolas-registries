# Autonolas Registries

## Introduction

This repository contains the Autonolas component / agent / service registries part of the on-chain protocol.

Autonolas registries provide the functionality to mint agent `components` and canonical `agents` via the ERC721 standard.
It stores instances associated with components and agents, supplies a set of read-only functions to inquire the state
of entities.

The registries also provide the capability of creating `services` that are based on canonical agents. Each service
instance bears a set of canonical agent Ids it is composed of with the number of agent instances for each Id. For the
service deployment `operators` supply agent instances to a specific service via registration. Once all the required
agent instances are provided by operators, the service can be deployed forming a Gnosis Safe contract governed by
a group of agent instances.

A graphical overview of the whole on-chain architecture is available here:

![architecture](https://github.com/valory-xyz/autonolas-registries/blob/main/docs/On-chain_architecture_v2.png?raw=true)

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

## Definitions and data structures
- [`Multihash`](https://multiformats.io/multihash/): a self-describing hash, a protocol for differentiating outputs
  from various well-established hash functions. Multihash is a hashing standard for [`IPFS`](https://docs.ipfs.io/concepts/what-is-ipfs/),
  a distributed system for storing and accessing files, websites, applications, and data. Please note that IPSF uses the
  `sha2-256 - 256 bits` as their hashing function. From the definition, `sha2-256` has a `0x12` code in hex, and its
  length is 32, or `0x20` in hex. This means that each IPFS link starts with `1220` value in hash, and the link itself
  can perfectly fit the `bytes32` data structure. Note that if the IPFS hashing changes, the size of Multihash data
  structure needs to be updated, although old links would still work (as per IPFS standard).
- `Agent Component`: a piece of code + configuration in the agent. In the context of the [`open-aea`](https://github.com/valory-xyz/open-aea)
  framework, it is a skill, connection, protocol or contract. Each component is identified by its IPFS hash.
- `Canonical Agent`: a configuration and optionally code making up the agent. In the context of the [`open-aea`](https://github.com/valory-xyz/open-aea)
  framework, this is the agent config file which points to various agent components. The agent code and config are
  identified by its IPFS hash.
- `Agent Instance`: an instance of a canonical agent. Each agent instance must have, at a minimum, a single
  cryptographic key-pair, whose address identifies the agent.
- `Operator`: an individual operating an agent instance (or multiple). The operator must have, at a minimum, a single
  cryptographic key-pair whose address identifies the operator. This key-pair MUST be different from the ones used
  by the agent.
- `Service`: defines a set (or singleton) of canonical agents (and therefore components), a set of service extension
  contracts, a number of agents instances per canonical agents.

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
