#!/bin/bash

all_structs=()
# Loop through all Solidity files in the staking contracts
echo "---------------------------"
for contract_file in contracts/staking/*.sol contracts/interfaces/IErrorsRegistries.sol contracts/interfaces/IToken.sol; do
# Loop through each contract path
    contract_name=$(basename "$contract_file")

    # Get the structs and their count
    structs=$(grep -oE "(^)struct [a-zA-Z0-9_]*" "$contract_file")
    structs_count=$(grep -oE "(^)struct [a-zA-Z0-9_]*" "$contract_file" | wc -l)


    # Output the results
    echo "Contract Name: $contract_name"
    echo "Structs: $structs"
    echo "StructsNumber: $structs_count"
    echo "----"

    # Add structs statements to all_structs array
    all_structs+=($structs)
done

# Loop through the original all_structs array
for ((i = 0; i < ${#all_structs[@]}; i++)); do
    # If the current element is "struct"
    if [[ "${all_structs[i]}" == "struct" ]]; then
        # Concatenate "struct" with the next element (name) and add it to the new array
        struct_name="${all_structs[i+1]}"
        all_structs_conc+=("$struct_name")
    fi
done

# We are not currently including the logic to handle duplication. This can be added in the future

echo "Different Structs in all Staking Registry contracts:"
count=0
for struct_stmt in "${all_structs_conc[@]}"; do
    ((count++))
    echo "$count. $struct_stmt"
done

echo "Total Number of Different Structs: $count"