# Recover Funds When Agent EOA Is Lost

This document describes the design and usage of `scripts/recover_funds_lost_agent_eoa.py`, a script that recovers funds from an Agent Safe (service multisig) when the Agent EOA private key has been lost.

## Background

In the Olas protocol, a service is deployed as a Gnosis Safe multisig (the "Agent Safe") owned by agent instance EOAs. When the Agent EOA key is lost, the service owner (Master Safe) can regain control of the Agent Safe through the RecoveryModule, and then sweep all remaining funds back to the Master Safe.

### Key Actors

| Actor | Description |
|-------|-------------|
| **Master EOA** | The externally owned account that signs transactions. Owns the Master Safe. |
| **Master Safe** | A Gnosis Safe v1.3.0 with threshold=1. The service owner (holds the service NFT). Has at least 2 owners: Master EOA + backup address. |
| **Agent EOA** | The agent instance EOA whose private key is **lost**. Was an owner of the Agent Safe. |
| **Agent Safe** | The service multisig (Gnosis Safe v1.3.0) created when the service was deployed. Holds the funds to recover. |
| **Staking Proxy** | (Optional) A staking contract that may hold the service NFT if the service is currently staked. |

### Recovery Flow

The script handles the full lifecycle automatically:

```
1. [If staked]  Master EOA -> Master Safe -> stakingProxy.unstake(serviceId)
2. [If Deployed] Master EOA -> Master Safe -> serviceManager.terminate(serviceId)
3. [If TerminatedBonded] Master EOA -> Master Safe -> serviceManager.unbond(serviceId)
4. [If Agent Safe not owned by Master Safe] Master EOA -> Master Safe -> recoveryModule.recoverAccess(serviceId)
5. Master EOA -> Master Safe -> Agent Safe.execTransaction(multiSend: transfer all tokens to Master Safe)
```

Each step is skipped if the service is already past that state.

---

## Prerequisites

### Python Dependencies

```bash
pip install web3 eth_account
```

### Information Needed

- **Service ID**: The on-chain service ID to recover
- **Chain ID**: The chain where the service is deployed
- **RPC URL**: An RPC endpoint for the target chain
- **Master EOA key**: One of: private key file, `PRIVATE_KEY` env var, or `--impersonate` for fork testing

The script auto-detects the Master Safe address from the service registry. If the service is staked, it detects the staking contract and resolves the actual owner from `stakingProxy.getServiceInfo(serviceId).owner`.

### Supported Chains

The script loads contract addresses from `docs/configuration.json`. Token lists for recovery are fetched at runtime from the [olas-operate-app token config](https://github.com/valory-xyz/olas-operate-app/blob/main/frontend/config/tokens.ts).

| Chain | Chain ID |
|-------|----------|
| Ethereum | 1 |
| Polygon | 137 |
| Gnosis | 100 |
| Base | 8453 |
| Optimism | 10 |
| Arbitrum | 42161 |
| Celo | 42220 |
| Mode | 34443 |

---

## Usage

### Production Mode (with private key)

```bash
# Using a private key file
python scripts/recover_funds_lost_agent_eoa.py \
  --service-id 42 \
  --chain-id 100 \
  --rpc-url https://rpc.gnosischain.com \
  --private-key-file /path/to/master_eoa.key

# Using PRIVATE_KEY environment variable
export PRIVATE_KEY=0xabcdef...
export RPC_URL=https://rpc.gnosischain.com
python scripts/recover_funds_lost_agent_eoa.py \
  --service-id 42 \
  --chain-id 100
```

The private key file should contain the raw hex private key (with or without `0x` prefix).

### Fork Testing Mode (Tenderly / Anvil)

For testing without a private key, use `--impersonate` on a fork RPC. This sends unsigned transactions that the fork accepts from any address.

```bash
# Create a Tenderly fork or Anvil fork of the target chain, then:
python scripts/recover_funds_lost_agent_eoa.py \
  --service-id 109 \
  --chain-id 137 \
  --rpc-url https://virtual.polygon.eu.rpc.tenderly.co/<fork-id> \
  --impersonate 0xMasterEOAAddress
```

### CLI Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `--service-id` | Yes | Service ID to recover |
| `--chain-id` | Yes | Chain ID where the service lives |
| `--rpc-url` | No | RPC endpoint (or set `RPC_URL` env var) |
| `--private-key-file` | No | Path to file containing the Master EOA private key |
| `--ledger` | No | Use Ledger hardware wallet (not yet implemented) |
| `--derivation-path` | No | Ledger derivation path (default: `m/44'/60'/0'/0/0`) |
| `--impersonate` | No | EOA address to impersonate on fork RPCs (no signing needed) |

### Example Output

```
Connected to chain 137
Master EOA (impersonated): 0x7945E6D6665B569eaE7E8465915bBf49205C7708
MultiSend address: 0x40A2aCCbd92BCA938b02010E17A5b8929b49130D

--- Checking service ---
Service 109:
  NFT holder: 0xcE6192e447560A17eEB2CEc64726000bE4446179
  Multisig (Agent Safe): 0x0FFAD2468e9Cc611761a8052791E56756Db6F137
  State: PreRegistration (1)
  Service owner (Master Safe): 0xcE6192e447560A17eEB2CEc64726000bE4446179

--- Validating Master Safe ---
Master Safe owners: ['0x24786ba2BF5A6dB021518fFA669eb0c63c225513', '0x7945E6D6665B569eaE7E8465915bBf49205C7708']
Master Safe threshold: 1

Agent Safe owners: ['0xcE6192e447560A17eEB2CEc64726000bE4446179']
Agent Safe sole owner is already Master Safe. Skipping recovery.

--- Recovering funds ---
Found 3 ERC20 token(s) for chain 137:
  OLAS: 27.46 (27463850837138520060 wei)
  USDC: 1320.41 (1320413562 wei)
  USDC.e: 1012.16 (1012155666 wei)
  Native token: 2.0 (2000000000000000000 wei)

Building multicall with 4 transfer(s)...
Executing fund recovery transaction...
  Transaction sent: 0xe335...22df9

--- Recovery Summary ---
Recovered from Agent Safe (0x0FFA...F137) to Master Safe (0xcE61...6179):
  OLAS: 27.46
  USDC: 1320.41
  USDC.e: 1012.16
  Native: 2.0

All ERC20 funds recovered successfully.
```

---

## How It Works

### Step-by-Step

1. **Service discovery**: Queries `serviceRegistry.ownerOf(serviceId)` to find the NFT holder. If the holder is a contract, tries `getServiceInfo(serviceId)` on it to detect staking. The actual service owner (Master Safe) is resolved either directly or from the staking contract's `ServiceInfo.owner` field.

2. **Master Safe validation**: Verifies the Master EOA is an owner of the Master Safe and the threshold is 1 (required for single-signer execution).

3. **Operator discovery**: Before any state changes, queries `serviceRegistry.getAgentInstances(serviceId)` and `mapAgentInstanceOperators()` to find all operators. This is needed for the unbond step.

4. **Unstake** (if staked): Master Safe calls `stakingProxy.unstake(serviceId)`, which transfers the service NFT back to Master Safe. The service remains in Deployed state.

5. **Terminate** (if Deployed/Active/FinishedRegistration): Master Safe calls `serviceManager.terminate(serviceId)`, moving the service to TerminatedBonded (if agents were registered) or PreRegistration.

6. **Unbond** (if TerminatedBonded): For each operator, calls `serviceManager.unbond(serviceId)`. In the typical olas-operate-app flow, Master Safe is the operator. If an operator is not Master Safe and we're in impersonate mode, the script impersonates the operator directly. In production mode with a non-Master-Safe operator, the script errors out.

7. **Recovery**: With the service in PreRegistration state, Master Safe calls `recoveryModule.recoverAccess(serviceId)`. The RecoveryModule removes all Agent Safe owners and sets Master Safe as the sole owner (threshold=1).

8. **Fund transfer**: Builds a MultiSend multicall that Agent Safe executes via delegatecall, transferring all ERC20 tokens (fetched from the olas-operate-app token config) and native tokens to Master Safe. The Master Safe uses a v=1 (sender-approved) Safe signature since it is the sole owner and msg.sender.

### Safe Signature Types Used

- **ECDSA (v=27/28)**: Master EOA signs the Master Safe transaction hash. Used for all Master Safe `execTransaction` calls in production mode.
- **Sender-approved (v=1)**: Used for Agent Safe's `execTransaction` where Master Safe is both the sole owner and `msg.sender`. Format: `r = masterSafe address (32 bytes) | s = 0 (32 bytes) | v = 1 (1 byte)`.
- **Impersonate mode**: Uses v=1 sender-approved signatures on both Master Safe and Agent Safe, combined with unsigned `eth_sendTransaction` calls that Tenderly/Anvil forks accept.

### Contract Dependencies

All addresses are loaded from `docs/configuration.json` at runtime:
- `ServiceRegistry` (chain 1) or `ServiceRegistryL2` (all L2 chains)
- `RecoveryModule`
- `ServiceManager` / `ServiceManagerProxy`
- `MultiSend` (read from `recoveryModule.multiSend()` immutable)

### Limitations

- Master Safe threshold must be 1. For threshold > 1, additional owner signatures would be needed.
- If the operator is not Master Safe, production mode cannot unbond (need operator's key). Fork testing mode can impersonate.
- Ledger hardware wallet signing is not yet implemented.
- Only recovers tokens listed in the olas-operate-app token config for the given chain. Other tokens in the Agent Safe are not recovered.

---

## Testing

### Forge Tests

The Solidity test `test/RecoverFunds.t.sol` covers:

```bash
forge test --match-contract RecoverFunds -vvv
```

| Test | Description |
|------|-------------|
| `test_recoverAccess_and_transferFunds` | Full flow: recover ownership + transfer ERC20s + native |
| `test_skipRecovery_whenAlreadyOwner` | Skip recovery when Agent Safe already owned by Master Safe |
| `test_recoverNativeTokenOnly` | Recover only native tokens |
| `test_recoverAccess_multipleAgentInstances` | Recovery with 2 agent instances |
| `test_recoverFromStakedService` | Full flow from staked state: unstake -> terminate -> unbond -> recover -> transfer |

### Fork Testing with Tenderly

1. Go to [Tenderly](https://dashboard.tenderly.co/) and create a Virtual TestNet fork of the target chain
2. Copy the RPC URL
3. Run the script with `--impersonate`:

```bash
python scripts/recover_funds_lost_agent_eoa.py \
  --service-id <ID> \
  --chain-id <CHAIN> \
  --rpc-url <TENDERLY_FORK_RPC> \
  --impersonate <MASTER_EOA_ADDRESS>
```

This lets you verify the full recovery flow without spending real funds or needing the Master EOA private key.
