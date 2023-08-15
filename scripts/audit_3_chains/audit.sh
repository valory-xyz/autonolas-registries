#!/bin/bash

if ! command -v ethereum-sources-downloader &> /dev/null
then
    echo "ethereum-sources-downloader could not be found"
    npm i ethereum-sources-downloader
fi
rm -rf out
# "serviceManagerAddress":"0x3C1fF68f5aa342D296d4DEe4Bb1cACCA912D95fE"
ethereum-sources-downloader polygonscan 0x3C1fF68f5aa342D296d4DEe4Bb1cACCA912D95fE
r=$(diff -r out/ServiceManager/contracts/ contracts/ | grep -v Only)
if [ -z "$r" ]
then
      echo "OK. serviceManager (0x3C1fF68f5aa342D296d4DEe4Bb1cACCA912D95fE) on polygon eq contracts"
else
      echo "serviceManager (0x3C1fF68f5aa342D296d4DEe4Bb1cACCA912D95fE) on polygon NOT eq contracts"
fi
# "serviceRegistryAddress":"0xE3607b00E75f6405248323A9417ff6b39B244b50"
rm -rf out
ethereum-sources-downloader polygonscan 0xE3607b00E75f6405248323A9417ff6b39B244b50
r=$(diff -r out/ServiceRegistryL2/contracts/ contracts/ | grep -v Only)
if [ -z "$r" ]
then
      echo "OK. serviceRegistryL2 (0xE3607b00E75f6405248323A9417ff6b39B244b50) on polygon eq contracts"
else
      echo "serviceRegistryL2 (0xE3607b00E75f6405248323A9417ff6b39B244b50) on polygon NOT eq contracts"
fi
rm -rf out
