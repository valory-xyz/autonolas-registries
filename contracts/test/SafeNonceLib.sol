// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {GnosisSafeStorage} from "@gnosis.pm/safe-contracts/contracts/examples/libraries/GnosisSafeStorage.sol";

/// @title SafeNonceLib - Smart contract to manipulate the multisig nonce.
contract SafeNonceLib is GnosisSafeStorage {
    event nonceUpdated(uint256 nonce);

    function increaseNonce(uint256 _nonce) external {
        uint256 origNonce = uint256(nonce);
        origNonce += _nonce;
        nonce = bytes32(origNonce);
        emit nonceUpdated(origNonce);
    }

    function decreaseNonce(uint256 _nonce) external {
        uint256 origNonce = uint256(nonce);
        if (origNonce >= _nonce) {
            origNonce -= _nonce;
	    } else {
            origNonce = 0;
	    }
        nonce = bytes32(origNonce);
        emit nonceUpdated(origNonce);
    }

}
