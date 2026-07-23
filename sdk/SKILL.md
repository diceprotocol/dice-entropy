# Dice Protocol Skill

## Agent-Friendly Onchain Randomness

Dice Protocol is a commit-reveal randomness oracle for Robinhood Chain (chain ID 4663). Any AI agent — BankrBot, AI wallet agents, DeFi automation agents, game-playing agents — can request verifiable onchain randomness with a few lines of code.

This SKILL.md is written for **agents**, not just humans. An agent reading this file should be able to integrate Dice Protocol without any human help.

---

## Quick Reference (live v10)

| Property | Value |
|----------|-------|
| Chain ID | 4663 (Robinhood Chain mainnet) |
| Contract | `0xd8a0680e7699526b57140ed4eafdcc7219dc0a0c` |
| Keeper (Provider) | `0x8741b8a825644D9Ef18Faf2DAB5e9b47B900F2b6` |
| Fee | **exact** `0.000025 ETH` (`25000000000000` wei) |
| Fee rule | `msg.value` must equal required fee exactly. Underpay **and** overpay both revert with `InsufficientFee()` |
| Refund delay | `6` L1 blocks (~60–90 seconds wall-clock) |
| Refund method | `refundRequest(provider, sequenceNumber)` — requester only |
| Latency | ~1–3 seconds typical (request → keeper reveal) |
| Package | `@diceprotocol/sdk` |
| License | Apache-2.0 (Pyth Entropy attribution) |
| Explorer | https://robinhoodchain.blockscout.com/address/0xd8a0680e7699526b57140ed4eafdcc7219dc0a0c |

Note on blocks: Robinhood/Arbitrum Nitro uses L1 `block.number` (~12s). That is why `refundDelayBlocks = 6` is about 60–90 seconds, not 6 L2 blocks.

---

## Integration Patterns

### Pattern 1: Solidity Smart Contract (Consumer)

Best for: onchain games, lotteries, DeFi protocols, NFT mints.

```solidity
// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import { IEntropyConsumer } from "@diceprotocol/sdk/IEntropyConsumer.sol";
import { IEntropy } from "@diceprotocol/sdk/IEntropy.sol";

contract MyGame is IEntropyConsumer {
    IEntropy public immutable dice;
    address public provider = 0x8741b8a825644D9Ef18Faf2DAB5e9b47B900F2b6;

    constructor(address _dice) {
        dice = IEntropy(_dice);
    }

    function playGame(bytes32 userRandom) external payable {
        // Prefer getFeeV2(provider, gasLimit). getFee(provider) also works for the flat fee.
        uint128 fee = dice.getFeeV2(provider, 200000);
        require(msg.value == fee, "fee must be exact");

        uint64 seq = dice.requestV2{value: fee}(
            provider,
            userRandom,
            200000  // gasLimit for callback
        );

        // Store mapping from seq → requester if needed
        seq;
    }

    // If keeper does not reveal within ~60–90s, original requester can reclaim exact fee:
    function reclaim(uint64 sequenceNumber) external {
        dice.refundRequest(provider, sequenceNumber);
    }

    // Called automatically by the keeper when randomness is revealed
    function entropyCallback(
        uint64 sequence,
        address,
        bytes32 randomNumber
    ) internal override {
        // Use randomNumber — it's unbiased and verifiable
        sequence;
        randomNumber;
    }

    // Required: return the DiceEntropy contract address
    function getEntropy() internal view override returns (address) {
        return address(dice);
    }
}
```

### Pattern 2: TypeScript SDK (Offchain Agent)

Best for: AI agents, automation scripts, backend services.

```bash
npm install @diceprotocol/sdk ethers
```

```typescript
import { DiceProtocol } from '@diceprotocol/sdk';
import { Wallet } from 'ethers';

const PROVIDER = '0x8741b8a825644D9Ef18Faf2DAB5e9b47B900F2b6';

const dice = new DiceProtocol({
  rpcUrl: 'https://rpc.mainnet.chain.robinhood.com',
  contractAddress: '0xd8a0680e7699526b57140ed4eafdcc7219dc0a0c',
});

const signer = new Wallet(process.env.PRIVATE_KEY!);

// 1. Fee must be exact (SDK request helper pays exact getFee result)
const fee = await dice.getFee(PROVIDER, 200000); // -> 25000000000000n today

// 2. Request randomness (user/agent supplies own random contribution)
const userRandom = DiceProtocol.generateUserRandom();
const seqNum = await dice.requestRandom(
  signer,
  PROVIDER,
  userRandom,
  200000  // gasLimit
);

// 3. Listen for reveal (~1–3s typical)
dice.onReveal((event) => {
  if (event.sequenceNumber === seqNum) {
    console.log('Random number:', event.randomNumber);
  }
});

// 4. If not revealed after ~60–90s:
// await dice.refundRequest(signer, PROVIDER, seqNum);
```

### Pattern 3: Raw Cast Commands (Quick Testing)

```bash
# Protocol fee (flat)
cast call 0xd8a0680e7699526b57140ed4eafdcc7219dc0a0c \
  "getProtocolFee()(uint128)" \
  --rpc-url https://rpc.mainnet.chain.robinhood.com

# Fee helpers (equivalent for current flat-fee model)
cast call 0xd8a0680e7699526b57140ed4eafdcc7219dc0a0c \
  "getFeeV2(address,uint32)(uint128)" \
  0x8741b8a825644D9Ef18Faf2DAB5e9b47B900F2b6 \
  200000 \
  --rpc-url https://rpc.mainnet.chain.robinhood.com

# Request randomness (MUST include exact --value)
cast send 0xd8a0680e7699526b57140ed4eafdcc7219dc0a0c \
  "requestV2(address,bytes32,uint32)" \
  0x8741b8a825644D9Ef18Faf2DAB5e9b47B900F2b6 \
  $(cast keccak 0xdeadbeef) \
  200000 \
  --value 25000000000000 \
  --rpc-url https://rpc.mainnet.chain.robinhood.com \
  --private-key $PK

# Refund after refundDelayBlocks (6 L1 blocks) if still unrevealed
cast send 0xd8a0680e7699526b57140ed4eafdcc7219dc0a0c \
  "refundRequest(address,uint64)" \
  0x8741b8a825644D9Ef18Faf2DAB5e9b47B900F2b6 \
  <SEQUENCE> \
  --rpc-url https://rpc.mainnet.chain.robinhood.com \
  --private-key $PK
```

---

## Agent-Specific Notes

### For BankrBot / Agent Orchestration

1. **Always pay the exact fee.** Read fee first (`getFee` / `getFeeV2` / `getProtocolFee`). `msg.value` must equal it exactly.
2. **Generate `userRandomNumber` locally** with a CSPRNG. This is the agent's contribution — provider cannot unilaterally set the final randomness.
3. **Wait ~1–3 seconds typical** for keeper reveal. Use `onReveal()` or poll `Revealed` logs / `getRequestV2`.
4. **If reveal never comes:** after ~60–90s call `refundRequest(provider, sequenceNumber)` as the original requester.
5. **Verify randomness onchain** from request/reveal contributions when needed.

### Why It's Agent-Safe

- **Immutability:** no proxy / upgrade path
- **Exact deterministic fee:** no under/overpay ambiguity
- **Requester refund path:** stuck requests are recoverable after delay
- **Onchain verifiability:** commitment + reveal + Keccak256 combine
- **Keeper auto-reveal:** agent does not submit provider reveal

### Gas Estimation

- Request tx: ~50,000 gas class of cost (varies)
- Reveal tx: paid by keeper, not requester
- Callback gas: from your `gasLimit` parameter (examples use 200,000)
- Protocol fee: exact `0.000025 ETH` today via `getProtocolFee()`

---

## ABI Summary

| Function | Who | Purpose |
|----------|-----|---------|
| `getProtocolFee()` | Anyone | Current flat protocol fee |
| `getFee(address provider)` | Anyone | Fee helper (flat-fee compatible) |
| `getFeeV2(address provider, uint32 gasLimit)` | Anyone | Preferred fee helper for requestV2 gasLimit path |
| `requestV2(address, bytes32, uint32)` | Consumer payable | Request randomness; **exact** `msg.value` |
| `getRequestV2(address, uint64)` | Anyone | Request state including `feePaid`, `blockNumber`, requester |
| `getRefundDelayBlocks()` | Anyone | Live value `6` |
| `refundRequest(address, uint64)` | Original requester | Refund exact `feePaid` after delay if still active |
| `revealWithCallback(...)` | Keeper/provider path | Reveal + consumer callback |
| `getProviderInfoV2(address)` | Anyone | Provider commitment / sequence metadata |
| `getDefaultProvider()` | Anyone | Default provider address |
| `setFee(uint128)` | Admin | Update protocol fee |
| `withdrawFees(uint128)` | Admin | Withdraw accrued fees |
| `registerFor(...)` | Admin | Register/rotate provider commitment |
| `setDefaultProvider(address)` | Admin | Set default provider |
| `proposeAdmin(address)` | Admin | Two-step admin transfer (step 1) |
| `acceptAdmin()` | Proposed admin | Two-step admin transfer (step 2) |

Events:

| Event | When |
|-------|------|
| `Requested(...)` | User requests randomness |
| `Revealed(...)` | Keeper/provider reveals |
| `RequestRefunded(...)` | Successful requester refund |

---

## Error Handling

| Error | Cause | Fix |
|-------|-------|-----|
| `InsufficientFee()` | `msg.value != requiredFee` (underpay **or** overpay) | Send exactly `getFeeV2` / `getProtocolFee` |
| `NoSuchRequest()` | Missing/already settled request | Check sequence; don't double-settle |
| `RefundNotAvailable()` | Too early, wrong caller, or already settled | Wait full 6 L1 blocks; caller must be requester |
| `Unauthorized()` | Wrong caller for admin/gated path | Use correct wallet |
| `OutOfRandomness()` | Provider hash chain exhausted | Admin must `registerFor` a new chain |
| `IncorrectRevelation()` | Bad reveal contribution | Keeper/provider bug or wrong reveal values |
| `InsufficientGas()` | Not enough gas left for gas-limited callback path | Raise gas / callback gasLimit appropriately |

---

## File Structure

```
@diceprotocol/sdk
├── SKILL.md
├── README.md
├── LICENSE
├── NOTICE
├── package.json
├── src/
│   ├── index.ts
│   └── abi.json
├── dist/
└── solidity/
    ├── IEntropy.sol
    ├── IEntropyConsumer.sol
    └── ...
```

---

## License

Apache-2.0. Portions of the protocol architecture and interfaces are adapted from Pyth Entropy / pyth-crosschain; see NOTICE.
