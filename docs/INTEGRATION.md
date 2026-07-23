# Dice Protocol — Integration Guide

## Quick Start

### 1. Install the SDK

```bash
npm install @diceprotocol/sdk
```

### 2. Request Randomness (Solidity)

```solidity
// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import { IEntropyConsumer } from "@diceprotocol/sdk/IEntropyConsumer.sol";
import { IEntropy } from "@diceprotocol/sdk/IEntropy.sol";

contract MyGame is IEntropyConsumer {
    IEntropy public immutable dice;
    address public provider;
    
    mapping(uint64 => bytes32) public results;
    mapping(uint64 => address) public requesters;
    
    constructor(address _dice, address _provider) {
        dice = IEntropy(_dice);
        provider = _provider;
    }
    
    function roll() external payable {
        // Generate user random contribution
        bytes32 userRandom = keccak256(abi.encodePacked(
            msg.sender,
            block.timestamp,
            block.prevrandao,
            gasleft()
        ));
        
        // Request randomness - must send exact fee
        uint64 seqNum = dice.requestV2{value: msg.value}(
            provider,
            userRandom,
            200000  // callback gas limit
        );
        
        requesters[seqNum] = msg.sender;
    }
    
    function entropyCallback(
        uint64 sequenceNumber,
        address,
        bytes32 randomNumber
    ) internal override {
        results[sequenceNumber] = randomNumber;
        // Use the random number in your game logic
    }
    
    function getEntropy() internal view override returns (address) {
        return address(dice);
    }
}
```

### 3. Request Randomness (TypeScript)

```typescript
import { DiceProtocol } from '@diceprotocol/sdk';
import { ethers } from 'ethers';

const provider = new ethers.JsonRpcProvider('https://rpc.mainnet.chain.robinhood.com');
const signer = new ethers.Wallet(process.env.PRIVATE_KEY!, provider);

const dice = new DiceProtocol({
  rpcUrl: 'https://rpc.mainnet.chain.robinhood.com',
  contractAddress: '0xd8a0680e7699526b57140ed4eafdcc7219dc0a0c',
});

// Get current fee
const fee = await dice.getFee('0x8741b8a825644D9Ef18Faf2DAB5e9b47B900F2b6');
console.log('Fee:', ethers.formatEther(fee), 'ETH');

// Request randomness
const userRandom = ethers.randomBytes(32);
const seqNum = await dice.requestRandom(
  signer,
  '0x8741b8a825644D9Ef18Faf2DAB5e9b47B900F2b6',
  ethers.hexlify(userRandom),
  200000
);

console.log('Request sequence:', seqNum);
// Tyche auto-reveals within ~3.5 seconds
// Your contract's entropyCallback() fires automatically
```

## Contract Addresses

| Component | Address |
|-----------|---------|
| DiceEntropy Contract | `0xd8a0680e7699526b57140ed4eafdcc7219dc0a0c` |
| Provider (Keeper) | `0x8741b8a825644D9Ef18Faf2DAB5e9b47B900F2b6` |
| Admin | `0x4ACD2C88a239a924E47Fc4995114ca1Bb0CA3CaD` |
| Vault (Fee Recipient) | `0x918EAF0b2589710B0D85ef48C12a343E68263841` |

## Network

| Parameter | Value |
|-----------|-------|
| Chain ID | 4663 |
| RPC URL | `https://rpc.mainnet.chain.robinhood.com` |
| Block Explorer | `https://robinhoodchain.blockscout.com` |
| Fee per Request | 0.000025 ETH (25,000,000,000,000 wei) |
| Reveal Time | ~3.5 seconds |

## How It Works

```
User Contract                DiceEntropy                Tyche Keeper
     │                            │                          │
     │── requestV2() ────────────►│                          │
     │   (pays 0.000025 ETH)      │                          │
     │                            │── Requested event ──────►│
     │                            │                          │
     │                            │   (computes reveal value) │
     │                            │◄── revealWithCallback() ──│
     │                            │   (verifies hash chain)   │
     │◄── entropyCallback() ──────│                          │
     │   (receives random number) │                          │
     │                            │                          │
```

## Fee Handling

- Each request costs exactly **0.000025 ETH**
- Fees accrue in the contract
- Admin withdraws accumulated fees to the vault via `withdrawFees()`
- The keeper is funded separately for gas costs

## Gas Considerations

| Operation | Gas | Notes |
|-----------|-----|-------|
| `requestV2()` | ~125,000 | Paid by requester |
| `revealWithCallback()` | ~200,000 | Paid by keeper |
| Callback execution | Consumer-specified | Example integrations use 200,000 gas |

Pass a callback gas limit that covers your callback logic. The examples use 200,000 gas. Keep callbacks small and deterministic.

## Error Reference

| Error | Cause |
|-------|-------|
| `InsufficientFee` | Sent ETH < provider fee |
| `NoSuchProvider` | Provider not registered |
| `NoSuchRequest` | Sequence number doesn't exist |
| `IncorrectRevelation` | Provider reveal doesn't match commitment |
| `OutOfRandomness` | Hash chain exhausted |
| `MaxGasLimitExceeded` | Requested gas limit > MAX_GAS_LIMIT |
| `Unauthorized` | Caller lacks permission |
| `BlockhashUnavailable` | Block hash for request block not available |

## Comparison

| Feature | Dice Protocol | Other RNG |
|---------|---------------|-----------|
| Deployment | Native to Robinhood Chain | External |
| Fee model | Flat 0.000025 ETH | Variable |
| Reveal time | ~3.5 seconds | Varies |
| Verifiability | On-chain Keccak256 | Varies |
| Callback | Automatic | Manual polling |
| Infrastructure | Self-hosted keeper | Third-party |

## Refunds (v10)

If a request is not revealed within about 60–90 seconds (`refundDelayBlocks = 6` L1 blocks on Robinhood/Arbitrum Nitro), the original requester can call `refundRequest(provider, sequenceNumber)` and reclaim the exact fee paid.
