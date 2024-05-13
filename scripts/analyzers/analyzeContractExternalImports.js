#!/bin/bash

# Enable nullglob to handle cases where no files match the pattern
shopt -s nullglob

# Function to extract non-interface imports from a Solidity contract
function extract_external_imports() {
    contract_path="$1"
    imports=$(grep "import .*;" "$contract_path" | grep -v "interface")
    echo "$imports"
}

# Array to store all import statements
all_imports=()

# Loop through all Solidity files in the staking contracts  
echo "---------------------------"
for contract_file in contracts/staking/*.sol contracts/interfaces/IErrorsRegistries.sol contracts/interfaces/IToken.sol; do
    contract_name=$(basename "$contract_file")
    echo "Contract Name: $contract_name"
    external_imports=$(extract_external_imports "$contract_file")
    echo "External Imports: $external_imports"
    echo "---------------------------"
    all_imports+=("$external_imports")
done 


#This script can be improved, is currently not complete