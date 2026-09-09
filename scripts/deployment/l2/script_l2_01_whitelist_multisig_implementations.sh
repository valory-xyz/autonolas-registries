#!/bin/bash

# Check if $1 is provided
if [ -z "$1" ]; then
  echo "Usage: $0 <network>"
  echo "Example: $0 eth_mainnet"
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

serviceRegistryAddress=$(jq -r '.serviceRegistryAddress' $globals)
safeMultisigWithRecoveryModuleAddress=$(jq -r '.safeMultisigWithRecoveryModuleAddress' $globals)
recoveryModuleAddress=$(jq -r '.recoveryModuleAddress' $globals)
gnosisSafeMultisigImplementationAddress=$(jq -r '.gnosisSafeMultisigImplementationAddress' $globals)
gnosisSafeSameAddressMultisigImplementationAddress=$(jq -r '.gnosisSafeSameAddressMultisigImplementationAddress' $globals)

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

castSendHeader="cast send --rpc-url $networkURL$API_KEY $walletArgs"

echo "${green}Whitelist SafeMultisigWithRecoveryModule${reset}"
castArgs="$serviceRegistryAddress changeMultisigPermission(address,bool) $safeMultisigWithRecoveryModuleAddress true"
echo $castArgs
castCmd="$castSendHeader $castArgs"
result=$($castCmd)
statusLine=$(echo "$result" | grep -E "^status[[:space:]]+[0-9]")
echo "$statusLine"
if ! echo "$statusLine" | grep -qE "^status[[:space:]]+1[[:space:]]"; then
  echo "${red}!!! changeMultisigPermission transaction did not succeed${reset}"
  exit 1
fi

echo "${green}Whitelist RecoveryModule${reset}"
castArgs="$serviceRegistryAddress changeMultisigPermission(address,bool) $recoveryModuleAddress true"
echo $castArgs
castCmd="$castSendHeader $castArgs"
result=$($castCmd)
statusLine=$(echo "$result" | grep -E "^status[[:space:]]+[0-9]")
echo "$statusLine"
if ! echo "$statusLine" | grep -qE "^status[[:space:]]+1[[:space:]]"; then
  echo "${red}!!! changeMultisigPermission transaction did not succeed${reset}"
  exit 1
fi

# The two Gnosis Safe multisig implementations. These were previously whitelisted only by the hardhat
# deploy_07_10_change_managers_and_permissions.js, so a chain brought up via the shell route alone ended up
# with them deployed but not permitted, and ServiceRegistry.deploy() would revert UnauthorizedMultisig for
# any service trying to use them.
echo "${green}Whitelist GnosisSafeMultisig${reset}"
castArgs="$serviceRegistryAddress changeMultisigPermission(address,bool) $gnosisSafeMultisigImplementationAddress true"
echo $castArgs
castCmd="$castSendHeader $castArgs"
result=$($castCmd)
statusLine=$(echo "$result" | grep -E "^status[[:space:]]+[0-9]")
echo "$statusLine"
if ! echo "$statusLine" | grep -qE "^status[[:space:]]+1[[:space:]]"; then
  echo "${red}!!! changeMultisigPermission transaction did not succeed${reset}"
  exit 1
fi

echo "${green}Whitelist GnosisSafeSameAddressMultisig${reset}"
castArgs="$serviceRegistryAddress changeMultisigPermission(address,bool) $gnosisSafeSameAddressMultisigImplementationAddress true"
echo $castArgs
castCmd="$castSendHeader $castArgs"
result=$($castCmd)
statusLine=$(echo "$result" | grep -E "^status[[:space:]]+[0-9]")
echo "$statusLine"
if ! echo "$statusLine" | grep -qE "^status[[:space:]]+1[[:space:]]"; then
  echo "${red}!!! changeMultisigPermission transaction did not succeed${reset}"
  exit 1
fi
