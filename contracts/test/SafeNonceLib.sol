pragma solidity =0.8.21;

import {SafeStorage} from "./SafeStorage.sol";

contract SafeNonceLib is SafeStorage {
    event nonceUpdate(uint256 nonce);

    function inceraseNonce(uint256 _nonce) external {
        nonce += _nonce;
        emit nonceUpdate(nonce);
    }

    function decreaseNonce(uint256 _nonce) external {         
        if(nonce >= _nonce) {
		    nonce -= _nonce;
	    } else {
		    nonce = 0;
	    }
        emit nonceUpdate(nonce);
    }

}
