// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

// Getting ABIs for the Gnosis Safe master copy and proxy contracts
import "@gnosis.pm/safe-contracts/contracts/GnosisSafe.sol";
import {DefaultCallbackHandler} from "@gnosis.pm/safe-contracts/contracts/handler/DefaultCallbackHandler.sol";
import {CompatibilityFallbackHandler} from "@gnosis.pm/safe-contracts/contracts/handler/CompatibilityFallbackHandler.sol";
import "@gnosis.pm/safe-contracts/contracts/proxies/GnosisSafeProxyFactory.sol";
import "@gnosis.pm/safe-contracts/contracts/libraries/MultiSend.sol";
import "@gnosis.pm/safe-contracts/contracts/libraries/MultiSendCallOnly.sol";
import "@gnosis.pm/safe-contracts/contracts/examples/libraries/SignMessage.sol";