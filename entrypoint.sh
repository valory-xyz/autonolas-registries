#!/bin/bash

echo "Using SERVICE_CONFIG_HASH = $SERVICE_CONFIG_HASH"
echo $(jq --arg SERVICE_CONFIG_HASH "$SERVICE_CONFIG_HASH" '.serviceRegistry.configHashes = [ $SERVICE_CONFIG_HASH ]' snapshot.json) > snapshot.json
yarn hardhat node
