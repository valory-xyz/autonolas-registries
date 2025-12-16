# Internal audit of autonolas-registries
The review has been performed based on the contract code in the following repository:<br>
`https://github.com/valory-xyz/autonolas-registries` <br>
commit: `v1.3.2-pre-internal-audit` or 24750cd659367d31854938ce601feb613e544721 <br> 

## Objectives
The audit focused on PolySafeCreatorWithRecoveryModule.

### ERC20/ERC721 checks
N/A

### Coverage
```
-------------------------------------|----------|----------|----------|----------|----------------|
File                                 |  % Stmts | % Branch |  % Funcs |  % Lines |Uncovered Lines |
-------------------------------------|----------|----------|----------|----------|----------------|
PolySafeCreatorWithRecoveryModule.sol |        0 |        0 |        0 |        0 |... 214,218,224 |
```
- Needed test for PolySafeCreatorWithRecoveryModule
[]  

### Issue
#### Notes/Low. Useless check
```
// Check for zero address
if (multisig == address(0)) {
    revert ZeroAddress();
}
This check will always pass (because multisig = IPolySafeProxyFactory(polySafeProxyFactory).computeProxyAddress(owners[0]);)
This check doesn't verify the account state after the operation, but simply checks the state of the variable.
If you want a 100% guarantee, you can check the bytecode hash at `multisig` account (address) vs 
function getContractBytecode() public view returns (bytes memory) {
       return abi.encodePacked(proxyCreationCode(), abi.encode(masterCopy));
    }
by Factory
We can be sure if:
1. Before Factory multisig.code.length == 0
2. After Factory multisig.code.length > 0 (Weak proof)
3. After Factory multisig.codehash == keccak256(Factory.getContractBytecode()) (Strong proof)
4. After Factory multisig.owners()[0] == ownwers[0] (Medium proof)

Warning: We don't check safeCreateSig vs owners, but Factorty always calculate owner based on sign: address owner = _getSigner(paymentToken, payment, paymentReceiver, createSig);
```
[] 