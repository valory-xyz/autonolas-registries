#!/bin/bash

if [[ -n "$SERVICE_CONFIG_HASH" ]]; then
  echo "Using SERVICE_CONFIG_HASH = $SERVICE_CONFIG_HASH"
  echo $(jq --arg SERVICE_CONFIG_HASH "$SERVICE_CONFIG_HASH" '.serviceRegistry.configHashes = [ $SERVICE_CONFIG_HASH ]' snapshot.json) > snapshot.json
fi

yarn hardhat node
