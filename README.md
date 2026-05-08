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

A graphical overview is available [here](./docs/flowchart.md).

For reference purposes only, an older version of the general Autonolas architecture is available [here](./docs/On-chain_architecture_v6.png).

An overview of the design, details on how securing services with ETH or a custom ERC20 token, how service owners can opt for a set of authorized operators,
as well as how DAOs can manage their autonomous services are provided [here](./docs/AgentServicesFunctionality.pdf).

We have a core periphery architecture for both the components/agents and services. The core contracts are ERC721s primarily accessed via the peripheral manager contracts.

An overview of the state machine governing service management and usage is provided [here](./docs/FSM.md).

A more detailed set of registries definitions are provided [here](./docs/definitions.md).

An overview of the registries contracts related to staking can be found [here](./docs/StakingSmartContracts.pdf). Details on Olas staking are provided [here](https://staking.olas.network/poaa-whitepaper.pdf).

Note that by default the contracts do not work with:
- Fee on transfer tokens;
- Balance changes outside token transfers.

The following list represents registries contracts:
- Abstract contracts:
  - [GenericRegistry](./contracts/GenericRegistry.sol)
  - [UnitRegistry](./contracts/UnitRegistry.sol)
  - [GenericManager](./contracts/GenericManager.sol)
  - [StakingBase.sol](./contracts/staking/StakingBase.sol)
- Core contracts:
  - [AgentRegistry](./contracts/AgentRegistry.sol)
  - [ComponentRegistry](./contracts/ComponentRegistry.sol)
  - ServiceRegistry [L1](./contracts/ServiceRegistry.sol)
    [L2](./contracts/ServiceRegistryL2.sol)
  - [ServiceRegistryTokenUtility](./contracts/ServiceRegistryTokenUtility.sol)
- Periphery contracts:
  - [RegistriesManager](./contracts/RegistriesManager.sol)
  - [ServiceManager](./contracts/ServiceManager.sol)
- Utility contracts:
  - [OperatorSignedHashes](./contracts/utils/OperatorSignedHashes.sol)
  - [OperatorWhitelist](./contracts/utils/OperatorWhitelist.sol)

- Staking related contracts:
  - [StakingBase.sol](./contracts/staking/StakingBase.sol)
  - [StakingNativeToken.sol](./contracts/staking/StakingNativeToken.sol)
  - [StakingToken.sol](./contracts/staking/StakingToken.sol)
  - [StakingFactory.sol](./contracts/staking/StakingFactory.sol)
  - [StakingProxy.sol](./contracts/staking/StakingProxy.sol)
  - [StakingVerifier.sol](./contracts/staking/StakingVerifier.sol)
  - [StakingActivityChecker.sol](./contracts/staking/StakingActivityChecker.sol)


In order to deploy a service, its registered agent instances form a consensus mechanism via the means of multisigs using the generic multisig interface.
One of the most well-known multisigs is [Safe](https://safe.global/). The Safe interface implementation of a generic multisig interface is provided here:
- [GnosisSafeMultisig](./contracts/multisigs/GnosisSafeMultisig.sol)

The updated version accounting for the Recovery Module installation is provided here:
- [SafeMultisigWithRecoveryModule](./contracts/multisigs/SafeMultisigWithRecoveryModule.sol)

Another multisig implementation allows to upgrade / downgrade the number of agent instances that govern the same Safe multisig instance between different service re-deployments.
Please note that the initial multisig instance must already exist from a previous service deployment.
In order to use that option, registered agent instances forming a consensus are required to return the multisig instance ownership to the service owner.
Then, the service owner must terminate the service, update the number of desired agent instances and move it into a new `active-registration` state.
Once all agent instances are registered, the service owner re-deploys the service by giving up their ownership of the multisig with registered agent instances and by setting a new multisig instance threshold.
The implementation of such multisig is provided here:
- [GnosisSafeSameAddressMultisig](./contracts/multisigs/GnosisSafeSameAddressMultisig.sol)

The updated version with the access recovery feature is provided in the Recovery Module contract itself here:
- [RecoveryModule](./contracts/multisigs/RecoveryModule.sol)

A Polymarket-specific multisig creator that pairs a Safe (OLAS service multisig + ERC-8004 agent wallet) with a Polymarket deposit wallet — required for new accounts under the CLOB v2 rollout — is provided here:
- [SafeAndDepositWalletCreator](./contracts/multisigs/SafeAndDepositWalletCreator.sol)

It produces the Safe with `RecoveryModule` enabled atomically (via `Safe.setup`) and verifies a deposit wallet that is pre-deployed out-of-band by Polymarket's relayer (the `DepositWalletFactory.deploy` entry point is operator-gated, so the deposit wallet must be provisioned via an off-chain HTTP call before the on-chain `serviceManager.deploy` is submitted). The Safe and the deposit wallet are independent peers bridged by the agent-instance EOA: the EOA is one of the Safe's owners and the deposit wallet's sole EOA owner. ERC-8004 `setAgentWallet` works through the Safe via the standard `SignMessageLib` + `CompatibilityFallbackHandler` path. See [`docs/polymarket/clob_v2_deposit_wallet_creator_plan.md`](./docs/polymarket/clob_v2_deposit_wallet_creator_plan.md) for the full architecture and threat model, [`docs/polymarket/clob_v2_impact_polySafeCreator.md`](./docs/polymarket/clob_v2_impact_polySafeCreator.md) for the impact on the existing PolySafe creator, and [`docs/polymarket/clob_v2_impact_subgraphs.md`](./docs/polymarket/clob_v2_impact_subgraphs.md) for the subgraph-side impact.

To verify the multisig data when redeploying the service using the GnosisSafeSameAddressMultisig contract while changing service multisig owners (with updated agent instance addresses),
see the guidelines and corresponding scripts [here](./scripts/multisig/)

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
#### Hardhat
Compile the code with Hardhat:
```
yarn compile
```
Run tests with Hardhat:
```
yarn test
```
Run coverage with Hardhat:
```
yarn coverage
```

#### Forge
Compile the code with Forge:
```
forge build
```
Run tests with Forge (skip fork testing):
```
forge test --match-contract Staking -vvv
forge test --match-contract PolySafeCreator -vvv
forge test --match-contract SafeAndDepositWalletCreator -vvv
```
Run fork tests with Forge:
```
forge test -f $FORK_NODE_URL --match-contract IdentityRegistry -vvv
forge test -f $FORK_NODE_URL --match-contract StakePolySafe -vvv
forge test -f $FORK_NODE_URL --match-contract SafeAndDepositWalletCreatorFork -vvv
forge test -f $FORK_NODE_URL --match-contract SafeAndDepositWalletCreatorE2E -vvv
```

### Test with instrumented code
[Scribble](https://docs.scribble.codes/) annotated contracts are located in ./contracts/scribble.

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
The description of deployment procedure can be found here: [deployment](./scripts/deployment).

The finalized contract ABIs for deployment and their number of optimization passes are located here: [ABIs](./abis).
Each folder there contains contracts compiled with the solidity version before their deployment.

For testing purposes, the hardhat node deployment script is located [here](./deploy).

If you want to use custom contracts in the registry image, read [here](./docs/running_with_custom_contracts.md).

### Audits
- The audit is provided as development matures. The latest audit report can be found here: [audits](./audits).
- A list of known vulnerabilities can be found here: [Vulnerabilities list](./docs/Vulnerabilities_list_registries.md)

#### Static audit
The static audit checks all the deployed contracts on-chain info correctness and can be run using the following script:
```
node scripts/audit_chains/audit_contracts_setup.js
```

## Deployed Protocol
The list of contract addresses for different chains and their full contract configuration can be found [here](./docs/configuration.json).

In order to test the protocol setup on all the deployed chains, the audit script is implemented. Make sure to export
required API keys for corresponding chains (see the script for more information). The audit script can be run as follows:
```
node scripts/audit_chains/audit_contracts_setup.js
```

### Mainnet snapshot of registries
In order to get the current snapshot of all the registries, the following script is provided [here](./scripts/mainnet_snapshot.js).
The script can be run with the following command:
```
npx hardhat run scripts/mainnet_snapshot.js --network mainnet
```
Please note that for the correct mainnet interaction the `ALCHEMY_API_KEY` needs to be exported as an environment variable.

NOTE: whilst the snapshot does maintain the exact dependency structure between components, agents and services, it does not conserve the ownership structure.

## Protocol-owned-services
A specific service can be owned by a DAO-governed protocol. In order to construct a DAO proposal for the service (re-)deployment,
the following step-by-step guide is advised to be observed [here](./docs/DAO_service_deloyment_FSM.pdf).

## Integrations on non-EVM blockchains
### Solana
The light protocol with a similar functionality to ServiceRegistryL2 is implemented as part of the Solana integration network.
The ServiceRegistrySolana program is developed [here](./integrations/solana).


## Acknowledgements
The registries contracts were inspired and based on the following sources:
- [Rari-Capital](https://github.com/Rari-Capital/solmate). Last known audited version: `a9e3ea26a2dc73bfa87f0cb189687d029028e0c5`;
- [Safe Ecosystem](https://github.com/safe-global/safe-contracts). Last known audited version: `c19d65f4bc215d18a137dc4d787873d99333c4d5`;
- [OpenZeppelin](https://github.com/OpenZeppelin/openzeppelin-contracts).
