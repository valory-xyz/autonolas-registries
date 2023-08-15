#!/bin/bash

# network contract_name contract_address

if ! command -v ethereum-sources-downloader &> /dev/null
then
    # https://github.com/SergeKireev/ethereum-sources-downloader
    echo "ethereum-sources-downloader could not be found"
    npm i ethereum-sources-downloader
fi

# "serviceRegistryAddress":"0xE3607b00E75f6405248323A9417ff6b39B244b50"
rm -rf out

ethereum-sources-downloader polygonscan 0xE3607b00E75f6405248323A9417ff6b39B244b50 2>&1 > /dev/null
r=$(diff -r out/ServiceRegistryL2/contracts/ contracts/ | grep -v Only)
if [ -z "$r" ]
then
      echo "OK. serviceRegistryL2 (0xE3607b00E75f6405248323A9417ff6b39B244b50) on polygon eq contracts"
else
      echo "serviceRegistryL2 (0xE3607b00E75f6405248323A9417ff6b39B244b50) on polygon NOT eq contracts"
fi

rm -rf out
