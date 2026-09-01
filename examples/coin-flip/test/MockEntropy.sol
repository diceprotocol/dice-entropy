// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {DiceErrors} from "@diceprotocol/sdk/solidity/DiceErrors.sol";
import {IEntropyConsumer} from "@diceprotocol/sdk/solidity/IEntropyConsumer.sol";

/// @notice Minimal DiceEntropy stand-in for CoinFlip unit tests.
contract MockEntropy {
    uint128 public fee;
    uint64 public nextSeq = 1;

    mapping(uint64 => address) public requesterOf;

    constructor(uint128 fee_) {
        fee = fee_;
    }

    function setFee(uint128 fee_) external {
        fee = fee_;
    }

    function getFeeV2(address, uint32) external view returns (uint128) {
        return fee;
    }

    function getFeeV2(uint32) external view returns (uint128) {
        return fee;
    }

    function getFeeV2() external view returns (uint128) {
        return fee;
    }

    function requestV2(address, bytes32, uint32) external payable returns (uint64 seq) {
        if (msg.value != fee) revert DiceErrors.InsufficientFee();
        seq = nextSeq++;
        requesterOf[seq] = msg.sender;
    }

    function fulfill(uint64 seq, bytes32 randomNumber) external {
        address consumer = requesterOf[seq];
        require(consumer != address(0), "no request");
        IEntropyConsumer(consumer)._entropyCallback(seq, address(this), randomNumber);
    }
}
