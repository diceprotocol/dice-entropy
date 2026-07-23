# @diceprotocol/sdk

TypeScript SDK for [Dice Protocol](https://diceprotocol.world) — trustless commit-reveal randomness oracle on Robinhood Chain.

## Live v10

| Item | Value |
|------|-------|
| Package | `@diceprotocol/sdk` |
| Contract | `0xd8a0680e7699526b57140ed4eafdcc7219dc0a0c` |
| Chain ID | `4663` |
| Fee | exact `0.000025 ETH` (`25000000000000` wei) |
| Refund delay | `6` L1 blocks (~60–90s) via `refundRequest` |
| Provider | `0x8741b8a825644D9Ef18Faf2DAB5e9b47B900F2b6` |

## Install

```bash
npm install @diceprotocol/sdk
```

## Quick Start

```typescript
import { DiceProtocol } from '@diceprotocol/sdk';
import { Wallet } from 'ethers';

const dice = new DiceProtocol({
  rpcUrl: 'https://rpc.mainnet.chain.robinhood.com',
  contractAddress: '0xd8a0680e7699526b57140ed4eafdcc7219dc0a0c',
});

const signer = new Wallet(privateKey);
const provider = '0x8741b8a825644D9Ef18Faf2DAB5e9b47B900F2b6';

// Fee must be exact (underpay and overpay both revert)
const fee = await dice.getFee(provider, 200000); // 25000000000000n

const userRandom = DiceProtocol.generateUserRandom();
const seq = await dice.requestRandom(signer, provider, userRandom, 200000);

dice.onReveal((event) => {
  if (event.sequenceNumber === seq) {
    console.log('Random number:', event.randomNumber);
  }
});

// If not revealed within ~60–90s:
// await dice.refundRequest(signer, provider, seq);
```

## Agent guide

See [`SKILL.md`](./SKILL.md) for the full agent integration guide (exact fee, refunds, errors, cast examples).

## Solidity Interfaces

Solidity interfaces ship in [`solidity/`](./solidity):

```solidity
import {IEntropyConsumer} from "@diceprotocol/sdk/IEntropyConsumer.sol";
import {IEntropy} from "@diceprotocol/sdk/IEntropy.sol";
```

## License

Apache-2.0. Portions adapted from Pyth Entropy / pyth-crosschain. See `LICENSE` and `NOTICE`.
