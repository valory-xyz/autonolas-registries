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

serviceRegistryName=$(jq -r '.serviceRegistryName' $globals)
serviceRegistrySymbol=$(jq -r '.serviceRegistrySymbol' $globals)
baseURI=$(jq -r '.baseURI' $globals)

contractName="ServiceRegistryL2"
contractPath="contracts/$contractName.sol:$contractName"
constructorArgs="$serviceRegistryName $serviceRegistrySymbol $baseURI"
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

# Deploy the contract and capture the address.
# The constructor args are passed as separate quoted words rather than through a single
# $execCmd string: serviceRegistryName is "Service Registry L2", and a string-built command
# re-split on expansion would pass it as three arguments, so the five resulting words
# "Service|Registry|L2|AUTONOLAS-SERVICE-L2-V1|https://gateway.autonolas.tech/ipfs/" reach a
# three-string constructor. forge consumes the first three and silently DROPS the surplus - it
# does not reject the count - which is how the abandoned 0x9338b515 got name()="Service",
# symbol()="Registry", baseURI()="L2". Confirmed against forge 1.5.1 on anvil.
deploymentOutput=$(forge create --broadcast --rpc-url "$networkURL$API_KEY" $walletArgs \
  "$contractPath" --constructor-args "$serviceRegistryName" "$serviceRegistrySymbol" "$baseURI")
serviceRegistryAddress=$(echo "$deploymentOutput" | grep 'Deployed to:' | awk '{print $3}')

# Get output length
outputLength=${#serviceRegistryAddress}

# Check for the deployed address
if [ $outputLength != 42 ]; then
  echo "!!! The contract was not deployed, aborting..."
  exit 0
fi

# Write new deployed contract back into JSON
echo "$(jq '. += {"serviceRegistryAddress":"'$serviceRegistryAddress'"}' $globals)" > $globals

# Verify contract
if [ "$contractVerification" == "true" ]; then
  contractParams="$serviceRegistryAddress $contractPath --constructor-args $(cast abi-encode "constructor(string,string,string)" "$serviceRegistryName" "$serviceRegistrySymbol" "$baseURI")"
  echo "Verification contract params: $contractParams"

  echo "Verifying contract on Etherscan..."
  forge verify-contract --chain-id "$chainId" --etherscan-api-key "$ETHERSCAN_API_KEY" $contractParams

  blockscoutURL=$(jq -r '.blockscoutURL' $globals)
  if [ "$blockscoutURL" != "null" ]; then
    echo "Verifying contract on Blockscout..."
    forge verify-contract --verifier blockscout --verifier-url "$blockscoutURL/api" $contractParams
  fi
fi

echo "$contractName deployed at: $serviceRegistryAddress"