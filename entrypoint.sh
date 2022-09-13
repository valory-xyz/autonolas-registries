#!/bin/bash

echo "Using SERVICE_CONFIG_HASH = $SERVICE_CONFIG_HASH"
jq '.serviceRegistry.configHashes = "$SERVICE_CONFIG_HASH"' snapshot.json > snapshot.json
yarn hardhat node