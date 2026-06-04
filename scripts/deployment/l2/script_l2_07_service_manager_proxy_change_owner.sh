#!/bin/bash

# Transfers ServiceManagerProxy ownership from the deployer EOA to the chain's
# governance control point, by calling changeOwner(bridgeMediator). On L2 this
# is the bridge mediator; on Arbitrum it is the L1-aliased Timelock — both are
# stored as bridgeMediatorAddress in the per-network globals.
#
# The script is idempotent: it is a no-op if the proxy is already owned by the
# target, and otherwise pre-checks that the signer derived from $derivationPath
# is the current proxy owner (changeOwner would revert with OwnerOnly otherwise).

# Check if $1 is provided
if [ -z "$1" ]; then
  echo "Usage: $0 <network>"
  echo "Example: $0 gnosis_mainnet"
  exit 1
fi

red=$(tput setaf 1)
green=$(tput setaf 2)
reset=$(tput sgr0)

# Get globals file
globals="$(dirname "$0")/globals_$1.json"
if [ ! -f $globals ]; then
  echo "${red}!!! $globals is not found${reset}"
  exit 0
fi

# Read variables using jq
useLedger=$(jq -r '.useLedger' $globals)
derivationPath=$(jq -r '.derivationPath' $globals)
chainId=$(jq -r '.chainId' $globals)
networkURL=$(jq -r '.networkURL' $globals)

serviceManagerProxyAddress=$(jq -r '.serviceManagerProxyAddress' $globals)
bridgeMediatorAddress=$(jq -r '.bridgeMediatorAddress' $globals)

# New owner: the chain's governance control point — the bridge mediator on L2,
# or the L1-aliased Timelock on Arbitrum — stored as bridgeMediatorAddress. It
# is required and has no fallback: timelockAddress is the non-aliased L1
# Timelock, an address nobody controls on an L2.
if [ "$bridgeMediatorAddress" == "null" ] || [ -z "$bridgeMediatorAddress" ]; then
  echo "${red}!!! bridgeMediatorAddress is not set in $globals${reset}"
  exit 1
fi
newOwnerAddress="$bridgeMediatorAddress"

if [ "$newOwnerAddress" == "0x0000000000000000000000000000000000000000" ]; then
  echo "${red}!!! newOwnerAddress is the zero address — check $globals${reset}"
  exit 1
fi

if [ "$serviceManagerProxyAddress" == "null" ] || [ -z "$serviceManagerProxyAddress" ]; then
  echo "${red}!!! serviceManagerProxyAddress is not set in $globals${reset}"
  exit 1
fi

# Check for Alchemy keys
if [[ "$networkURL" == *"alchemy.com"* ]]; then
  case $chainId in
    1)        API_KEY=$ALCHEMY_API_KEY_MAINNET; keyName="ALCHEMY_API_KEY_MAINNET" ;;
    11155111) API_KEY=$ALCHEMY_API_KEY_SEPOLIA; keyName="ALCHEMY_API_KEY_SEPOLIA" ;;
    137)      API_KEY=$ALCHEMY_API_KEY_MATIC;   keyName="ALCHEMY_API_KEY_MATIC" ;;
    80002)    API_KEY=$ALCHEMY_API_KEY_AMOY;    keyName="ALCHEMY_API_KEY_AMOY" ;;
  esac
  if [ -n "$keyName" ] && [ "$API_KEY" == "" ]; then
    echo "set $keyName env variable"
    exit 0
  fi
fi

# Get deployer based on the ledger flag
if [ "$useLedger" == "true" ]; then
  walletArgs="-l --mnemonic-derivation-path $derivationPath"
  deployer=$(cast wallet address $walletArgs)
else
  echo "Using PRIVATE_KEY: ${PRIVATE_KEY:0:6}..."
  walletArgs="--private-key $PRIVATE_KEY"
  deployer=$(cast wallet address $walletArgs)
fi

# Pre-flight: read the current owner. Addresses are lowercased before comparison
# because the globals JSON may not be EIP-55 checksummed; tr is used instead of
# the ${var,,} expansion so the script also runs on bash 3.2 (macOS default).
currentOwner=$(cast call --rpc-url $networkURL$API_KEY $serviceManagerProxyAddress "owner()(address)")
if ! [[ "$currentOwner" =~ ^0x[0-9a-fA-F]{40}$ ]]; then
  echo "${red}!!! Failed to read the current ServiceManagerProxy owner (got: $currentOwner)${reset}"
  exit 1
fi
currentOwnerLc=$(echo "$currentOwner" | tr '[:upper:]' '[:lower:]')
deployerLc=$(echo "$deployer" | tr '[:upper:]' '[:lower:]')
newOwnerLc=$(echo "$newOwnerAddress" | tr '[:upper:]' '[:lower:]')

# No-op if already owned by the target.
if [ "$currentOwnerLc" == "$newOwnerLc" ]; then
  echo "${green}ServiceManagerProxy $serviceManagerProxyAddress is already owned by $newOwnerAddress. Nothing to do.${reset}"
  exit 0
fi

# The signer must be the current owner; otherwise changeOwner reverts with OwnerOnly.
if [ "$currentOwnerLc" != "$deployerLc" ]; then
  echo "${red}!!! Signer $deployer is not the current ServiceManagerProxy owner ($currentOwner).${reset}"
  echo "${red}    Set derivationPath in $globals to the path that controls $currentOwner, then re-run.${reset}"
  exit 1
fi

castSendHeader="cast send --rpc-url $networkURL$API_KEY $walletArgs"

echo "${green}Change ServiceManagerProxy owner: $currentOwner -> $newOwnerAddress${reset}"
castArgs="$serviceManagerProxyAddress changeOwner(address) $newOwnerAddress"
echo $castArgs
castCmd="$castSendHeader $castArgs"
result=$($castCmd)
statusLine=$(echo "$result" | grep -E "^status[[:space:]]+[0-9]")
echo "$statusLine"
if ! echo "$statusLine" | grep -qE "^status[[:space:]]+1[[:space:]]"; then
  echo "${red}!!! changeOwner transaction did not succeed${reset}"
  exit 1
fi
echo "${green}ServiceManagerProxy owner changed to $newOwnerAddress.${reset}"
