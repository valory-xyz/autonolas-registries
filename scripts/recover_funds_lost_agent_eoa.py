#!/usr/bin/env python3
"""
Recover funds from an Agent Safe after gaining ownership via RecoveryModule.

Full flow (handles staked services automatically):
  1. If service is staked: Master Safe -> stakingProxy.unstake(serviceId)
  2. If service is Deployed: Master Safe -> serviceManager.terminate(serviceId)
  3. If service is TerminatedBonded: Master Safe -> serviceManager.unbond(serviceId) per operator
  4. Master Safe -> recoveryModule.recoverAccess(serviceId) (makes Master Safe sole owner of Agent Safe)
  5. Master EOA -> Master Safe -> Agent Safe.execTransaction(multiSend transfer all tokens)

Usage:
  python recover_funds_lost_agent_eoa.py --service-id 42 --chain-id 100
  python recover_funds_lost_agent_eoa.py --service-id 42 --chain-id 100 --private-key-file /path/to/key
  python recover_funds_lost_agent_eoa.py --service-id 42 --chain-id 100 --ledger --derivation-path "m/44'/60'/0'/0/0"

Testing on a Tenderly/Anvil fork (no private key needed):
  python recover_funds_lost_agent_eoa.py --service-id 42 --chain-id 100 \
    --rpc-url https://rpc.tenderly.co/fork/... --impersonate 0xMasterEOA
"""

import argparse
import json
import os
import re
import sys
import urllib.request
import warnings
from pathlib import Path

# Suppress eth_utils network warnings about unknown chain IDs
warnings.filterwarnings("ignore", message="Network .* does not have a valid ChainId", category=UserWarning)

from web3 import Web3
from web3.middleware import geth_poa_middleware
from eth_account import Account

# ---------------------------------------------------------------------------
# Minimal ABIs (only the functions we call)
# ---------------------------------------------------------------------------

SAFE_ABI = json.loads("""[
  {
    "inputs": [],
    "name": "getOwners",
    "outputs": [{"internalType": "address[]", "name": "", "type": "address[]"}],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [],
    "name": "getThreshold",
    "outputs": [{"internalType": "uint256", "name": "", "type": "uint256"}],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [],
    "name": "nonce",
    "outputs": [{"internalType": "uint256", "name": "", "type": "uint256"}],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [
      {"internalType": "address", "name": "to", "type": "address"},
      {"internalType": "uint256", "name": "value", "type": "uint256"},
      {"internalType": "bytes", "name": "data", "type": "bytes"},
      {"internalType": "uint8", "name": "operation", "type": "uint8"},
      {"internalType": "uint256", "name": "safeTxGas", "type": "uint256"},
      {"internalType": "uint256", "name": "baseGas", "type": "uint256"},
      {"internalType": "uint256", "name": "gasPrice", "type": "uint256"},
      {"internalType": "address", "name": "gasToken", "type": "address"},
      {"internalType": "address payable", "name": "refundReceiver", "type": "address"},
      {"internalType": "bytes", "name": "signatures", "type": "bytes"}
    ],
    "name": "execTransaction",
    "outputs": [{"internalType": "bool", "name": "success", "type": "bool"}],
    "stateMutability": "payable",
    "type": "function"
  },
  {
    "inputs": [
      {"internalType": "address", "name": "to", "type": "address"},
      {"internalType": "uint256", "name": "value", "type": "uint256"},
      {"internalType": "bytes", "name": "data", "type": "bytes"},
      {"internalType": "uint8", "name": "operation", "type": "uint8"},
      {"internalType": "uint256", "name": "safeTxGas", "type": "uint256"},
      {"internalType": "uint256", "name": "baseGas", "type": "uint256"},
      {"internalType": "uint256", "name": "gasPrice", "type": "uint256"},
      {"internalType": "address", "name": "gasToken", "type": "address"},
      {"internalType": "address", "name": "refundReceiver", "type": "address"},
      {"internalType": "uint256", "name": "_nonce", "type": "uint256"}
    ],
    "name": "getTransactionHash",
    "outputs": [{"internalType": "bytes32", "name": "", "type": "bytes32"}],
    "stateMutability": "view",
    "type": "function"
  }
]""")

SERVICE_REGISTRY_ABI = json.loads("""[
  {
    "inputs": [{"internalType": "uint256", "name": "serviceId", "type": "uint256"}],
    "name": "mapServices",
    "outputs": [
      {"internalType": "uint96", "name": "securityDeposit", "type": "uint96"},
      {"internalType": "address", "name": "multisig", "type": "address"},
      {"internalType": "bytes32", "name": "configHash", "type": "bytes32"},
      {"internalType": "uint32", "name": "threshold", "type": "uint32"},
      {"internalType": "uint32", "name": "maxNumAgentInstances", "type": "uint32"},
      {"internalType": "uint32", "name": "numAgentInstances", "type": "uint32"},
      {"internalType": "uint8", "name": "state", "type": "uint8"}
    ],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [{"internalType": "uint256", "name": "tokenId", "type": "uint256"}],
    "name": "ownerOf",
    "outputs": [{"internalType": "address", "name": "", "type": "address"}],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [{"internalType": "uint256", "name": "serviceId", "type": "uint256"}],
    "name": "getAgentInstances",
    "outputs": [
      {"internalType": "uint256", "name": "numAgentInstances", "type": "uint256"},
      {"internalType": "address[]", "name": "agentInstances", "type": "address[]"}
    ],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [{"internalType": "address", "name": "", "type": "address"}],
    "name": "mapAgentInstanceOperators",
    "outputs": [{"internalType": "address", "name": "", "type": "address"}],
    "stateMutability": "view",
    "type": "function"
  }
]""")

RECOVERY_MODULE_ABI = json.loads("""[
  {
    "inputs": [{"internalType": "uint256", "name": "serviceId", "type": "uint256"}],
    "name": "recoverAccess",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function"
  },
  {
    "inputs": [],
    "name": "multiSend",
    "outputs": [{"internalType": "address", "name": "", "type": "address"}],
    "stateMutability": "view",
    "type": "function"
  }
]""")

MULTISEND_ABI = json.loads("""[
  {
    "inputs": [{"internalType": "bytes", "name": "transactions", "type": "bytes"}],
    "name": "multiSend",
    "outputs": [],
    "stateMutability": "payable",
    "type": "function"
  }
]""")

ERC20_ABI = json.loads("""[
  {
    "inputs": [{"internalType": "address", "name": "account", "type": "address"}],
    "name": "balanceOf",
    "outputs": [{"internalType": "uint256", "name": "", "type": "uint256"}],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [
      {"internalType": "address", "name": "to", "type": "address"},
      {"internalType": "uint256", "name": "amount", "type": "uint256"}
    ],
    "name": "transfer",
    "outputs": [{"internalType": "bool", "name": "", "type": "bool"}],
    "stateMutability": "nonpayable",
    "type": "function"
  },
  {
    "inputs": [],
    "name": "symbol",
    "outputs": [{"internalType": "string", "name": "", "type": "string"}],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [],
    "name": "decimals",
    "outputs": [{"internalType": "uint8", "name": "", "type": "uint8"}],
    "stateMutability": "view",
    "type": "function"
  }
]""")

STAKING_ABI = json.loads("""[
  {
    "inputs": [{"internalType": "uint256", "name": "serviceId", "type": "uint256"}],
    "name": "getServiceInfo",
    "outputs": [
      {
        "components": [
          {"internalType": "address", "name": "multisig", "type": "address"},
          {"internalType": "address", "name": "owner", "type": "address"},
          {"internalType": "uint256[]", "name": "nonces", "type": "uint256[]"},
          {"internalType": "uint256", "name": "tsStart", "type": "uint256"},
          {"internalType": "uint256", "name": "reward", "type": "uint256"},
          {"internalType": "uint256", "name": "inactivity", "type": "uint256"},
          {"internalType": "uint256", "name": "rewardDistributionInfo", "type": "uint256"}
        ],
        "internalType": "struct ServiceInfo",
        "name": "sInfo",
        "type": "tuple"
      }
    ],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [{"internalType": "uint256", "name": "serviceId", "type": "uint256"}],
    "name": "unstake",
    "outputs": [{"internalType": "uint256", "name": "", "type": "uint256"}],
    "stateMutability": "nonpayable",
    "type": "function"
  },
  {
    "inputs": [{"internalType": "uint256", "name": "serviceId", "type": "uint256"}],
    "name": "getStakingState",
    "outputs": [{"internalType": "uint8", "name": "stakingState", "type": "uint8"}],
    "stateMutability": "view",
    "type": "function"
  }
]""")

SERVICE_MANAGER_ABI = json.loads("""[
  {
    "inputs": [{"internalType": "uint256", "name": "serviceId", "type": "uint256"}],
    "name": "terminate",
    "outputs": [
      {"internalType": "bool", "name": "success", "type": "bool"},
      {"internalType": "uint256", "name": "refund", "type": "uint256"}
    ],
    "stateMutability": "nonpayable",
    "type": "function"
  },
  {
    "inputs": [{"internalType": "uint256", "name": "serviceId", "type": "uint256"}],
    "name": "unbond",
    "outputs": [
      {"internalType": "bool", "name": "success", "type": "bool"},
      {"internalType": "uint256", "name": "refund", "type": "uint256"}
    ],
    "stateMutability": "nonpayable",
    "type": "function"
  }
]""")

ZERO_ADDRESS = "0x0000000000000000000000000000000000000000"

# Safe operation types
CALL = 0
DELEGATECALL = 1  # Required for MultiSend (it enforces delegatecall-only via singleton check)

# Service states from ServiceRegistryL2
SERVICE_STATE_NAMES = {
    0: "NonExistent",
    1: "PreRegistration",
    2: "ActiveRegistration",
    3: "FinishedRegistration",
    4: "Deployed",
    5: "TerminatedBonded",
}

# Staking states from StakingBase
STAKING_STATE_NAMES = {
    0: "Unstaked",
    1: "Staked",
    2: "Evicted",
}

# Token config URL
TOKENS_TS_URL = "https://raw.githubusercontent.com/valory-xyz/olas-operate-app/main/frontend/config/tokens.ts"


# ---------------------------------------------------------------------------
# Token fetching
# ---------------------------------------------------------------------------

def fetch_url(url: str) -> str:
    """Fetch text content from a URL."""
    req = urllib.request.Request(url, headers={"User-Agent": "recover_funds_lost_agent_eoa.py"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        return resp.read().decode("utf-8")



def parse_tokens(tokens_ts: str) -> dict:
    """
    Parse tokens.ts to extract ERC20 token addresses per chain config block.
    Returns: {chain_config_name: [{"address": "0x...", "symbol": "...", "decimals": N}, ...]}
    """
    chain_configs = {}

    # Match each *_TOKEN_CONFIG block by finding the opening brace and balancing
    config_pattern = re.compile(
        r"(?:const|export\s+const)\s+(\w+_TOKEN_CONFIG)\s*:\s*ChainTokenConfig\s*=\s*\{",
    )

    for config_match in config_pattern.finditer(tokens_ts):
        config_name = config_match.group(1)
        # Find the balanced closing brace for this config block
        start = config_match.end()
        depth = 1
        pos = start
        while pos < len(tokens_ts) and depth > 0:
            if tokens_ts[pos] == "{":
                depth += 1
            elif tokens_ts[pos] == "}":
                depth -= 1
            pos += 1
        config_body = tokens_ts[start:pos - 1]

        tokens = []

        # Match token entries with both dot notation and bracket notation:
        #   [TokenSymbolMap.OLAS]: { ... }
        #   [TokenSymbolMap['USDC.e']]: { ... }
        entry_pattern = re.compile(
            r"\[TokenSymbolMap(?:\.(\w+)|\[['\"]([^'\"]+)['\"]\])\]\s*:\s*\{",
            re.DOTALL,
        )

        for entry_match in entry_pattern.finditer(config_body):
            symbol = entry_match.group(1) or entry_match.group(2)

            # Extract the entry body by finding balanced braces
            entry_start = entry_match.end()
            depth = 1
            epos = entry_start
            while epos < len(config_body) and depth > 0:
                if config_body[epos] == "{":
                    depth += 1
                elif config_body[epos] == "}":
                    depth -= 1
                epos += 1
            entry_body = config_body[entry_start:epos - 1]

            # Skip native gas tokens (no address field)
            address_match = re.search(r"address\s*:\s*['\"]([^'\"]+)['\"]", entry_body)
            if not address_match:
                continue

            address = address_match.group(1)
            decimals_match = re.search(r"decimals\s*:\s*(\d+)", entry_body)
            decimals = int(decimals_match.group(1)) if decimals_match else 18

            tokens.append({
                "address": address,
                "symbol": symbol,
                "decimals": decimals,
            })

        chain_configs[config_name] = tokens

    return chain_configs


def fetch_token_config(chain_id: int) -> list:
    """
    Fetch and parse token configuration from the olas-operate-app repo.
    Returns list of ERC20 tokens for the given chain ID: [{"address": ..., "symbol": ..., "decimals": ...}]
    """
    # Map chain IDs to config block names
    chain_id_to_config = {
        1: "ETHEREUM_TOKEN_CONFIG",
        100: "GNOSIS_TOKEN_CONFIG",
        8453: "BASE_TOKEN_CONFIG",
        34443: "MODE_TOKEN_CONFIG",
        10: "OPTIMISM_TOKEN_CONFIG",
        137: "POLYGON_TOKEN_CONFIG",
        42220: "CELO_TOKEN_CONFIG",
    }

    config_name = chain_id_to_config.get(chain_id)
    if not config_name:
        print(f"WARNING: No token config mapping for chain ID {chain_id}. No ERC20 tokens will be recovered.")
        return []

    print(f"Fetching token configuration from {TOKENS_TS_URL} ...")
    try:
        tokens_ts = fetch_url(TOKENS_TS_URL)
    except Exception as e:
        print(f"WARNING: Failed to fetch token config: {e}. No ERC20 tokens will be recovered.")
        return []

    chain_configs = parse_tokens(tokens_ts)
    tokens = chain_configs.get(config_name, [])

    if not tokens:
        print(f"WARNING: No ERC20 tokens found for {config_name} (chain {chain_id}).")
    else:
        print(f"Found {len(tokens)} ERC20 token(s) for chain {chain_id}:")
        for t in tokens:
            print(f"  {t['symbol']}: {t['address']} ({t['decimals']} decimals)")

    return tokens


# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

def load_configuration(chain_id: int) -> dict:
    """Load contract addresses from docs/configuration.json for the given chain."""
    config_path = Path(__file__).resolve().parent.parent / "docs" / "configuration.json"
    with open(config_path) as f:
        configs = json.load(f)

    for chain_config in configs:
        if str(chain_config["chainId"]) == str(chain_id):
            contracts = {}
            for c in chain_config["contracts"]:
                contracts[c["name"]] = c["address"]
            return contracts

    print(f"ERROR: Chain ID {chain_id} not found in {config_path}")
    sys.exit(1)


def get_service_registry_name(chain_id: int) -> str:
    """Return the service registry contract name for the chain."""
    return "ServiceRegistry" if chain_id == 1 else "ServiceRegistryL2"


# ---------------------------------------------------------------------------
# Safe transaction helpers
# ---------------------------------------------------------------------------

def encode_function_data(contract_func) -> bytes:
    """Encode a contract function call to raw bytes calldata (no gas estimation)."""
    data = contract_func._encode_transaction_data()
    return bytes.fromhex(data[2:] if data.startswith("0x") else data)


def encode_multisend_txs(txs: list) -> bytes:
    """
    Encode transactions for MultiSend.multiSend().
    Each tx: {to, value, data, operation}
    Packed format: uint8 operation | address to | uint256 value | uint256 dataLength | bytes data
    """
    packed = b""
    for tx in txs:
        operation = tx.get("operation", CALL)
        to_addr = bytes.fromhex(tx["to"][2:])
        value = tx.get("value", 0)
        data = tx.get("data", b"")
        if isinstance(data, str):
            data = bytes.fromhex(data[2:] if data.startswith("0x") else data)

        packed += (
            operation.to_bytes(1, "big")
            + to_addr
            + value.to_bytes(32, "big")
            + len(data).to_bytes(32, "big")
            + data
        )
    return packed


def build_safe_signature_for_eoa(account, tx_hash: bytes) -> bytes:
    """Build ECDSA signature (v=27/28) for an EOA signing a Safe tx hash."""
    signed = account.signHash(tx_hash)
    # Pack r (32 bytes) + s (32 bytes) + v (1 byte)
    return (
        signed.r.to_bytes(32, "big")
        + signed.s.to_bytes(32, "big")
        + signed.v.to_bytes(1, "big")
    )


def build_safe_signature_for_approved_owner(owner_address: str) -> bytes:
    """
    Build v=1 (sender-approved) signature for a Safe owner that is msg.sender.
    r = owner address padded to 32 bytes, s = 0, v = 1
    """
    return (
        bytes.fromhex(owner_address[2:]).rjust(32, b"\x00")
        + b"\x00" * 32
        + b"\x01"
    )


def exec_safe_tx(w3, safe_contract, account, to, value, data, operation):
    """
    Build, sign, and send a Safe execTransaction from an EOA owner.
    Returns the transaction receipt.
    """
    nonce = safe_contract.functions.nonce().call()

    tx_hash = safe_contract.functions.getTransactionHash(
        to, value, data, operation,
        0, 0, 0,  # safeTxGas, baseGas, gasPrice
        ZERO_ADDRESS, ZERO_ADDRESS,  # gasToken, refundReceiver
        nonce,
    ).call()

    signature = build_safe_signature_for_eoa(account, tx_hash)

    tx = safe_contract.functions.execTransaction(
        to, value, data, operation,
        0, 0, 0,
        ZERO_ADDRESS, ZERO_ADDRESS,
        signature,
    ).build_transaction({
        "from": account.address,
        "nonce": w3.eth.get_transaction_count(account.address),
        "gas": 0,  # will be estimated
    })

    # Estimate gas
    tx["gas"] = w3.eth.estimate_gas(tx)

    signed_tx = account.sign_transaction(tx)
    tx_hash_sent = w3.eth.send_raw_transaction(signed_tx.raw_transaction)
    print(f"  Transaction sent: {tx_hash_sent.hex()}")
    receipt = w3.eth.wait_for_transaction_receipt(tx_hash_sent)
    return receipt


def exec_safe_tx_impersonated(w3, safe_contract, sender_address, to, value, data, operation):
    """
    Build and send a Safe execTransaction via unsigned eth_sendTransaction
    (for Tenderly/Anvil forks where any address can be impersonated).
    Returns the transaction receipt.
    """
    nonce = safe_contract.functions.nonce().call()

    tx_hash = safe_contract.functions.getTransactionHash(
        to, value, data, operation,
        0, 0, 0,
        ZERO_ADDRESS, ZERO_ADDRESS,
        nonce,
    ).call()

    # Use v=1 sender-approved signature: since sender_address is msg.sender and an owner,
    # Safe's checkNSignatures accepts this without an actual ECDSA signature
    signature = build_safe_signature_for_approved_owner(sender_address)

    tx = safe_contract.functions.execTransaction(
        to, value, data, operation,
        0, 0, 0,
        ZERO_ADDRESS, ZERO_ADDRESS,
        signature,
    ).build_transaction({
        "from": sender_address,
        "nonce": w3.eth.get_transaction_count(sender_address),
        "gas": 0,
    })

    tx["gas"] = w3.eth.estimate_gas(tx)

    # Send unsigned — Tenderly/Anvil forks accept this for any address
    tx_hash_sent = w3.eth.send_transaction(tx)
    print(f"  Transaction sent: {tx_hash_sent.hex()}")
    receipt = w3.eth.wait_for_transaction_receipt(tx_hash_sent)
    return receipt


def send_tx_impersonated(w3, sender_address, to, data):
    """
    Send an unsigned transaction impersonating sender_address (for Tenderly/Anvil forks).
    Returns the transaction receipt.
    """
    tx = {
        "from": sender_address,
        "to": to,
        "data": data,
        "nonce": w3.eth.get_transaction_count(sender_address),
        "gas": 0,
    }
    tx["gas"] = w3.eth.estimate_gas(tx)
    tx_hash_sent = w3.eth.send_transaction(tx)
    print(f"  Transaction sent: {tx_hash_sent.hex()}")
    receipt = w3.eth.wait_for_transaction_receipt(tx_hash_sent)
    return receipt


def send_tx_signed(w3, account, to, data):
    """
    Sign and send a transaction from account.
    Returns the transaction receipt.
    """
    tx = {
        "from": account.address,
        "to": Web3.to_checksum_address(to),
        "data": data,
        "nonce": w3.eth.get_transaction_count(account.address),
        "gas": 0,
    }
    tx["gas"] = w3.eth.estimate_gas(tx)
    signed_tx = account.sign_transaction(tx)
    tx_hash_sent = w3.eth.send_raw_transaction(signed_tx.raw_transaction)
    print(f"  Transaction sent: {tx_hash_sent.hex()}")
    receipt = w3.eth.wait_for_transaction_receipt(tx_hash_sent)
    return receipt


# ---------------------------------------------------------------------------
# Key loading
# ---------------------------------------------------------------------------

def load_account(args) -> Account:
    """Load the Master EOA account from private key file, env var, or ledger."""
    if args.ledger:
        print("ERROR: Ledger support is not yet implemented.")
        print("  Please use --private-key-file or PRIVATE_KEY env variable instead.")
        sys.exit(1)

    private_key = None
    if args.private_key_file:
        key_path = Path(args.private_key_file)
        if not key_path.exists():
            print(f"ERROR: Private key file not found: {key_path}")
            sys.exit(1)
        private_key = key_path.read_text().strip()
    else:
        private_key = os.environ.get("PRIVATE_KEY")

    if not private_key:
        print("ERROR: No private key provided.")
        print("  Use --private-key-file, set PRIVATE_KEY env var, or use --ledger")
        sys.exit(1)

    if not private_key.startswith("0x"):
        private_key = "0x" + private_key

    account = Account.from_key(private_key)
    print(f"Master EOA: {account.address}")
    return account


# ---------------------------------------------------------------------------
# Staking detection
# ---------------------------------------------------------------------------

def detect_staking(w3, nft_holder_address, service_id):
    """
    Check if the service NFT holder is a staking contract.
    Returns (is_staked, staking_contract_or_None, actual_owner_address).

    If the NFT holder is a staking proxy, getServiceInfo(serviceId).owner gives the actual service owner.
    If the NFT holder is not a staking contract, it IS the actual owner (Master Safe).
    """
    # If NFT holder has no code, it's an EOA (the actual owner)
    code = w3.eth.get_code(nft_holder_address)
    if code == b"" or code == b"\x00":
        return False, None, nft_holder_address

    # Try calling getServiceInfo on the NFT holder — if it works, it's a staking contract
    staking_contract = w3.eth.contract(address=nft_holder_address, abi=STAKING_ABI)
    try:
        sinfo = staking_contract.functions.getServiceInfo(service_id).call()
        # sinfo is a tuple: (multisig, owner, nonces, tsStart, reward, inactivity, rewardDistributionInfo)
        actual_owner = sinfo[1]
        if actual_owner != ZERO_ADDRESS:
            return True, staking_contract, actual_owner
    except Exception:
        pass

    # Not a staking contract — the NFT holder is the actual owner
    return False, None, nft_holder_address


# ---------------------------------------------------------------------------
# Operator discovery
# ---------------------------------------------------------------------------

def get_service_operators(service_registry, service_id):
    """
    Get unique operator addresses for a service by querying agent instances.
    Returns list of unique operator addresses.
    Must be called while the service still has agent instances (before terminate deletes them).
    """
    try:
        num_instances, agent_instances = service_registry.functions.getAgentInstances(service_id).call()
    except Exception:
        return []

    operators = set()
    for instance in agent_instances:
        try:
            operator = service_registry.functions.mapAgentInstanceOperators(instance).call()
            if operator != ZERO_ADDRESS:
                operators.add(operator)
        except Exception:
            pass

    return list(operators)


# ---------------------------------------------------------------------------
# Main logic
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="Recover funds from an Agent Safe via RecoveryModule"
    )
    parser.add_argument("--service-id", required=True, type=int, help="Service ID to recover")
    parser.add_argument("--chain-id", required=True, type=int, help="Chain ID")
    parser.add_argument("--rpc-url", help="RPC URL (or set RPC_URL env var)")
    parser.add_argument("--private-key-file", help="Path to file containing private key")
    parser.add_argument("--ledger", action="store_true", help="Use Ledger hardware wallet")
    parser.add_argument("--derivation-path", default="m/44'/60'/0'/0/0",
                        help="Ledger derivation path (default: m/44'/60'/0'/0/0)")
    parser.add_argument("--impersonate", metavar="EOA_ADDRESS",
                        help="Impersonate an EOA address on a fork RPC (Tenderly/Anvil). "
                             "No private key needed. Sends unsigned transactions.")
    args = parser.parse_args()

    # --- Setup ---
    rpc_url = args.rpc_url or os.environ.get("RPC_URL")
    if not rpc_url:
        print("ERROR: No RPC URL provided. Use --rpc-url or set RPC_URL env var.")
        sys.exit(1)

    w3 = Web3(Web3.HTTPProvider(rpc_url))
    # Inject POA middleware for chains like Polygon that have >32 byte extraData
    w3.middleware_onion.inject(geth_poa_middleware, layer=0)
    if not w3.is_connected():
        print(f"ERROR: Cannot connect to RPC at {rpc_url}")
        sys.exit(1)

    on_chain_id = w3.eth.chain_id
    if on_chain_id != args.chain_id:
        print(f"ERROR: RPC chain ID ({on_chain_id}) does not match --chain-id ({args.chain_id})")
        sys.exit(1)

    print(f"Connected to chain {args.chain_id}")

    impersonate_mode = bool(args.impersonate)
    if impersonate_mode:
        master_eoa_address = Web3.to_checksum_address(args.impersonate)
        account = None
        print(f"Master EOA (impersonated): {master_eoa_address}")
    else:
        account = load_account(args)
        master_eoa_address = account.address

    service_id = args.service_id

    # Load contract addresses from configuration.json
    contracts = load_configuration(args.chain_id)

    registry_name = get_service_registry_name(args.chain_id)
    if registry_name not in contracts:
        print(f"ERROR: {registry_name} not found in configuration for chain {args.chain_id}")
        sys.exit(1)
    if "RecoveryModule" not in contracts:
        print(f"ERROR: RecoveryModule not found in configuration for chain {args.chain_id}")
        sys.exit(1)

    service_registry = w3.eth.contract(
        address=Web3.to_checksum_address(contracts[registry_name]),
        abi=SERVICE_REGISTRY_ABI,
    )
    recovery_module = w3.eth.contract(
        address=Web3.to_checksum_address(contracts["RecoveryModule"]),
        abi=RECOVERY_MODULE_ABI,
    )

    # Get ServiceManager address (proxy)
    sm_name = "ServiceManagerProxy" if "ServiceManagerProxy" in contracts else "ServiceManager"
    if sm_name not in contracts:
        print(f"ERROR: ServiceManager/ServiceManagerProxy not found in configuration for chain {args.chain_id}")
        sys.exit(1)
    service_manager = w3.eth.contract(
        address=Web3.to_checksum_address(contracts[sm_name]),
        abi=SERVICE_MANAGER_ABI,
    )

    # Read MultiSend address from the RecoveryModule (immutable)
    multisend_addr = recovery_module.functions.multiSend().call()
    print(f"MultiSend address: {multisend_addr}")
    multisend = w3.eth.contract(address=multisend_addr, abi=MULTISEND_ABI)

    # --- Step 1: Get Service Info & Detect Staking ---
    print("\n--- Checking service ---")
    service_info = service_registry.functions.mapServices(service_id).call()
    agent_safe_addr = service_info[1]  # multisig field
    service_state = service_info[6]    # state field

    if agent_safe_addr == ZERO_ADDRESS:
        print(f"ERROR: Service {service_id} has no multisig (zero address). Has it been deployed?")
        sys.exit(1)

    nft_holder = service_registry.functions.ownerOf(service_id).call()
    state_name = SERVICE_STATE_NAMES.get(service_state, f"Unknown({service_state})")
    print(f"Service {service_id}:")
    print(f"  NFT holder: {nft_holder}")
    print(f"  Multisig (Agent Safe): {agent_safe_addr}")
    print(f"  State: {state_name} ({service_state})")

    # Detect if service is staked
    is_staked, staking_contract, master_safe_addr = detect_staking(w3, nft_holder, service_id)
    master_safe_addr = Web3.to_checksum_address(master_safe_addr)

    if is_staked:
        staking_state = staking_contract.functions.getStakingState(service_id).call()
        staking_state_name = STAKING_STATE_NAMES.get(staking_state, f"Unknown({staking_state})")
        print(f"  Staking contract: {nft_holder}")
        print(f"  Staking state: {staking_state_name} ({staking_state})")
        print(f"  Actual service owner (Master Safe): {master_safe_addr}")
    else:
        print(f"  Service owner (Master Safe): {master_safe_addr}")

    # --- Step 2: Validate Master EOA -> Master Safe ---
    print("\n--- Validating Master Safe ---")
    master_safe = w3.eth.contract(address=master_safe_addr, abi=SAFE_ABI)
    master_owners = master_safe.functions.getOwners().call()
    master_threshold = master_safe.functions.getThreshold().call()
    print(f"Master Safe owners: {master_owners}")
    print(f"Master Safe threshold: {master_threshold}")

    if master_eoa_address not in master_owners:
        print(f"ERROR: Master EOA {master_eoa_address} is not an owner of Master Safe {master_safe_addr}")
        sys.exit(1)

    if master_threshold != 1:
        print(f"ERROR: Master Safe threshold is {master_threshold}, but this script only supports threshold=1.")
        print("  For threshold > 1, additional owner signatures are required.")
        sys.exit(1)

    # --- Step 3: Get operators (before any state changes) ---
    # Must get operators while service is in Deployed state (agent instances are available)
    operators = []
    if service_state in (2, 3, 4, 5):  # ActiveRegistration, FinishedRegistration, Deployed, TerminatedBonded
        operators = get_service_operators(service_registry, service_id)
        if operators:
            print(f"\nService operators: {operators}")

    # --- Step 4: Unstake (if staked) ---
    if is_staked:
        print(f"\n--- Unstaking service {service_id} ---")
        print(f"Master Safe -> stakingProxy.unstake({service_id})...")

        unstake_data = encode_function_data(staking_contract.functions.unstake(service_id))

        if impersonate_mode:
            receipt = exec_safe_tx_impersonated(
                w3, master_safe, master_eoa_address,
                to=nft_holder, value=0, data=unstake_data, operation=CALL,
            )
        else:
            receipt = exec_safe_tx(
                w3, master_safe, account,
                to=nft_holder, value=0, data=unstake_data, operation=CALL,
            )

        if receipt.status != 1:
            print(f"ERROR: Unstake transaction failed. Receipt: {receipt}")
            sys.exit(1)

        # Verify NFT is now held by Master Safe
        new_nft_holder = service_registry.functions.ownerOf(service_id).call()
        if new_nft_holder != master_safe_addr:
            print(f"ERROR: After unstake, NFT holder is {new_nft_holder}, expected {master_safe_addr}")
            sys.exit(1)
        print(f"Unstake successful. Service NFT now held by Master Safe.")

        # Re-read service state after unstake
        service_info = service_registry.functions.mapServices(service_id).call()
        service_state = service_info[6]
        state_name = SERVICE_STATE_NAMES.get(service_state, f"Unknown({service_state})")
        print(f"Service state after unstake: {state_name} ({service_state})")

    # --- Step 5: Terminate (if needed) ---
    if service_state in (2, 3, 4):  # ActiveRegistration, FinishedRegistration, Deployed
        print(f"\n--- Terminating service {service_id} ---")
        print(f"Master Safe -> serviceManager.terminate({service_id})...")

        terminate_data = encode_function_data(service_manager.functions.terminate(service_id))

        if impersonate_mode:
            receipt = exec_safe_tx_impersonated(
                w3, master_safe, master_eoa_address,
                to=service_manager.address, value=0, data=terminate_data, operation=CALL,
            )
        else:
            receipt = exec_safe_tx(
                w3, master_safe, account,
                to=service_manager.address, value=0, data=terminate_data, operation=CALL,
            )

        if receipt.status != 1:
            print(f"ERROR: Terminate transaction failed. Receipt: {receipt}")
            sys.exit(1)

        # Re-read service state
        service_info = service_registry.functions.mapServices(service_id).call()
        service_state = service_info[6]
        state_name = SERVICE_STATE_NAMES.get(service_state, f"Unknown({service_state})")
        print(f"Terminate successful. Service state: {state_name} ({service_state})")

    # --- Step 6: Unbond (if needed) ---
    if service_state == 5:  # TerminatedBonded
        print(f"\n--- Unbonding service {service_id} ---")

        if not operators:
            # Try to get operators now (may fail if agent instances were already cleaned)
            operators = get_service_operators(service_registry, service_id)

        if not operators:
            print("ERROR: Could not find any operators to unbond.")
            print("  The service is in TerminatedBonded state but no operators were found.")
            sys.exit(1)

        for operator in operators:
            operator = Web3.to_checksum_address(operator)
            print(f"Unbonding operator {operator}...")

            # ServiceManager.unbond(serviceId) uses msg.sender as the operator.
            # So the operator itself must call ServiceManager.unbond.
            if operator == master_safe_addr:
                # Master Safe IS the operator — call via Master Safe -> ServiceManager.unbond
                unbond_data = encode_function_data(service_manager.functions.unbond(service_id))

                if impersonate_mode:
                    receipt = exec_safe_tx_impersonated(
                        w3, master_safe, master_eoa_address,
                        to=service_manager.address, value=0, data=unbond_data, operation=CALL,
                    )
                else:
                    receipt = exec_safe_tx(
                        w3, master_safe, account,
                        to=service_manager.address, value=0, data=unbond_data, operation=CALL,
                    )
            else:
                # Operator is NOT Master Safe
                if impersonate_mode:
                    # On a fork, impersonate the operator directly
                    print(f"  (impersonating operator {operator})")
                    unbond_data = encode_function_data(service_manager.functions.unbond(service_id))
                    unbond_data_hex = "0x" + unbond_data.hex()
                    receipt = send_tx_impersonated(w3, operator, service_manager.address, unbond_data_hex)
                else:
                    print(f"ERROR: Operator {operator} is not Master Safe ({master_safe_addr}).")
                    print("  Cannot unbond this operator without their private key.")
                    print("  Options:")
                    print("    1. Have the operator call serviceManager.unbond() directly")
                    print("    2. Use unbondWithSignature() with the operator's signature")
                    print("    3. Test on a fork with --impersonate to impersonate the operator")
                    sys.exit(1)

            if receipt.status != 1:
                print(f"ERROR: Unbond transaction for operator {operator} failed. Receipt: {receipt}")
                sys.exit(1)
            print(f"  Operator {operator} unbonded successfully.")

        # Re-read service state
        service_info = service_registry.functions.mapServices(service_id).call()
        service_state = service_info[6]
        state_name = SERVICE_STATE_NAMES.get(service_state, f"Unknown({service_state})")
        print(f"Service state after unbond: {state_name} ({service_state})")

    # --- Step 7: Verify we're in PreRegistration ---
    if service_state != 1:
        state_name = SERVICE_STATE_NAMES.get(service_state, f"Unknown({service_state})")
        print(f"ERROR: Service must be in PreRegistration state (1) for recovery, but is in {state_name} ({service_state}).")
        sys.exit(1)

    # --- Step 8: Recovery (if needed) ---
    agent_safe = w3.eth.contract(address=Web3.to_checksum_address(agent_safe_addr), abi=SAFE_ABI)
    agent_owners = agent_safe.functions.getOwners().call()
    print(f"\nAgent Safe owners: {agent_owners}")

    if not (len(agent_owners) == 1 and agent_owners[0] == master_safe_addr):
        print("\n--- Recovering Agent Safe ownership ---")
        print(f"Agent Safe owners are not [Master Safe]. Calling recoverAccess({service_id})...")

        # Build recoverAccess calldata
        recover_data = encode_function_data(recovery_module.functions.recoverAccess(service_id))

        # Execute via Master Safe
        if impersonate_mode:
            receipt = exec_safe_tx_impersonated(
                w3, master_safe, master_eoa_address,
                to=recovery_module.address, value=0, data=recover_data, operation=CALL,
            )
        else:
            receipt = exec_safe_tx(
                w3, master_safe, account,
                to=recovery_module.address, value=0, data=recover_data, operation=CALL,
            )

        if receipt.status != 1:
            print(f"ERROR: Recovery transaction failed. Receipt: {receipt}")
            sys.exit(1)

        # Verify
        agent_owners = agent_safe.functions.getOwners().call()
        if not (len(agent_owners) == 1 and agent_owners[0] == master_safe_addr):
            print(f"ERROR: Recovery succeeded on-chain but Agent Safe owners are {agent_owners}, expected [{master_safe_addr}]")
            sys.exit(1)

        print(f"Recovery successful. Agent Safe sole owner is now Master Safe.")
    else:
        print("Agent Safe sole owner is already Master Safe. Skipping recovery.")

    # --- Step 9: Fund Recovery ---
    print("\n--- Recovering funds ---")

    # Fetch token config
    erc20_tokens = fetch_token_config(args.chain_id)

    # Check balances
    transfers = []
    recovered_summary = []

    # Check ERC20 balances
    for token_info in erc20_tokens:
        token_addr = Web3.to_checksum_address(token_info["address"])
        token = w3.eth.contract(address=token_addr, abi=ERC20_ABI)

        try:
            balance = token.functions.balanceOf(agent_safe_addr).call()
        except Exception as e:
            print(f"  WARNING: Failed to check balance for {token_info['symbol']} ({token_addr}): {e}")
            continue

        if balance > 0:
            decimals = token_info["decimals"]
            human_balance = balance / (10 ** decimals)
            print(f"  {token_info['symbol']}: {human_balance} ({balance} wei)")

            transfer_data = "0x" + encode_function_data(token.functions.transfer(master_safe_addr, balance)).hex()
            transfers.append({
                "to": token_addr,
                "value": 0,
                "data": transfer_data,
                "operation": CALL,
            })
            recovered_summary.append(f"  {token_info['symbol']}: {human_balance}")

    # Check native balance
    native_balance = w3.eth.get_balance(agent_safe_addr)
    if native_balance > 0:
        human_native = native_balance / (10 ** 18)
        print(f"  Native token: {human_native} ({native_balance} wei)")

        # Transfer native tokens: send to Master Safe with empty data
        transfers.append({
            "to": master_safe_addr,
            "value": native_balance,
            "data": b"",
            "operation": CALL,
        })
        recovered_summary.append(f"  Native: {human_native}")

    if not transfers:
        print("No tokens with non-zero balance found in Agent Safe. Nothing to recover.")
        sys.exit(0)

    # Build the Agent Safe multicall
    print(f"\nBuilding multicall with {len(transfers)} transfer(s)...")

    multisend_packed = encode_multisend_txs(transfers)
    multisend_data_bytes = encode_function_data(multisend.functions.multiSend(multisend_packed))

    # Build Agent Safe execTransaction calldata
    # Master Safe is sole owner and will be msg.sender, so v=1 signature is valid
    agent_safe_signature = build_safe_signature_for_approved_owner(master_safe_addr)

    agent_exec_data_bytes = encode_function_data(agent_safe.functions.execTransaction(
        multisend_addr,       # to: MultiSend
        0,                    # value
        multisend_data_bytes, # data
        DELEGATECALL,         # operation
        0, 0, 0,              # safeTxGas, baseGas, gasPrice
        ZERO_ADDRESS,         # gasToken
        ZERO_ADDRESS,         # refundReceiver
        agent_safe_signature, # signatures (v=1 for Master Safe as sender)
    ))

    # Master EOA -> Master Safe -> Agent Safe.execTransaction(...)
    print("Executing fund recovery transaction...")
    if impersonate_mode:
        receipt = exec_safe_tx_impersonated(
            w3, master_safe, master_eoa_address,
            to=agent_safe_addr, value=0, data=agent_exec_data_bytes, operation=CALL,
        )
    else:
        receipt = exec_safe_tx(
            w3, master_safe, account,
            to=agent_safe_addr, value=0, data=agent_exec_data_bytes, operation=CALL,
        )

    if receipt.status != 1:
        print(f"ERROR: Fund recovery transaction failed. Receipt status: {receipt.status}")
        print(f"  Tx hash: {receipt.transactionHash.hex()}")
        sys.exit(1)

    # --- Step 10: Verify & Report ---
    print(f"\nTransaction successful: {receipt.transactionHash.hex()}")
    print("\n--- Verification ---")

    all_clear = True
    for token_info in erc20_tokens:
        token_addr = Web3.to_checksum_address(token_info["address"])
        token = w3.eth.contract(address=token_addr, abi=ERC20_ABI)
        try:
            remaining = token.functions.balanceOf(agent_safe_addr).call()
            if remaining > 0:
                print(f"  WARNING: {token_info['symbol']} still has balance: {remaining}")
                all_clear = False
        except Exception:
            pass

    remaining_native = w3.eth.get_balance(agent_safe_addr)
    if remaining_native > 0:
        print(f"  Note: Native token remaining: {remaining_native / 10**18} (expected small amount for gas)")

    print("\n--- Recovery Summary ---")
    print(f"Recovered from Agent Safe ({agent_safe_addr}) to Master Safe ({master_safe_addr}):")
    for line in recovered_summary:
        print(line)

    if all_clear:
        print("\nAll ERC20 funds recovered successfully.")
    else:
        print("\nWARNING: Some tokens may not have been fully recovered. Check balances.")


if __name__ == "__main__":
    main()
