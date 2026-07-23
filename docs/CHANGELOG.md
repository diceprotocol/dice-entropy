# Changelog

## v10 — 2026-07-23

- Deployed DiceEntropy v10 on Robinhood Chain mainnet: `0xd8a0680e7699526b57140ed4eafdcc7219dc0a0c`.
- Fee: exact `0.000025 ETH` (`25000000000000` wei), set on-chain after tiny-fee E2E.
- Added `refundRequest(provider, sequenceNumber)` with `refundDelayBlocks = 6` (~60–90s wall-clock; L1 blocks on Robinhood/Arbitrum Nitro).
- Per-request `feePaid` stored for correct refunds after fee changes.
- Apache-2.0 + Pyth Entropy attribution via NOTICE.
- SDK helpers: `registerProviderFor`, `withdrawFees`, `refundRequest`, `getRefundDelayBlocks`.
- Live E2E verified: request/reveal, early-refund reject, post-delay refund, setFee, withdrawFees.

All notable public documentation and SDK changes are tracked here.

## 1.0.0 — 2026-07-23

- Standardized mainnet contract address: `0xd8a0680e7699526b57140ed4eafdcc7219dc0a0c`.
- Standardized request fee: `0.000025 ETH`.
- Standardized SDK package name: `@diceprotocol/sdk`.
- Added FAQ, risk disclosure, versioning policy, Terms, Privacy, and API reference documentation.
- Cleaned public documentation contradictions before launch.