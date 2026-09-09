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

identityRegistryAddress=$(jq -r '.identityRegistryAddress' $globals)
serviceRegistryAddress=$(jq -r '.serviceRegistryAddress' $globals)

# Preflight: IdentityRegistryBridger sets its serviceManager as an immutable in the constructor, reading
# it from IServiceRegistry(serviceRegistry).manager(). Deploying before the manager is set bakes in a
# permanent address(0): there is no setter, and an immutable lives in the implementation runtime code, so
# even a proxy cannot override it - the only repair is a redeploy. Run
# script_l2_02_change_managers_registries.sh first.
serviceRegistryManager=$(cast call --rpc-url $networkURL$API_KEY $serviceRegistryAddress "manager()(address)")
if [ ${#serviceRegistryManager} != 42 ]; then
  echo "!!! Could not read manager() from ServiceRegistry $serviceRegistryAddress - aborting"
  exit 1
fi
if [ "$serviceRegistryManager" == "$(cast address-zero)" ]; then
  echo "!!! ServiceRegistry $serviceRegistryAddress has no manager set."
  echo "!!! IdentityRegistryBridger would capture address(0) as its immutable serviceManager, permanently."
  echo "!!! Run script_l2_02_change_managers_registries.sh first, then re-run this script."
  exit 1
fi
echo "Preflight OK: ServiceRegistry manager() = $serviceRegistryManager"

contractName="IdentityRegistryBridger"
contractPath="contracts/8004/$contractName.sol:$contractName"
constructorArgs="$identityRegistryAddress $serviceRegistryAddress"
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
identityRegistryBridgerAddress=$(echo "$deploymentOutput" | grep 'Deployed to:' | awk '{print $3}')

# Get output length
outputLength=${#identityRegistryBridgerAddress}

# Check for the deployed address
if [ $outputLength != 42 ]; then
  echo "!!! The contract was not deployed, aborting..."
  exit 0
fi

# Write new deployed contract back into JSON
echo "$(jq '. += {"identityRegistryBridgerAddress":"'$identityRegistryBridgerAddress'"}' $globals)" > $globals

# Verify contract
if [ "$contractVerification" == "true" ]; then
  contractParams="$identityRegistryBridgerAddress $contractPath --constructor-args $(cast abi-encode "constructor(address,address)" $constructorArgs)"
  echo "Verification contract params: $contractParams"

  echo "Verifying contract on Etherscan..."
  forge verify-contract --chain-id "$chainId" --etherscan-api-key "$ETHERSCAN_API_KEY" $contractParams

  blockscoutURL=$(jq -r '.blockscoutURL' $globals)
  if [ "$blockscoutURL" != "null" ]; then
    echo "Verifying contract on Blockscout..."
    forge verify-contract --verifier blockscout --verifier-url "$blockscoutURL/api" $contractParams
  fi
fi

echo "$contractName deployed at: $identityRegistryBridgerAddress"