# Internal audit of autonolas-registries
The review has been performed based on the contract code in the following repository:<br>
`https://github.com/valory-xyz/autonolas-registries` <br>
commit: `tag: v1.2.2-pre-internal-audit` <br> 

## Objectives
The audit focused on fixing `PoAA Staking` contracts after C4A audit.

### Coverage
Hardhat coverage has been performed before the audit and can be found here:
```sh
 contracts/staking/                 |    95.77 |    89.83 |    96.08 |    95.09 |                |
  StakingActivityChecker.sol        |      100 |      100 |      100 |      100 |                |
  StakingBase.sol                   |    98.54 |    94.07 |       95 |    97.71 |... 886,893,904 |
  StakingFactory.sol                |    92.16 |    85.71 |    90.91 |    88.61 |... 291,295,297 |
  StakingNativeToken.sol            |      100 |       50 |      100 |       90 |             35 |
  StakingProxy.sol                  |      100 |       50 |      100 |       80 |             30 |
  StakingToken.sol                  |      100 |       80 |      100 |    95.83 |             95 |
  StakingVerifier.sol               |       90 |    87.93 |      100 |    93.75 |... 257,271,274 |
```
Please pay attention if possible. <br>
[x] Noted. Missing 100% is not an obvious problem.


#### Issue
```
Pay attention calculation for checkpoint().
serviceNonce - not needed to return
serviceIds - update before return
evictServiceIds - update before return
```
[x] fixed

#### Checking the corrections made after C4A
62. Adding staking instance as nominee before it is created #62
https://github.com/code-423n4/2024-05-olas-findings/issues/62
[x] fixed

57. Unstake function reverts because of use of outdated/stale serviceIds array #57
https://github.com/code-423n4/2024-05-olas-findings/issues/57
[x] fixed

49. A staked service may not be rewarded as available rewards may show obsolete value #49
https://github.com/code-423n4/2024-05-olas-findings/issues/49
[x] fixed

44. Malicious StakingToken instance can DoS deposits and control min deposit amount #44
https://github.com/code-423n4/2024-05-olas-findings/issues/44
[x] fixed

31. Blocklisted or paused state in staking token can prevent service owner from unstaking #31
https://github.com/code-423n4/2024-05-olas-findings/issues/31
[x] fixed

23. Staked service will be irrecoverable by owner if not an ERC721 receiver #23
https://github.com/code-423n4/2024-05-olas-findings/issues/23
[x] fixed

#### No need to change the code, just add information to the documentation
51. StakingToken.sol doesn't properly handle FOT, rebasing tokens or those with variable which will lead to accounting issues downstream. #51
https://github.com/code-423n4/2024-05-olas-findings/issues/51
```
Detailed list of "weird ERC20": https://github.com/d-xo/weird-erc20
```
[x] fixed

50. Griefing attack on unstaking services #50
https://github.com/code-423n4/2024-05-olas-findings/issues/50
[x] fixed

#### Low issue
QA Report #107
https://github.com/code-423n4/2024-05-olas-findings/issues/107
```
Event Emission for _withdraw in StakingNativeToken
```
[x] fixed in the upstream

#### Notes
QA Report #108
SafeTransferLib.sol doesn't mask addresses for safeTransfer and safeTransferFrom
```
./contracts/staking/StakingToken.sol:        SafeTransferLib.safeTransferFrom(stakingToken, msg.sender, address(this), amount);
TL/DR: This is not a problem for our code. Ideally, change the version of the library to a newer one, but using the old one does not pose a danger to our code, where address is "cleaned".
Details:
The root of the potential problem is that we are using an old version of the library.
key point of the masking issue is if you put some garbage in the higher order bits of a 256-bit type and then cast it down (с)
Example non-issue cases:
    SafeTransferLib.safeTransferFrom(stakingToken, msg.sender, to, amount); // own case
or
    uint96 a = type(uint96).max;
    address t = address(uint160(uint256(0x000000000000000000000000ffffffffffffffffffffffffffffffffffffffff)));
    Dummy memory dummy = Dummy(a, t); // "cleaning" by default
    SafeTransferLib.safeTransferFrom(stakingToken, msg.sender, dummy.to, amount);

Example issue:
    uint96 a = type(uint96).max;
    address t = address(uint160(uint256(0x000000000000000000000000ffffffffffffffffffffffffffffffffffffffff)));
    bytes memory packed = abi.encodePacked(a, t); // special unclean higher order bits
    SafeTransferLib.safeTransferFrom(stakingToken, msg.sender, address(uint160(uint256(bytes32(packed)))), amount); // special cast
or
    address to = address(uint160(uint256(0x0000000000000000000000010000000000000000000000000000000000000000))); // special cast
    SafeTransferLib.safeTransferFrom(stakingToken, msg.sender, to, amount);
Details:
https://github.com/code-423n4/2023-11-panoptic-findings/issues/154
```
[x] noted

#### Etherscan/gnosisscan issue
```
contracts/staking/StakingProxy.sol
    /// @dev Gets the implementation address.
    function getImplementation() external view returns (address implementation) {
        assembly {
            implementation := sload(SERVICE_STAKING_PROXY)
        }
    }
It is necessary to carry out tests with the option to move this function to implementation.
Perhaps this will solve the problem with proxy recognition on the side gnosisscan.
```
[x] noted

#### Notes: StakingVerifier (commit 261c597388426e4e3a412123f50ee4dbe5e9fa8f)
```
  some of the code just follows the same path ("fake if/elese") - since the path can't be changed it just wastes gas.
  StakingFactory:
  
 /// @dev Verifies a service staking contract instance.
    /// @param instance Service staking proxy instance.
    /// @return True, if verification is successful.
    function verifyInstance(address instance) public view returns (bool) {
        // Get proxy instance params
        InstanceParams storage instanceParams = mapInstanceParams[instance];
        address implementation = instanceParams.implementation;

        // Check that the implementation corresponds to the proxy instance
        if (implementation == address(0)) {
            return false;
        }

        // Check for the instance being active
        if (!instanceParams.isEnabled) {
            return false;
        }

        // Provide additional checks, if needed
        address localVerifier = verifier;
        if (localVerifier != address(0)) {
            return IStakingVerifier(localVerifier).verifyInstance(instance, implementation);
        }

        return true;
    }

    /// @dev Verifies staking proxy instance and gets emissions amount.
    /// @param instance Staking proxy instance.
    /// @return amount Emissions amount.
    function verifyInstanceAndGetEmissionsAmount(address instance) external view returns (uint256 amount) {
        // Verify the proxy instance
        bool success = verifyInstance(instance);

        if (success) {
            // If there is a verifier, get the emissions amount
            address localVerifier = verifier;
            if (localVerifier != address(0)) {
                // Get the max possible emissions amount
                amount = IStakingVerifier(localVerifier).getEmissionsAmountLimit(instance);
            } else {
                // Get the proxy instance emissions amount
                amount = IStaking(instance).emissionsAmount();
            }
        }
    }
	
	verifyInstanceAndGetEmissionsAmount:
	1. verifyInstance(instance)
	1.1. if localVerifier != address(0) 
	1.2. IStakingVerifier(localVerifier).verifyInstance(instance, implementation);
	1.3. verifyInstance(address instance, address implementation) external view returns (bool)
	      if (apy > apyLimit) {
            return false;
        } and etc
	if success (apy checking is success!) then
	2. if (localVerifier != address(0)) {
	2.1. amount = IStakingVerifier(localVerifier).getEmissionsAmountLimit(instance);
	     getEmissionsAmountLimit(instance)
		 ->
		 amount = IStaking(instance).emissionsAmount();
		 
    so,
	if (success) {
            // If there is a verifier, get the emissions amount
            address localVerifier = verifier;
            if (localVerifier != address(0)) {
                // Get the max possible emissions amount
                amount = IStakingVerifier(localVerifier).getEmissionsAmountLimit(instance);
            } else {
                // Get the proxy instance emissions amount
                amount = IStaking(instance).emissionsAmount();
            }
        }
	always equal:
	if (success) {
	   amount = IStaking(instance).emissionsAmount();
	}
    because the current code always produces this result.
```
[x] noted. No code base replacement required.

### Catch up on changes. 15.07.24
https://github.com/valory-xyz/autonolas-registries/compare/v1.2.2-pre-internal-audit...v1.2.2-pre-audit <br>
The changes to the codebase appear to be correct.
