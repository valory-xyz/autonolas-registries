#!/bin/bash

# Read variables using jq
contractVerification=$(jq -r '.contractVerification' globals.json)
useLedger=$(jq -r '.useLedger' globals.json)
derivationPath=$(jq -r '.derivationPath' globals.json)
gasPriceInGwei=$(jq -r '.gasPriceInGwei' globals.json)
chainId=$(jq -r '.chainId' globals.json)
networkURL=$(jq -r '.networkURL' globals.json)

serviceRegistryAddress=$(jq -r '.serviceRegistryAddress' globals.json)

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

contractPath="contracts/utils/ComplementaryServiceMetadata.sol:ComplementaryServiceMetadata"
constructorArgs="$serviceRegistryAddress"
contractArgs="$contractPath --constructor-args $constructorArgs"

# Get deployer based on the ledger flag
if [ "$useLedger" == "true" ]; then
  walletArgs="-l --mnemonic-derivation-path $derivationPath"
  deployer=$(cast wallet address $walletArgs)
else
  echo "Using PRIVATE_KEY: ${PRIVATE_KEY:0:6}..."
  walletArgs="--private-key $PRIVATE_KEY"
  deployer=$(cast wallet address $walletArgs)
fi

# Deployment message
echo "Deploying from: $deployer"
echo "Deployment of: $contractArgs"

# Deploy the contract and capture the address
execCmd="forge create --broadcast --rpc-url $networkURL$API_KEY $walletArgs $contractArgs"
deploymentOutput=$($execCmd)
complementaryServiceMetadataAddress=$(echo "$deploymentOutput" | grep 'Deployed to:' | awk '{print $3}')

# Get output length
outputLength=${#complementaryServiceMetadataAddress}

# Check for the deployed address
if [ $outputLength != 42 ]; then
  echo "!!! The contract was not deployed, aborting..."
  exit 0
fi

# Write new deployed contract back into JSON
echo "$(jq '. += {"complementaryServiceMetadataAddress":"'$complementaryServiceMetadataAddress'"}' globals.json)" > globals.json

# Verify contract
if [ "$contractVerification" == "true" ]; then
  echo "Verifying contract..."
  forge verify-contract \
    --chain-id "$chainId" \
    --etherscan-api-key "$ETHERSCAN_API_KEY" \
    "$complementaryServiceMetadataAddress" \
    "$contractPath" \
    --constructor-args $(cast abi-encode "constructor(address)" $constructorArgs)
fi

echo "Contract deployed at: $complementaryServiceMetadataAddress"