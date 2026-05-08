# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Autonolas Registries implements an on-chain protocol for registering and managing autonomous services. The system uses ERC721 tokens to mint components, agents, and services. Services are deployed using multisig contracts (typically Safe/Gnosis Safe) governed by agent instances.

Key terminology (see docs/definitions.md for details):
- **Component**: A piece of code/configuration (skill, connection, protocol, or contract). Identified by IPFS hash.
- **Agent (Canonical Agent)**: Configuration/code making up an agent, composed of components. Identified by IPFS hash.
- **Agent Instance**: A running instance of a canonical agent with its own cryptographic key-pair.
- **Service**: Defines a set of canonical agents, number of instances per agent, and operator slots. Deployed as a multisig.
- **Operator**: Individual operating agent instance(s) with a key-pair separate from the agent's keys.

### Consumer-Facing Terminology

**Important:** The smart contracts use the terminology above, but the marketplace UI at https://marketplace.olas.network/ uses different consumer-facing names:

| Smart Contract Term | Marketplace UI Term |
|---------------------|---------------------|
| Component | Component |
| Agent (Canonical Agent) | AI Agent Blueprint |
| Service | AI Agent |

When reading code, documentation, or contract names, use the smart contract terminology. When discussing the user-facing application, use the marketplace terminology.

## Setup

The project uses git submodules (`lib/forge-std`, `lib/solmate`). Clone with `git clone --recursive` or run `git submodule update --init --recursive` after cloning.

```bash
yarn install
```

Confirmed to work with Yarn 1.22.19, npm/npx 10.1.0, Node v18.17.0.

## Common Development Commands

### Build and Compile
```bash
# Compile with Hardhat (primary build system)
yarn compile

# Compile with Forge (Foundry)
forge build
```

### Testing

#### Hardhat Tests (JavaScript)
```bash
# Run all tests
yarn test

# Run specific test file
npx hardhat test test/ServiceRegistry.js

# Gas reporter is enabled by default in hardhat config
```

#### Forge Tests (Solidity)
```bash
# Run Staking tests (skip fork tests)
forge test --match-contract Staking -vvv

# Run PolySafeCreator tests
forge test --match-contract PolySafeCreator -vvv

# Run SafeAndDepositWalletCreator unit tests
forge test --match-contract SafeAndDepositWalletCreator -vvv

# Run fork tests (requires FORK_NODE_URL env var)
forge test -f $FORK_NODE_URL --match-contract IdentityRegistry -vvv
forge test -f $FORK_NODE_URL --match-contract StakePolySafe -vvv
forge test -f $FORK_NODE_URL --match-contract SafeAndDepositWalletCreatorFork -vvv
forge test -f $FORK_NODE_URL --match-contract SafeAndDepositWalletCreatorE2E -vvv
```

### Coverage
```bash
yarn coverage
```

### Linting
```bash
# Solidity linting (solhint)
npx solhint 'contracts/**/*.sol'

# JavaScript linting (ESLint)
npx eslint .
```

### Scribble Testing
Scribble is used for formal verification of annotated contracts. Annotated contracts are in `contracts/scribble/`.

```bash
# Install Scribble globally
npm install -g eth-scribble

# Instrument, test, and disarm
scribble contracts/scribble/ServiceRegistryAnnotated.sol --output-mode files --arm
npx hardhat test
scribble contracts/scribble/ServiceRegistryAnnotated.sol --disarm

# Or use the convenience script
./scripts/scribble.sh scribble/ServiceRegistryAnnotated.sol
```

### Docker (Local Development)
```bash
docker build . -t valory/autonolas-registries
docker run -it -d -p 8545:8545 --name chain valory/autonolas-registries
```

### Deployment and Network Operations
```bash
# Run mainnet snapshot (requires ALCHEMY_API_KEY)
npx hardhat run scripts/mainnet_snapshot.js --network mainnet

# Audit deployed contracts setup across chains
node scripts/audit_chains/audit_contracts_setup.js
```

## Architecture

### Core-Periphery Pattern
The system uses a core-periphery architecture where core contracts (ERC721 registries) are primarily accessed via peripheral manager contracts.

**Abstract Base Contracts:**
- `GenericRegistry`: Base ERC721 registry with owner/manager roles, CID prefix handling
- `UnitRegistry`: Extends GenericRegistry for components/agents with dependency tracking
- `GenericManager`: Base manager contract for periphery
- `StakingBase`: Base staking contract

**Core Contracts (ERC721):**
- `ComponentRegistry`: Registry for agent components
- `AgentRegistry`: Registry for canonical agents (composed of components)
- `ServiceRegistry` (L1) / `ServiceRegistryL2` (L2): Registry for services
- `ServiceRegistryTokenUtility`: Token utility for service registration

**Periphery Contracts (Managers):**
- `RegistriesManager`: Manager for component and agent registries
- `ServiceManager`: Manager for service lifecycle operations
- `ServiceManagerProxy`: Proxy pattern for service manager upgrades

**Utility Contracts:**
- `OperatorSignedHashes`: For operator signature verification
- `OperatorWhitelist`: Whitelist management for operators

### Service State Machine

Services follow a strict state machine (see docs/FSM.md):

1. **NonExistent** → `createService()` → **PreRegistration**
2. **PreRegistration** → `activateRegistration()` → **ActiveRegistration**
   - Can call `update()` to modify config while in PreRegistration
3. **ActiveRegistration** → `registerAgents()` → **FinishedRegistration** (when all slots filled)
   - Can call `terminate()` to go back to PreRegistration (if no agents) or TerminatedBonded (if agents registered)
4. **FinishedRegistration** → `deploy()` → **Deployed**
   - Can call `terminate()` → TerminatedBonded
5. **Deployed** → `terminate()` → **TerminatedBonded**
6. **TerminatedBonded** → `unbond()` → **PreRegistration** (when all agents unbonded)

### Dependency Management

Components and agents track their dependencies:
- Components can depend on other components
- Agents depend on components (which may have their own component dependencies)
- The system maintains `mapSubComponents` to track the full dependency tree
- Dependencies are stored as `uint32[]` arrays and must be provided in sorted ascending order

### Multisig Implementations

Services are deployed as multisigs. Multiple implementations are supported via the `IMultisig` interface:

- `GnosisSafeMultisig`: Standard Safe multisig deployment
- `GnosisSafeSameAddressMultisig`: Allows upgrading/downgrading agent instances while keeping the same multisig address
- `SafeMultisigWithRecoveryModule`: Includes Recovery Module for access recovery
- `RecoveryModule`: Provides recovery functionality for Safe multisigs
- `PolySafeCreatorWithRecoveryModule`: Creates Safe multisigs with recovery on Polygon/other chains
- `SafeAndDepositWalletCreator`: Creates a Safe multisig with Recovery Module and links it to a Polymarket deposit wallet (Polygon-specific). The Safe is the OLAS service multisig + ERC-8004 agent wallet; the deposit wallet is a separate per-service Polymarket trading account, deployed out-of-band by Polymarket's relayer with the agent-instance EOA as its sole owner. The two are independent peers bridged by the agent EOA — the Safe cannot own the deposit wallet because Polymarket's `_erc1271IsValidSignatureNowCalldata` is pure ECDSA. See `docs/polymarket/clob_v2_deposit_wallet_creator_plan.md` for the full design (and `docs/polymarket/clob_v2_impact_polySafeCreator.md` / `docs/polymarket/clob_v2_impact_subgraphs.md` for impact write-ups).

Multisig policies are tracked in `mapMultisigs` mapping in ServiceRegistry.

### Polymarket CLOB v2 — deposit-wallet flow

Under the CLOB v2 rollout (2026-05-01), new accounts must use deposit wallets to trade on Polymarket; new PolySafes are off-allowlist at the CLOB API ingest service. `SafeAndDepositWalletCreator` is the migration path: a single on-chain user transaction (`ServiceManager.deploy(serviceId, creator, data)`) deploys the Safe with RecoveryModule enabled atomically and verifies a pre-deployed deposit wallet, while off-chain HTTP calls to Polymarket's relayer (which is the only caller authorized to deploy deposit wallets — `DepositWalletFactory.deploy` is `onlyOperator`) handle the wallet provisioning and the post-deploy session-signer + approvals batch (`factory.proxy`). ERC-8004 `setAgentWallet` works through the Safe via the standard `SignMessageLib` + `CompatibilityFallbackHandler` path — no special multisig logic required, the Safe just needs the `CompatibilityFallbackHandler` set as its fallback (passed in via `data` to the creator). The end-to-end flow is exercised by `test/SafeAndDepositWalletCreatorFork.sol::SafeAndDepositWalletCreatorE2E`.

### Staking Contracts

Staking system for services (see docs/StakingSmartContracts.pdf):

- `StakingBase`: Abstract base for staking implementations
- `StakingNativeToken`: Staking with native chain tokens (ETH, MATIC, etc.)
- `StakingToken`: Staking with ERC20 tokens
- `StakingFactory`: Factory for deploying staking instances
- `StakingProxy`: Proxy pattern for staking contracts
- `StakingVerifier`: Verification logic for staking
- `StakingActivityChecker`: Checks service activity for staking eligibility

### IPFS Hash Handling

The system uses IPFS CIDv1 with specific requirements:
- **Multibase:** base16 (prefix `f`)
- **Multicodec:** dag-pb (`0x70`)
- **Hash function:** sha2-256 (`0x12`)
- **Hash length:** 256 bits (`0x20`)

Only the 32-byte content hash is stored on-chain. The prefix `f01701220` (constant `CID_PREFIX`) is prepended when constructing full CIDs.

To convert existing CIDs: `ipfs cid format -v 1 -b base16 <your_ipfs_hash>`

### Contract Configuration

**Solidity version:** 0.8.30
**EVM version:** prague
**Optimizer:** enabled with 750 runs

Both Hardhat and Foundry are configured identically for compilation.

### Multi-Chain Support

The protocol is deployed across multiple chains. See `docs/configuration.json` for addresses. Network configurations in `hardhat.config.js` include:

**Mainnets:** ethereum, polygon, gnosis, arbitrum, optimism, base, celo, mode
**Testnets:** sepolia, polygonAmoy, chiado, arbitrumSepolia, optimismSepolia, baseSepolia, celoAlfajores, modeSepolia

### Important Constraints

- Contracts do NOT work with fee-on-transfer tokens
- Contracts do NOT handle balance changes outside token transfers
- Component/agent/service counters start from 1 (Id 0 is reserved/empty)
- Reentrancy protection uses a simple `_locked` variable pattern
- Maximum unit IDs are bounded by `uint32` (~4.2 billion)

### Recovery Module & Fund Recovery

When an Agent EOA private key is lost, the `RecoveryModule` contract allows the service owner (Master Safe) to regain sole ownership of the Agent Safe. The full recovery script is at `scripts/recover_funds_lost_agent_eoa.py` with detailed documentation in `docs/recover_funds_lost_agent_eoa.md`.

**Recovery flow**: unstake (if staked) -> terminate -> unbond -> `recoveryModule.recoverAccess(serviceId)` -> sweep funds via MultiSend.

Key contracts involved:
- `contracts/multisigs/RecoveryModule.sol`: `recoverAccess(serviceId)` removes all Agent Safe owners and makes the service owner the sole owner
- `contracts/multisigs/SafeMultisigWithRecoveryModule.sol`: Creates Safe proxies with the RecoveryModule pre-enabled
- `contracts/staking/StakingBase.sol`: `unstake(serviceId)` returns service NFT to the owner. `getServiceInfo(serviceId)` exposes the actual service owner when staked.

The recovery script uses Safe v=1 (sender-approved) signatures where Master Safe is both msg.sender and the sole owner. Forge tests covering all recovery scenarios are in `test/RecoverFunds.t.sol`.

## Key Files and Locations

- **Contracts:** `contracts/`
- **Tests:** `test/` (JavaScript with Hardhat), `test/*.t.sol` (Solidity with Forge)
- **Deployment scripts:** `scripts/deployment/`
- **Recovery script:** `scripts/recover_funds_lost_agent_eoa.py` (see `docs/recover_funds_lost_agent_eoa.md`)
- **ABIs:** `abis/` (organized by Solidity version)
- **Documentation:** `docs/`
- **Contract addresses per chain:** `docs/configuration.json`
- **Solana integration:** `integrations/solana/`

## Development Notes

- When using `web3.py` with Polygon (or other POA chains), inject `geth_poa_middleware` before making calls — Polygon blocks have >32 byte `extraData` which causes `ExtraDataLengthError` without it
- When encoding calldata for Safe transactions (without sending), use `contract.functions.func(args)._encode_transaction_data()` instead of `build_transaction()["data"]` to avoid unnecessary gas estimation RPC calls that may revert (e.g., MultiSend enforces delegatecall-only)
- Gnosis Safe v1.3.0 signature types: `v=27/28` for ECDSA, `v=0` for contract signature, `v=1` for sender-approved (msg.sender is owner, no actual signature needed — `r=address padded to 32 bytes, s=0, v=1`)
- `StakingBase.stake` has two overloads (`stake(uint256)` and `stake(uint256,uint256)`), so `StakingBase.stake.selector` is ambiguous in Solidity. Use `bytes4(keccak256("stake(uint256)"))` instead. Same applies to other overloaded functions.
- The `manager` role (not `owner`) typically calls `create()` functions on registries
- Service ownership transfers happen during deployment (service owner gives up multisig ownership to agent instances)
- When working with service registration, always verify the state machine constraints
- Bond amounts are stored as `uint96` (sufficient for 1b+ ETH or 1e27 wei)
- Agent instance addresses must be unique across the protocol (tracked in `mapAgentInstanceOperators`)
- Historical IPFS hashes are preserved in `mapUnitIdHashes` and `mapConfigHashes` but not checked for duplicates
