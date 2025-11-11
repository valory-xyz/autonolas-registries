#!/bin/bash

# Get globals file
globals="$(dirname "$0")/globals_$1.json"
if [ ! -f $globals ]; then
  echo "!!! $globals is not found"
  exit 0
fi

# Read variables using jq
contractVerification=$(jq -r '.contractVerification' $globals)
useLedger=$(jq -r '.useLedger' $globals)
derivationPath=$(jq -r '.derivationPath' $globals)
chainId=$(jq -r '.chainId' $globals)
networkURL=$(jq -r '.networkURL' $globals)

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

identityRegistryAddress=$(jq -r '.identityRegistryAddress' $globals)
validationRegistryAddress=$(jq -r '.validationRegistryAddress' $globals)
identityRegistryBridgerProxyAddress=$(jq -r '.identityRegistryBridgerProxyAddress' $globals)

contractName="ERC8004Operator"
contractPath="contracts/8004/$contractName.sol:$contractName"
constructorArgs="$identityRegistryAddress $validationRegistryAddress $identityRegistryBridgerProxyAddress"
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
erc8004OperatorAddress=$(echo "$deploymentOutput" | grep 'Deployed to:' | awk '{print $3}')

# Get output length
outputLength=${#erc8004OperatorAddress}

# Check for the deployed address
if [ $outputLength != 42 ]; then
  echo "!!! The contract was not deployed, aborting..."
  exit 0
fi

# Write new deployed contract back into JSON
echo "$(jq '. += {"erc8004OperatorAddress":"'$erc8004OperatorAddress'"}' $globals)" > $globals

# Verify contract
if [ "$contractVerification" == "true" ]; then
  contractParams="$erc8004OperatorAddress $contractPath --constructor-args $(cast abi-encode "constructor(address,address,address)" $constructorArgs)"
  echo "Verification contract params: $contractParams"

  echo "Verifying contract on Etherscan..."
  forge verify-contract --chain-id "$chainId" --etherscan-api-key "$ETHERSCAN_API_KEY" $contractParams

  blockscoutURL=$(jq -r '.blockscoutURL' $globals)
  if [ "$blockscoutURL" != "null" ]; then
    echo "Verifying contract on Blockscout..."
    forge verify-contract --verifier blockscout --verifier-url "$blockscoutURL/api" $contractParams
  fi
fi

echo "$contractName deployed at: $erc8004OperatorAddress"