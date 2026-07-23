# API Reference (v10)

## On-chain contract

| Item | Value |
|------|-------|
| DiceEntropy | `0xd8a0680e7699526b57140ed4eafdcc7219dc0a0c` |
| Chain ID | `4663` |
| Fee | exact `0.000025 ETH` (`25000000000000` wei) |
| Refund delay | `getRefundDelayBlocks() == 6` L1 blocks (~60–90s) |
| Provider | `0x8741b8a825644D9Ef18Faf2DAB5e9b47B900F2b6` |
| Package | `@diceprotocol/sdk` |

## Core consumer methods

### `getFeeV2(address provider, uint32 gasLimit) -> uint128`
Returns the exact fee required for `requestV2`.

### `requestV2(address provider, bytes32 userRandomNumber, uint32 gasLimit) payable -> uint64`
Creates a request. Requires `msg.value == getFeeV2(...)` exactly. Underpay and overpay both revert with `InsufficientFee()`.

### `revealWithCallback(address provider, uint64 sequenceNumber, bytes32 userRevelation, bytes32 providerRevelation)`
Provider/keeper reveal path with consumer callback.

### `refundRequest(address provider, uint64 sequenceNumber)`
Requester-only. Available after `block.number >= request.blockNumber + refundDelayBlocks`. Refunds stored `feePaid` and clears the request.

### `getRequestV2(address provider, uint64 sequenceNumber)`
Returns request fields including `feePaid`, `blockNumber`, `requester`, callback status, and gas limit.

### `getProviderInfoV2(address provider)`
Provider commitment / sequence metadata.

### `getRefundDelayBlocks() -> uint64`
Live value is `6`.

### Admin
- `setFee(uint128)`
- `withdrawFees(uint128)`
- `registerFor(address,uint128,bytes32,bytes,uint64,bytes)`
- `setDefaultProvider(address)`
- `proposeAdmin(address)` / `acceptAdmin()`

## Tyche REST endpoints (operational)

Tyche may expose operational endpoints for monitoring and request/reveal lookup. Public availability and rate limits depend on the deployed environment. Do not rely on REST as the canonical randomness source; verify on-chain events and contract state.

### `GET /v1/chains/{chain_id}/revelations/{sequence}`
Returns the provider reveal value for a sequence when available.

### `GET /v1/chains/{chain_id}/requests`
Lists tracked requests known to the keeper.
