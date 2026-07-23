# Dice Protocol — FAQ

## What is Dice Protocol?

Dice Protocol is a commit-reveal randomness oracle on Robinhood Chain. Consumer contracts request randomness, the Tyche keeper reveals a pre-committed hash-chain value, and the contract combines the user contribution with the provider contribution to produce a verifiable random number.

## What does a request cost?

Mainnet requests cost 0.000025 ETH. Always call `getFee(provider)` before sending a request because the admin can update the fee.

## What contract address should I use?

Mainnet DiceEntropy: `0xd8a0680e7699526b57140ed4eafdcc7219dc0a0c`.

## Which SDK package should I install?

Use `@diceprotocol/sdk`.

## What happens if the keeper is unavailable?

Requests remain on-chain until revealed. v1 depends on keeper availability for automatic callbacks. Applications should design UX around asynchronous resolution and monitor request status.

## Can the admin change the fee?

Yes. The immutable contract logic cannot be upgraded, but the admin can update operational parameters such as the request fee and default provider.

## What happens when the hash chain runs out?

The provider must register a new commitment before exhaustion. Requests revert with `OutOfRandomness()` after the active chain is depleted.

## Is $DICE required to use the protocol?

No. v1 uses native ETH fees. $DICE is planned and not yet released.

## Refunds (v10)

If a request is not revealed within about 60–90 seconds (`refundDelayBlocks = 6` L1 blocks on Robinhood/Arbitrum Nitro), the original requester can call `refundRequest(provider, sequenceNumber)` and reclaim the exact fee paid.
