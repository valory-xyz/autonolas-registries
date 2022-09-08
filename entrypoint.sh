#!/bin/sh

# Change to the correct directory
cd /usr/src/app;

# Run hardhat
yarn run hardhat node --port 8545

# Keep node alive
set -e
if [ "${1#-}" != "${1}" ] || [ -z "$(command -v "${1}")" ]; then
  set -- node "$@"
fi
exec "$@"
Footer
