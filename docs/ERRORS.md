# Dice Protocol — Error Reference and Frontend Decoding

DiceEntropy uses Solidity custom errors. Frontends can decode errors with the SDK ABI and ethers.

```ts
import { Interface } from 'ethers';
import abi from '@diceprotocol/sdk/dist/abi.json';

const iface = new Interface(abi);
try {
  await tx.wait();
} catch (err: any) {
  const data = err?.data ?? err?.error?.data;
  if (data) console.log(iface.parseError(data));
}
```

Common errors:

| Error | Meaning | Typical fix |
|---|---|---|
| `InsufficientFee()` | `msg.value` is below required fee | Call `getFee(provider)` and send exact fee |
| `NoSuchProvider()` | Provider is not registered | Use `getDefaultProvider()` |
| `NoSuchRequest()` | Request does not exist or was already revealed | Check provider + sequence |
| `IncorrectRevelation()` | User/provider reveal does not match commitment | Use correct request data |
| `OutOfRandomness()` | Provider chain is exhausted | Wait for provider renewal |
| `MaxGasLimitExceeded()` | Callback gas limit is too high | Use lower gas limit |
| `Unauthorized()` | Caller lacks permission | Use authorized admin/provider |


## Refunds (v10)

If a request is not revealed within about 60–90 seconds (`refundDelayBlocks = 6` L1 blocks on Robinhood/Arbitrum Nitro), the original requester can call `refundRequest(provider, sequenceNumber)` and reclaim the exact fee paid for that request.

Live contract: `0xd8a0680e7699526b57140ed4eafdcc7219dc0a0c`.
