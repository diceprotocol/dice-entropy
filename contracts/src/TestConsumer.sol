// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import {IEntropyConsumer} from "./sdk/IEntropyConsumer.sol";
import {IEntropy} from "./sdk/IEntropy.sol";

/// @title Simple test consumer for testnet E2E
contract TestConsumer is IEntropyConsumer {
    IEntropy public immutable dice;
    address public provider;
    
    mapping(uint64 => bytes32) public results;
    mapping(uint64 => bool) public resolved;
    
    constructor(address _dice, address _provider) {
        dice = IEntropy(_dice);
        provider = _provider;
    }
    
    function request(bytes32 userRandom) external payable returns (uint64) {
        return dice.requestV2{value: msg.value}(provider, userRandom, 0);
    }

    /// @notice Request with explicit gas limit for the callback
    /// @param userRandom User-provided random contribution
    /// @param gasLimit Gas limit for callback. 0 = use provider default.
    function requestWithGasLimit(bytes32 userRandom, uint32 gasLimit) external payable returns (uint64) {
        return dice.requestV2{value: msg.value}(provider, userRandom, gasLimit);
    }
    
    function getEntropy() internal view override returns (address) {
        return address(dice);
    }
    
    function entropyCallback(uint64 sequence, address, bytes32 randomNumber) internal override {
        results[sequence] = randomNumber;
        resolved[sequence] = true;
    }
}
