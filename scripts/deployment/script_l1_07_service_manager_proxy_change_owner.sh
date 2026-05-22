#!/bin/bash

# Transfers ServiceManagerProxy ownership from the deployer EOA to the protocol
# Timelock on Ethereum mainnet, by calling changeOwner(timelock).
#
# The script is idempotent: it pre-checks that the signer derived from
# $derivationPath is the current proxy owner (otherwise changeOwner reverts with
# OwnerOnly), and is a no-op if the proxy is already owned by the target.

# Check if $1 is provided
if [ -z "$1" ]; then
  echo "Usage: $0 <network>"
  echo "Example: $0 mainnet"
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
timelockAddress=$(jq -r '.timelockAddress' $globals)

# New owner: bridge mediator on L2, Timelock on L1 mainnet.
if [ "$bridgeMediatorAddress" != "null" ] && [ -n "$bridgeMediatorAddress" ]; then
  newOwnerAddress="$bridgeMediatorAddress"
elif [ "$timelockAddress" != "null" ] && [ -n "$timelockAddress" ]; then
  newOwnerAddress="$timelockAddress"
else
  echo "${red}!!! Neither bridgeMediatorAddress nor timelockAddress is set in $globals${reset}"
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

# Pre-flight: current owner must equal the signer; otherwise changeOwner reverts.
currentOwner=$(cast call --rpc-url $networkURL$API_KEY $serviceManagerProxyAddress "owner()(address)")
if [ "${currentOwner,,}" != "${deployer,,}" ]; then
  echo "${red}!!! Signer $deployer is not the current ServiceManagerProxy owner ($currentOwner).${reset}"
  echo "${red}    Set derivationPath in $globals to the path that controls $currentOwner, then re-run.${reset}"
  exit 1
fi

# No-op if already owned by the target
if [ "${currentOwner,,}" == "${newOwnerAddress,,}" ]; then
  echo "${green}ServiceManagerProxy $serviceManagerProxyAddress is already owned by $newOwnerAddress. Nothing to do.${reset}"
  exit 0
fi

castSendHeader="cast send --rpc-url $networkURL$API_KEY $walletArgs"

echo "${green}Change ServiceManagerProxy owner: $currentOwner -> $newOwnerAddress${reset}"
castArgs="$serviceManagerProxyAddress changeOwner(address) $newOwnerAddress"
echo $castArgs
castCmd="$castSendHeader $castArgs"
result=$($castCmd)
echo "$result" | grep "status"
