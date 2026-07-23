# Dice Protocol — Risk Disclosure

Dice Protocol is production software. Integrators should understand its risk model.

## Live v10 parameters

- Contract: `0xd8a0680e7699526b57140ed4eafdcc7219dc0a0c`
- Chain: Robinhood Chain mainnet (4663)
- Fee: exact `0.000025 ETH` (`25000000000000` wei). Underpay and overpay both revert.
- Refund delay: `6` L1 blocks (~60–90 seconds wall-clock on Robinhood/Arbitrum Nitro, where `block.number` is L1)

## Keeper availability

v1 relies on the Tyche keeper to submit reveal transactions automatically. If the keeper is delayed or unavailable, callbacks may be delayed. After the refund delay, the original requester can call `refundRequest(provider, sequenceNumber)` and reclaim the exact fee paid for an unrevealed request. Applications should still treat randomness requests as asynchronous.

## Admin authority

The contract is immutable and has no proxy upgrade path. The admin can still adjust operational parameters such as the request fee and default provider, and can register/rotate provider commitments.

## Hash-chain exhaustion

Each provider commitment has a finite number of reveals. If exhausted before renewal, new requests revert with `OutOfRandomness()`. Admin can register a new commitment via `registerFor`.

## Callback behavior

When a gas limit is configured, callback reverts can be recorded without reverting the reveal if the safe-call gas condition is satisfied. If insufficient gas remains for the safe path, reveal can revert with `InsufficientGas()`. With `defaultGasLimit = 0`, stored `gasLimit10k = 0` and the gas-limited callback path does not run unless an explicit gas limit is passed on the request.

## Chain and sequencer assumptions

Robinhood Chain is an Arbitrum Nitro L2. Integrators should account for L2 sequencer behavior, RPC availability, finality assumptions, and the L1-block semantics of `block.number`.

## No investment advice

Protocol documentation is technical information, not financial, legal, or investment advice.
