#!/bin/bash

# Read variables using jq
useLedger=$(jq -r '.useLedger' globals.json)
derivationPath=$(jq -r '.derivationPath' globals.json)
providerName=$(jq -r '.providerName' globals.json)
gasPriceInGwei=$(jq -r '.gasPriceInGwei' globals.json)
chainId=$(jq -r '.chainId' globals.json)
networkURL=$(jq -r '.networkURL' globals.json)

multiSendCallOnlyAddress=$(jq -r '.multiSendCallOnlyAddress' globals.json)
serviceRegistryAddress=$(jq -r '.serviceRegistryAddress' globals.json)

ledgerCmd="--mnemonic-derivation-path $derivationPath"
keyCmd="--private-key $PRIVATE_KEY"
execCmd="forge create --broadcast --rpc-url $networkURL$ALCHEMY_API_KEY_MAINNET contracts/multsigs/RecoveryModule.sol:RecoveryModule --constructor-args $multiSendCallOnlyAddress $serviceRegistryAddress"

# Conditional logic (correct syntax)
if [ "$useLedger" == "true" ]; then
  execCmd="$execCmd $ledgerCmd"
else
  execCmd="$execCmd $keyCmd"
fi

# Deploy the contract and capture the address
recoveryModuleAddress=$($execCmd)

# Write new deployed contract back into JSON
jq --argjson recoveryModuleAddress "$recoveryModuleAddress" '.recoveryModuleAddress = $recoveryModuleAddress' globals.json > output.json

# Verify contract
forge verify-contract \
    --chain-id "$chainId" \
    --etherscan-api-key "$ETHERSCAN_API_KEY" \
    "$recoveryModuleAddress" \
    contracts/multsigs/RecoveryModule.sol:RecoveryModule \
    --constructor-args $(cast abi-encode "constructor(address,address)" "$multiSendCallOnlyAddress" "$serviceRegistryAddress")

echo "Recovery Module deployed at address: $recoveryModuleAddress"