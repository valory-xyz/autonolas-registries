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
serviceManagerProxyAddress=$(jq -r '.serviceManagerProxyAddress' $globals)
identityRegistryBridgerProxyAddress=$(jq -r '.identityRegistryBridgerProxyAddress' $globals)

# Getting L1 API key
if [ $chainId == 1 ]; then
  API_KEY=$ALCHEMY_API_KEY_MAINNET
  if [ "$API_KEY" == "" ]; then
      echo "set ALCHEMY_API_KEY_MAINNET env variable"
      exit 0
  fi
elif [ $chainId == 11155111 ]; then
    API_KEY=$ALCHEMY_API_KEY_SEPOLIA
    if [ "$API_KEY" == "" ]; then
        echo "set ALCHEMY_API_KEY_SEPOLIA env variable"
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

# Cast message
echo "Casting from: $deployer"

echo "${green}VIEW FUNCTIONS EXECUTION${reset}"
castSendHeader="cast call --rpc-url $networkURL$API_KEY $walletArgs"

echo "${green}Get ServiceRegistry totalSupply${reset}"
castArgs="$serviceRegistryAddress totalSupply()(uint256)"
echo $castArgs
castCmd="$castSendHeader $castArgs"
result=$($castCmd)
echo "$result"

maxNumServicesPerTx=40
numIter=$((result / maxNumServicesPerTx + 1))
echo "Number of link steps: $numIter"


echo "${green}WRITE FUNCTIONS EXECUTION${reset}"
castSendHeader="cast send --rpc-url $networkURL$API_KEY $walletArgs"

echo "${green}Pause ServiceManager${reset}"
castArgs="$serviceManagerProxyAddress pause()"
echo $castArgs
castCmd="$castSendHeader $castArgs"
result=$($castCmd)
echo "$result" | grep "status"

# Link service Ids and 8004 agent Ids
for (( i=0; i < $numIter; i++ )); do
  echo "${green}Linking step $i${reset}"
  castArgs="$identityRegistryBridgerProxyAddress linkServiceIdAgentIds(uint256) 40"
  echo $castArgs
  castCmd="$castSendHeader $castArgs"
  result=$($castCmd)
  echo "$result" | grep "status"
done

echo "${green}Set identity registry bridger for ServiceManager${reset}"
castArgs="$serviceManagerProxyAddress setIdentityRegistryBridger(address) $identityRegistryBridgerProxyAddress"
echo $castArgs
castCmd="$castSendHeader $castArgs"
result=$($castCmd)
echo "$result" | grep "status"

echo "${green}Unpause ServiceManager${reset}"
castArgs="$serviceManagerProxyAddress unpause()"
echo $castArgs
castCmd="$castSendHeader $castArgs"
result=$($castCmd)
echo "$result" | grep "status"
