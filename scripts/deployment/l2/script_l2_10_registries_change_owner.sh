#!/bin/bash

# Transfers ownership of both service registries from the deployer EOA to the chain's governance control point, by calling changeOwner(bridgeMediator).
#
# Covers ServiceRegistryL2 and ServiceRegistryTokenUtility, the two contracts the
# shell deployment route never had a script for: they are reachable only through
# the hardhat deploy_13_15_change_ownerships.js, so on a shell-route chain the call had to be
# made by hand with cast send. That is how it was done on chain 4663.
#
# The script is idempotent per contract: it skips one already set to the target,
# and otherwise pre-checks that the signer derived from $derivationPath is the
# current owner (both setters are owner-gated and would revert with OwnerOnly).
#
# Run this AFTER script_l2_09 and after every other owner-gated setup call: once
# owner() is the bridge mediator, any further configuration becomes a governance
# proposal crossing the bridge. This is steps 13-14 of docs/deploymentL2.md; step 15, the ServiceManagerToken
# transfer, is script_l2_07_service_manager_proxy_change_owner.sh.

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
  exit 1
fi

# Read variables using jq
useLedger=$(jq -r '.useLedger' $globals)
derivationPath=$(jq -r '.derivationPath' $globals)
chainId=$(jq -r '.chainId' $globals)
networkURL=$(jq -r '.networkURL' $globals)

serviceRegistryAddress=$(jq -r '.serviceRegistryAddress' $globals)
serviceRegistryTokenUtilityAddress=$(jq -r '.serviceRegistryTokenUtilityAddress' $globals)
bridgeMediatorAddress=$(jq -r '.bridgeMediatorAddress' $globals)

# Target: the chain's governance control point — the bridge mediator on L2, or the
# L1-aliased Timelock on Arbitrum — stored as bridgeMediatorAddress. Required, with
# no fallback: timelockAddress is the non-aliased L1 Timelock, an address nobody
# controls on an L2.
if [ "$bridgeMediatorAddress" == "null" ] || [ -z "$bridgeMediatorAddress" ]; then
  echo "${red}!!! bridgeMediatorAddress is not set in $globals${reset}"
  exit 1
fi
targetAddress="$bridgeMediatorAddress"

if [ "$targetAddress" == "0x0000000000000000000000000000000000000000" ]; then
  echo "${red}!!! targetAddress is the zero address — check $globals${reset}"
  exit 1
fi

# Shape-check every address taken from globals, not just null/empty. jq -r preserves a stray
# trailing space, which passes a null/empty/zero test and then silently defeats every string
# comparison below: the idempotency branch can never match, while castCmd re-splits on expansion
# so the transaction itself is correct. A completed handover would then be reported as a hard
# failure telling the operator to find a derivation path for the bridge mediator.
for pair in "bridgeMediatorAddress:$targetAddress" \
            "serviceRegistryAddress:$serviceRegistryAddress" \
            "serviceRegistryTokenUtilityAddress:$serviceRegistryTokenUtilityAddress"; do
  key="${pair%%:*}"; val="${pair#*:}"
  if [ "$val" == "null" ] || [ -z "$val" ]; then
    echo "${red}!!! $key is not set in $globals${reset}"
    exit 1
  fi
  if ! [[ "$val" =~ ^0x[0-9a-fA-F]{40}$ ]]; then
    echo "${red}!!! $key in $globals is not a well-formed address: '$val'${reset}"
    exit 1
  fi
done

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
    exit 1
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

# cast wallet address fails silently into an empty string when the ledger is not
# connected. Without this the run continues with an empty signer and only fails
# later, at the owner comparison, with a misleading message.
if ! [[ "$deployer" =~ ^0x[0-9a-fA-F]{40}$ ]]; then
  echo "${red}!!! Failed to derive the signer address (is the ledger connected and unlocked?)${reset}"
  exit 1
fi
deployerLc=$(echo "$deployer" | tr '[:upper:]' '[:lower:]')
targetLc=$(echo "$targetAddress" | tr '[:upper:]' '[:lower:]')

echo "${green}Casting from: $deployer${reset}"
echo "RPC: $networkURL"

castSendHeader="cast send --rpc-url $networkURL$API_KEY $walletArgs"

for pair in "ServiceRegistryL2:$serviceRegistryAddress" \
            "ServiceRegistryTokenUtility:$serviceRegistryTokenUtilityAddress"; do
  name="${pair%%:*}"; addr="${pair#*:}"

  # Addresses are lowercased before comparison because the globals JSON may not be
  # EIP-55 checksummed; tr is used instead of the ${var,,} expansion so the script
  # also runs on bash 3.2 (macOS default).
  current=$(cast call --rpc-url $networkURL$API_KEY $addr "owner()(address)")
  if ! [[ "$current" =~ ^0x[0-9a-fA-F]{40}$ ]]; then
    echo "${red}!!! Failed to read $name owner() (got: $current)${reset}"
    exit 1
  fi
  currentLc=$(echo "$current" | tr '[:upper:]' '[:lower:]')

  if [ "$currentLc" == "$targetLc" ]; then
    echo "${green}$name $addr already has owner() == $targetAddress. Nothing to do.${reset}"
    continue
  fi

  # Enforce the ordering the header states, rather than only documenting it. Handing ownership over
  # while drainer() is unset permanently closes both sweep paths from the EOA:
  # ServiceRegistryL2.drain() requires msg.sender == drainer, and
  # ServiceRegistryTokenUtility.drain(token) reverts ZeroAddress(). Running _09 afterwards correctly
  # fails OwnerOnly, by which point restoring the sweep needs a governance proposal over the bridge.
  currentDrainer=$(cast call --rpc-url $networkURL$API_KEY $addr "drainer()(address)")
  if ! [[ "$currentDrainer" =~ ^0x[0-9a-fA-F]{40}$ ]]; then
    echo "${red}!!! Failed to read $name drainer() (got: $currentDrainer)${reset}"
    exit 1
  fi
  if [ "$(echo "$currentDrainer" | tr '[:upper:]' '[:lower:]')" == "0x0000000000000000000000000000000000000000" ]; then
    echo "${red}!!! $name drainer() is still unset. Run script_l2_09_registries_change_drainer.sh first${reset}"
    echo "${red}    — after this handover, setting it needs a governance proposal over the bridge.${reset}"
    exit 1
  fi

  # The signer must be the current owner; otherwise changeOwner reverts with OwnerOnly. $current was
  # already read and shape-checked above, so it is reused rather than re-read: a second call is a
  # second chance for a transient RPC error to produce a misleading "signer is not the owner ()".
  if [ "$currentLc" != "$deployerLc" ]; then
    echo "${red}!!! Signer $deployer is not the current $name owner ($current).${reset}"
    echo "${red}    Set derivationPath in $globals to the path that controls $current, then re-run.${reset}"
    exit 1
  fi

  echo "${green}$name changeOwner: $current -> $targetAddress${reset}"
  castArgs="$addr changeOwner(address) $targetAddress"
  echo $castArgs
  castCmd="$castSendHeader $castArgs"
  result=$($castCmd)
  statusLine=$(echo "$result" | grep -E "^status[[:space:]]+[0-9]")
  echo "$statusLine"
  if ! echo "$statusLine" | grep -qE "^status[[:space:]]+1[[:space:]]"; then
    echo "${red}!!! $name changeOwner transaction did not succeed${reset}"
    exit 1
  fi
  echo "${green}$name owner() set to $targetAddress.${reset}"
done
