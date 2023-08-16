#!/bin/bash

if ! command -v ethereum-sources-downloader &> /dev/null
then
    # https://github.com/SergeKireev/ethereum-sources-downloader
    echo "ethereum-sources-downloader could not be found"
    npm i ethereum-sources-downloader
fi

############################### POLYGON MAINNET ###############################
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

# "serviceManagerAddress":"0x3C1fF68f5aa342D296d4DEe4Bb1cACCA912D95fE"
rm -rf out
ethereum-sources-downloader polygonscan 0x3C1fF68f5aa342D296d4DEe4Bb1cACCA912D95fE 2>&1 > /dev/null
r=$(diff -r out/ServiceManager/contracts/ contracts/ | grep -v Only)
if [ -z "$r" ]
then
      echo "OK. serviceManager (0x3C1fF68f5aa342D296d4DEe4Bb1cACCA912D95fE) on polygon eq contracts"
else
      echo "serviceManager (0x3C1fF68f5aa342D296d4DEe4Bb1cACCA912D95fE) on polygon NOT eq contracts"
fi
############################### /POLYGON MAINNET ###############################

############################### ETHEREUM GOERLI ###############################
#"serviceManagerTokenAddress":"0x1d333b46dB6e8FFd271b6C2D2B254868BD9A2dbd"
rm -rf out
ethereum-sources-downloader goerli.etherscan 0x1d333b46dB6e8FFd271b6C2D2B254868BD9A2dbd 2>&1 > /dev/null
r=$(diff -r out/ServiceManagerToken/contracts/ contracts/ | grep -v Only)
if [ -z "$r" ]
then
      echo "OK. ServiceManagerToken (0x1d333b46dB6e8FFd271b6C2D2B254868BD9A2dbd) on goerli eq contracts"
else
      echo "ServiceManagerToken (0x1d333b46dB6e8FFd271b6C2D2B254868BD9A2dbd) on goerli NOT eq contracts"
fi

#"serviceRegistryTokenUtilityAddress":"0x6d9b08701Af43D68D991c074A27E4d90Af7f2276"
rm -rf out
ethereum-sources-downloader goerli.etherscan 0x6d9b08701Af43D68D991c074A27E4d90Af7f2276 2>&1 > /dev/null
r=$(diff -r out/ServiceRegistryTokenUtility/contracts/ contracts/ | grep -v Only)
if [ -z "$r" ]
then
      echo "OK. serviceRegistryTokenUtility (0x6d9b08701Af43D68D991c074A27E4d90Af7f2276) on goerli eq contracts" 
else
      echo "serviceRegistryTokenUtility (0x6d9b08701Af43D68D991c074A27E4d90Af7f2276) on goerli NOT eq contracts"                                           
fi

#"operatorWhitelistAddress":"0x0338893fB1A1D9Df03F72CC53D8f786487d3D03E"
rm -rf out
ethereum-sources-downloader goerli.etherscan 0x0338893fB1A1D9Df03F72CC53D8f786487d3D03E 2>&1 > /dev/null
r=$(diff -r out/OperatorWhitelist/contracts/ contracts/ | grep -v Only)
if [ -z "$r" ]
then
      echo "OK. operatorWhitelist (0x0338893fB1A1D9Df03F72CC53D8f786487d3D03E) on goerli eq contracts"
else
      echo "operatorWhitelist (0x0338893fB1A1D9Df03F72CC53D8f786487d3D03E) on goerli NOT eq contracts"
fi

#"gnosisSafeMultisigImplementationAddress":"0x65dD51b02049ad1B6FF7fa9Ea3322E1D2CAb1176"
rm -rf out
ethereum-sources-downloader goerli.etherscan 0x65dD51b02049ad1B6FF7fa9Ea3322E1D2CAb1176 2>&1 > /dev/null
r=$(diff -r out/GnosisSafeMultisig/contracts/ contracts/ | grep -v Only)          
if [ -z "$r" ]
then
      echo "OK. gnosisSafeMultisigImplementation (0x65dD51b02049ad1B6FF7fa9Ea3322E1D2CAb1176) on goerli eq contracts"          
else
      echo "gnosisSafeMultisigImplementation (0x65dD51b02049ad1B6FF7fa9Ea3322E1D2CAb1176) on goerli NOT eq contracts"          
fi

#"gnosisSafeSameAddressMultisigImplementationAddress":"0x92499E80f50f06C4078794C179986907e7822Ea1"
rm -rf out
ethereum-sources-downloader goerli.etherscan 0x92499E80f50f06C4078794C179986907e7822Ea1 2>&1 > /dev/null
r=$(diff -r out/GnosisSafeSameAddressMultisig/contracts/ contracts/ | grep -v Only)
if [ -z "$r" ]
then
      echo "OK. gnosisSafeSameAddressMultisigImplementation (0x92499E80f50f06C4078794C179986907e7822Ea1) on goerli eq contracts"
else
      echo "gnosisSafeSameAddressMultisigImplementation (0x92499E80f50f06C4078794C179986907e7822Ea1) on goerli NOT eq contracts"
fi

#"serviceManagerAddress":"0xcDdD9D9ABaB36fFa882530D69c73FeE5D4001C2d"
rm -rf out
ethereum-sources-downloader goerli.etherscan 0xcDdD9D9ABaB36fFa882530D69c73FeE5D4001C2d 2>&1 > /dev/null
r=$(diff -r out/ServiceManager/contracts/ contracts/ | grep -v Only)
if [ -z "$r" ]
then
      echo "OK. serviceManager (0xcDdD9D9ABaB36fFa882530D69c73FeE5D4001C2d) on goerli eq contracts"
else
      echo "serviceManager (0xcDdD9D9ABaB36fFa882530D69c73FeE5D4001C2d) on goerli NOT eq contracts"
fi

#"serviceRegistryAddress":"0x1cEe30D08943EB58EFF84DD1AB44a6ee6FEff63a"
rm -rf out
ethereum-sources-downloader goerli.etherscan 0x1cEe30D08943EB58EFF84DD1AB44a6ee6FEff63a 2>&1 > /dev/null
r=$(diff -r out/ServiceRegistry/contracts/ contracts/ | grep -v Only)               
if [ -z "$r" ]
then
      echo "OK. serviceRegistry (0x1cEe30D08943EB58EFF84DD1AB44a6ee6FEff63a) on goerli eq contracts"
else
      echo "serviceRegistry (0x1cEe30D08943EB58EFF84DD1AB44a6ee6FEff63a) on goerli NOT eq contracts"
fi

#"registriesManagerAddress":"0x10c5525F77F13b28f42c5626240c001c2D57CAd4"
rm -rf out
ethereum-sources-downloader goerli.etherscan 0x10c5525F77F13b28f42c5626240c001c2D57CAd4 2>&1 > /dev/null
r=$(diff -r out/RegistriesManager/contracts/ contracts/ | grep -v Only)
if [ -z "$r" ]
then
      echo "OK. registriesManager (0x10c5525F77F13b28f42c5626240c001c2D57CAd4) on goerli eq contracts"
else
      echo "registriesManager (0x10c5525F77F13b28f42c5626240c001c2D57CAd4) on goerli NOT eq contracts"
fi

#"agentRegistryAddress":"0xEB5638eefE289691EcE01943f768EDBF96258a80"
rm -rf out
ethereum-sources-downloader goerli.etherscan 0xEB5638eefE289691EcE01943f768EDBF96258a80 2>&1 > /dev/null
r=$(diff -r out/AgentRegistry/contracts/ contracts/ | grep -v Only)
if [ -z "$r" ]
then
      echo "OK. agentRegistry (0xEB5638eefE289691EcE01943f768EDBF96258a80) on goerli eq contracts"
else
      echo "agentRegistry (0xEB5638eefE289691EcE01943f768EDBF96258a80) on goerli NOT eq contracts"
fi

#"componentRegistryAddress":"0x7Fd1F4b764fA41d19fe3f63C85d12bf64d2bbf68"
rm -rf out
ethereum-sources-downloader goerli.etherscan 0x7Fd1F4b764fA41d19fe3f63C85d12bf64d2bbf68 2>&1 > /dev/null
r=$(diff -r out/ComponentRegistry/contracts/ contracts/ | grep -v Only)
if [ -z "$r" ]
then
      echo "OK. componentRegistry (0x7Fd1F4b764fA41d19fe3f63C85d12bf64d2bbf68) on goerli eq contracts"
else
      echo "componentRegistry (0x7Fd1F4b764fA41d19fe3f63C85d12bf64d2bbf68) on goerli NOT eq contracts"
fi
############################### /ETHEREUM GOERLI ###############################

############################### ETHEREUM MAINNET ###############################
#"serviceManagerTokenAddress":"0x2EA682121f815FBcF86EA3F3CaFdd5d67F2dB143"
rm -rf out
ethereum-sources-downloader etherscan 0x2EA682121f815FBcF86EA3F3CaFdd5d67F2dB143 2>&1 > /dev/null
r=$(diff -r out/ServiceManagerToken/contracts/ contracts/ | grep -v Only)
if [ -z "$r" ]
then
      echo "OK. ServiceManagerToken (0x2EA682121f815FBcF86EA3F3CaFdd5d67F2dB143) on mainnet eq contracts"
else
      echo "ServiceManagerToken (0x2EA682121f815FBcF86EA3F3CaFdd5d67F2dB143) on mainnet NOT eq contracts"
fi

#"serviceRegistryTokenUtilityAddress":"0x3Fb926116D454b95c669B6Bf2E7c3bad8d19affA"
rm -rf out
ethereum-sources-downloader etherscan 0x3Fb926116D454b95c669B6Bf2E7c3bad8d19affA 2>&1 > /dev/null
r=$(diff -r out/ServiceRegistryTokenUtility/contracts/ contracts/ | grep -v Only)
if [ -z "$r" ]
then
      echo "OK. serviceRegistryTokenUtility (0x3Fb926116D454b95c669B6Bf2E7c3bad8d19affA) on mainnet eq contracts" 
else
      echo "serviceRegistryTokenUtility (0x3Fb926116D454b95c669B6Bf2E7c3bad8d19affA) on mainnet NOT eq contracts"                                           
fi

#"operatorWhitelistAddress":"0x42042799B0DE38AdD2a70dc996f69f98E1a85260"
rm -rf out
ethereum-sources-downloader etherscan 0x42042799B0DE38AdD2a70dc996f69f98E1a85260 2>&1 > /dev/null
r=$(diff -r out/OperatorWhitelist/contracts/ contracts/ | grep -v Only)
if [ -z "$r" ]
then
      echo "OK. operatorWhitelist (0x42042799B0DE38AdD2a70dc996f69f98E1a85260) on mainnet eq contracts"
else
      echo "operatorWhitelist (0x42042799B0DE38AdD2a70dc996f69f98E1a85260) on mainnet NOT eq contracts"
fi

#"gnosisSafeMultisigImplementationAddress":"0x46C0D07F55d4F9B5Eed2Fc9680B5953e5fd7b461"
rm -rf out
ethereum-sources-downloader etherscan 0x46C0D07F55d4F9B5Eed2Fc9680B5953e5fd7b461 2>&1 > /dev/null
r=$(diff -r out/GnosisSafeMultisig/contracts/ contracts/ | grep -v Only)          
if [ -z "$r" ]
then
      echo "OK. gnosisSafeMultisigImplementation (0x46C0D07F55d4F9B5Eed2Fc9680B5953e5fd7b461) on mainnet eq contracts"          
else
      echo "gnosisSafeMultisigImplementation (0x46C0D07F55d4F9B5Eed2Fc9680B5953e5fd7b461) on mainnet NOT eq contracts"          
fi

#"gnosisSafeSameAddressMultisigImplementationAddress":"0x26Ea2dC7ce1b41d0AD0E0521535655d7a94b684c"
rm -rf out
ethereum-sources-downloader etherscan 0x26Ea2dC7ce1b41d0AD0E0521535655d7a94b684c 2>&1 > /dev/null
r=$(diff -r out/GnosisSafeSameAddressMultisig/contracts/ contracts/ | grep -v Only)
if [ -z "$r" ]
then
      echo "OK. gnosisSafeSameAddressMultisigImplementation (0x26Ea2dC7ce1b41d0AD0E0521535655d7a94b684c) on mainnet eq contracts"
else
      echo "gnosisSafeSameAddressMultisigImplementation (0x26Ea2dC7ce1b41d0AD0E0521535655d7a94b684c) on mainnet NOT eq contracts"
fi

#"serviceManagerAddress":"0x38b062d11CD7596Ab5aDFe4d0e9F0dC3218E5389"
rm -rf out
ethereum-sources-downloader etherscan 0x38b062d11CD7596Ab5aDFe4d0e9F0dC3218E5389 2>&1 > /dev/null
r=$(diff -r out/ServiceManager/contracts/ contracts/ | grep -v Only)
if [ -z "$r" ]
then
      echo "OK. serviceManager (0x38b062d11CD7596Ab5aDFe4d0e9F0dC3218E5389) on mainnet eq contracts"
else
      echo "serviceManager (0x38b062d11CD7596Ab5aDFe4d0e9F0dC3218E5389) on mainnet NOT eq contracts"
fi

#"serviceRegistryAddress":"0x48b6af7B12C71f09e2fC8aF4855De4Ff54e775cA"
rm -rf out
ethereum-sources-downloader etherscan 0x48b6af7B12C71f09e2fC8aF4855De4Ff54e775cA 2>&1 > /dev/null
r=$(diff -r out/ServiceRegistry/contracts/ contracts/ | grep -v Only)               
if [ -z "$r" ]
then
      echo "OK. serviceRegistry (0x48b6af7B12C71f09e2fC8aF4855De4Ff54e775cA) on mainnet eq contracts"
else
      echo "serviceRegistry (0x48b6af7B12C71f09e2fC8aF4855De4Ff54e775cA) on mainnet NOT eq contracts"
fi

#"registriesManagerAddress":"0x9eC9156dEF5C613B2a7D4c46C383F9B58DfcD6fE"
rm -rf out
ethereum-sources-downloader etherscan 0x9eC9156dEF5C613B2a7D4c46C383F9B58DfcD6fE 2>&1 > /dev/null
r=$(diff -r out/RegistriesManager/contracts/ contracts/ | grep -v Only)
if [ -z "$r" ]
then
      echo "OK. registriesManager (0x9eC9156dEF5C613B2a7D4c46C383F9B58DfcD6fE) on mainnet eq contracts"
else
      echo "registriesManager (0x9eC9156dEF5C613B2a7D4c46C383F9B58DfcD6fE) on mainnet NOT eq contracts"
fi

#"agentRegistryAddress":"0x2F1f7D38e4772884b88f3eCd8B6b9faCdC319112"
rm -rf out
ethereum-sources-downloader etherscan 0x2F1f7D38e4772884b88f3eCd8B6b9faCdC319112 2>&1 > /dev/null
r=$(diff -r out/AgentRegistry/contracts/ contracts/ | grep -v Only)
if [ -z "$r" ]
then
      echo "OK. agentRegistry (0x2F1f7D38e4772884b88f3eCd8B6b9faCdC319112) on mainnet eq contracts"
else
      echo "agentRegistry (0x2F1f7D38e4772884b88f3eCd8B6b9faCdC319112) on mainnet NOT eq contracts"
fi

#"componentRegistryAddress":"0x15bd56669F57192a97dF41A2aa8f4403e9491776"
rm -rf out
ethereum-sources-downloader etherscan 0x15bd56669F57192a97dF41A2aa8f4403e9491776 2>&1 > /dev/null
r=$(diff -r out/ComponentRegistry/contracts/ contracts/ | grep -v Only)
if [ -z "$r" ]
then
      echo "OK. componentRegistry (0x15bd56669F57192a97dF41A2aa8f4403e9491776) on mainnet eq contracts"
else
      echo "componentRegistry (0x15bd56669F57192a97dF41A2aa8f4403e9491776) on mainnet NOT eq contracts"
fi
############################### /ETHEREUM MAINNET ###############################

rm -rf out
