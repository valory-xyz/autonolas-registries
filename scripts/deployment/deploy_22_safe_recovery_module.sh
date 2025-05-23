#!/bin/bash

# Read variables using jq
useLedger=$(jq -r '.useLedger' globals.json)
derivationPath=$(jq -r '.derivationPath' globals.json)
gasPriceInGwei=$(jq -r '.gasPriceInGwei' globals.json)
chainId=$(jq -r '.chainId' globals.json)
networkURL=$(jq -r '.networkURL' globals.json)

multiSendCallOnlyAddress=$(jq -r '.multiSendCallOnlyAddress' globals.json)
serviceRegistryAddress=$(jq -r '.serviceRegistryAddress' globals.json)

execCmd="forge create --broadcast --rpc-url $networkURL$ALCHEMY_API_KEY_MAINNET"
contractPath="contracts/multisigs/RecoveryModule.sol:RecoveryModule"
contractArgs="$contractPath --constructor-args $multiSendCallOnlyAddress $serviceRegistryAddress"

# Conditional logic (correct syntax)
if [ "$useLedger" == "true" ]; then
  execCmd="$execCmd --mnemonic-derivation-path $derivationPath $contractArgs"
else
  echo "Using PRIVATE_KEY: ${PRIVATE_KEY:0:6}..."
  execCmd="$execCmd --private-key $PRIVATE_KEY $contractArgs"
fi

# Deployment message
echo "Deployment of: $contractArgs"

# Deploy the contract and capture the address
deploymentOutput=$($execCmd)
recoveryModuleAddress=$(echo "$deploymentOutput" | grep 'Deployed to:' | awk '{print $3}')

returnedLength=${#recoveryModuleAddress}

if [ $returnedLength == 0 ]; then
  echo "!!! The contract was not deployed, aborting..."
  exit 0
fi

# Write new deployed contract back into JSON
echo "$(jq '. += {"recoveryModuleAddress":"'$recoveryModuleAddress'"}' globals.json)" > globals.json

# Verify contract
forge verify-contract \
    --chain-id "$chainId" \
    --etherscan-api-key "$ETHERSCAN_API_KEY" \
    "$recoveryModuleAddress" \
    "$contractPath" \
    --constructor-args $(cast abi-encode "constructor(address,address)" "$multiSendCallOnlyAddress" "$serviceRegistryAddress")

echo "Recovery Module deployed at address: $recoveryModuleAddress"