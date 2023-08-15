#!/bin/bash

if ! command -v ethereum-sources-downloader &> /dev/null
then
    # https://github.com/SergeKireev/ethereum-sources-downloader
    echo "ethereum-sources-downloader could not be found"
    npm i ethereum-sources-downloader
fi

# "serviceManagerAddress":"0x3C1fF68f5aa342D296d4DEe4Bb1cACCA912D95fE"
rm -rf out
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

#"serviceManagerTokenAddress":"0x1d333b46dB6e8FFd271b6C2D2B254868BD9A2dbd"
rm -rf out
ethereum-sources-downloader goerli.etherscan 0x1d333b46dB6e8FFd271b6C2D2B254868BD9A2dbd
r=$(diff -r out/ServiceManagerToken/contracts/ contracts/ | grep -v Only)
if [ -z "$r" ]
then
      echo "OK. ServiceManagerToken (0x1d333b46dB6e8FFd271b6C2D2B254868BD9A2dbd) on goerli eq contracts"
else
      echo "ServiceManagerToken (0x1d333b46dB6e8FFd271b6C2D2B254868BD9A2dbd) on goerli NOT eq contracts"
fi

#"serviceRegistryTokenUtilityAddress":"0x6d9b08701Af43D68D991c074A27E4d90Af7f2276"
rm -rf out
ethereum-sources-downloader goerli.etherscan 0x6d9b08701Af43D68D991c074A27E4d90Af7f2276
r=$(diff -r out/ServiceRegistryTokenUtility/contracts/ contracts/ | grep -v Only)
if [ -z "$r" ]
then
      echo "OK. serviceRegistryTokenUtility (0x6d9b08701Af43D68D991c074A27E4d90Af7f2276) on goerli eq contracts" 
else
      echo "serviceRegistryTokenUtility (0x6d9b08701Af43D68D991c074A27E4d90Af7f2276) on goerli NOT eq contracts"                                           
fi

#"operatorWhitelistAddress":"0x0338893fB1A1D9Df03F72CC53D8f786487d3D03E"
rm -rf out
ethereum-sources-downloader goerli.etherscan 0x0338893fB1A1D9Df03F72CC53D8f786487d3D03E
r=$(diff -r out/OperatorWhitelist/contracts/ contracts/ | grep -v Only)
if [ -z "$r" ]
then
      echo "OK. operatorWhitelist (0x0338893fB1A1D9Df03F72CC53D8f786487d3D03E) on goerli eq contracts"
else
      echo "operatorWhitelist (0x0338893fB1A1D9Df03F72CC53D8f786487d3D03E) on goerli NOT eq contracts"
fi

#"0x65dD51b02049ad1B6FF7fa9Ea3322E1D2CAb1176","gnosisSafeSameAddressMultisigImplementationAddress"
rm -rf out
ethereum-sources-downloader goerli.etherscan 0x65dD51b02049ad1B6FF7fa9Ea3322E1D2CAb1176
r=$(diff -r out/GnosisSafeMultisig/contracts/ contracts/ | grep -v Only)          
if [ -z "$r" ]
then
      echo "OK. gnosisSafeSameAddressMultisigImplementation (0x65dD51b02049ad1B6FF7fa9Ea3322E1D2CAb1176) on goerli eq contracts"          
else
      echo "gnosisSafeSameAddressMultisigImplementation (0x65dD51b02049ad1B6FF7fa9Ea3322E1D2CAb1176) on goerli NOT eq contracts"          
fi

#"componentRegistryAddress":"0x7Fd1F4b764fA41d19fe3f63C85d12bf64d2bbf68",
#"agentRegistryAddress":"0xEB5638eefE289691EcE01943f768EDBF96258a80",
#"registriesManagerAddress":"0x10c5525F77F13b28f42c5626240c001c2D57CAd4",
#"serviceRegistryAddress":"0x1cEe30D08943EB58EFF84DD1AB44a6ee6FEff63a",
#"serviceManagerAddress":"0xcDdD9D9ABaB36fFa882530D69c73FeE5D4001C2d",
#"gnosisSafeMultisigImplementationAddress":"0x65dD51b02049ad1B6FF7fa9Ea3322E1D2CAb1176",

#"gnosisSafeSameAddressMultisigImplementationAddress":"0x92499E80f50f06C4078794C179986907e7822Ea1",
#"operatorWhitelistAddress":"0x0338893fB1A1D9Df03F72CC53D8f786487d3D03E",
#"serviceRegistryTokenUtilityAddress":"0x6d9b08701Af43D68D991c074A27E4d90Af7f2276",
#"serviceManagerTokenAddress":"0x1d333b46dB6e8FFd271b6C2D2B254868BD9A2dbd"}

rm -rf out
