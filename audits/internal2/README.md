# Internal audit of autonolas-registries
The review has been performed based on the contract code in the following repository:<br>
`https://github.com/valory-xyz/autonolas-registries` <br>
commit: `v1.1.1.pre-internal-audit` <br> 

## Objectives
The audit focused on `managing services with custom ERC20 tokens` contracts in this repo.

### Flatten version
Flatten version of contracts. [contracts](https://github.com/valory-xyz/autonolas-registries/blob/main/audits/internal2/analysis/contracts) 

### ERC20/ERC721 checks
N/A

### Security issues. Updated 25-04-23
#### Problems found instrumentally
Several checks are obtained automatically. They are commented. Some issues found need to be fixed. <br>
All automatic warnings are listed in the following file, concerns of which we address in more detail below: <br>
[slither-full](https://github.com/valory-xyz/autonolas-registries/blob/main/audits/internal1/analysis/slither_full.txt)

- ignores return value by `IService(serviceRegistry).update()`: [x] fixed.

#### ServiceManagerToken needs attention
```
function create()
lines 100-105
for (uint256 i = 0; i < numAgents; ++i) {
    // Copy actual bond values for each agent Id
    bonds[i] = agentParams[i].bond;
    // Wrap bonds with the BOND_WRAPPER value for the original ServiceRegistry contract
    agentParams[i].bond = BOND_WRAPPER;
}
no zeros are allowed as we might incorrectly wrap zero bonds
```
[x] fixed

```
function update()
lines 149-156
for (uint256 i = 0; i < numAgents; ++i) {
    // Copy actual bond values for each agent Id that has at least one slot in the updated service
    if (agentParams[i].slots > 0) {
        bonds[i] = agentParams[i].bond;
    }
    // Wrap bonds with the BOND_WRAPPER value for the original ServiceRegistry contract
    agentParams[i].bond = BOND_WRAPPER;
}
not all zero bonds are allowed, as we don't want to wrap zero bonds, see above
```
[x] fixed

#### ServiceRegistryTokenUtility needs attention
```
registerAgentsTokenDeposit()
lines 299-337
// Get the operator allowance to this contract in specified tokens
            uint256 allowance = IToken(token).allowance(operator, address(this));
            if (allowance < totalBond) {
                revert IncorrectRegistrationDepositValue(allowance, totalBond, serviceId);
            }
...
totalBond += mapOperatorAndServiceIdOperatorBalances[operatorService]; // totalBond += x if apOperatorAndServiceIdOperatorBalances[operatorService] > 0
bool success = IToken(token).transferFrom(operator, address(this), totalBond);
checking allowance before calculating the final quantity

double check, please, logic
lines 325-326
totalBond += mapOperatorAndServiceIdOperatorBalances[operatorService];
mapOperatorAndServiceIdOperatorBalances[operatorService] = totalBond;
```
[x] fixed

### Needed improvements
#### ServiceManagerToken
```
version number

constructor(address _serviceRegistry, address _serviceRegistryTokenUtility) + operatorWhitelist in constructor
``` 
[x] fixed

#### OperatorWhitelist
```
It would be nice to add an additional user-assignable setting. Through the UI, you can select the most typical combination. 
At the same time, allowing the user to install as he needs, including: id, [addr1, addr2, addr3], [true, true, true], false
so,
setCheck = true equal setOperatorsCheck(true)
setCheck = false equal setOperatorsCheck(false)
function setOperatorsStatuses(uint256 serviceId, address[] memory operators, bool[] memory statuses, bool setCheck) external
```
[x] fixed

#### ServiceRegistryTokenUtility
```
            bool success = IToken(token).transfer(drainer, amount);
            if (!success) {
                revert TransferFailed(token, address(this), msg.sender, amount);
            }
simple cure for https://github.com/Defi-Cartel/salmonella
check balances[recipient] before/after transfer
low priority
```
[x] fixed

### TODO helpers
Below are tips on how to solve `TODO` 
```
TODO Check for the token ERC20 formality
function isERC20(address token) public view returns (bool) {
    bytes4 selector = bytes4(keccak256("balanceOf(address)"));
    bool success;
    bytes memory data = abi.encodeWithSelector(selector, address(0));

    if(token.code.length) {
        assembly {
            success := staticcall(
                gas(),            // gas remaining
                token, // destination address
                add(data, 32),    // input buffer (starts after the first 32 bytes in the `data` array)
                mload(data),      // input length (loaded from the first 32 bytes in the `data` array)
                0,                // output buffer
                0                 // output length
            )
        }
        // or Solidity without assembly
        // (bool success, bytes memory data) = token.staticcall(abi.encodeWithSignature("balanceOf(address)", address(0)));
        // Details: https://medium.com/coinmonks/call-staticcall-and-delegatecall-1f0e1853340
    }    
    return success;
}

```
[x] fixed

```	
TODO Safe transferFrom
https://github.com/transmissions11/solmate/blob/8f9b23f8838670afda0fd8983f2c41e8037ae6bc/src/utils/SafeTransferLib.sol
https://github.com/transmissions11/solmate/blob/8f9b23f8838670afda0fd8983f2c41e8037ae6bc/src/tokens/WETH.sol
https://github.com/transmissions11/solmate/blob/8f9b23f8838670afda0fd8983f2c41e8037ae6bc/src/test/SafeTransferLib.t.sol
```
[x] fixed