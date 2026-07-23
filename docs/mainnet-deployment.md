# Dice Protocol — Mainnet Deployment

## Network
- **Chain**: Robinhood Chain Mainnet
- **Chain ID**: 4663
- **RPC**: `https://rpc.mainnet.chain.robinhood.com`
- **Explorer**: `https://robinhoodchain.blockscout.com`

## Contract
- **DiceEntropy**: `0xd8a0680e7699526b57140ed4eafdcc7219dc0a0c`
- **Verified**: Yes (Blockscout)
- **Fee**: 0.000025 ETH (25000000000000 wei) per request
- **Vault**: `0x918EAF0b2589710B0D85ef48C12a343E68263841`
- **Admin**: `0x4ACD2C88a239a924E47Fc4995114ca1Bb0CA3CaD`

## Provider
- **Address**: `0x8741b8a825644D9Ef18Faf2DAB5e9b47B900F2b6` (keeper)
- **Hash Chain**: 500,000 values registered on live v10
- **Commitment**: `0x3ee6b22e39df32c239ead8bd91e9378e9c65da12e6ec17b782f43e825c75d713`
- **Example callback gas**: 200,000
- **Auto-registered**: Yes (in constructor)

## Tyche Keeper Service
- **Status**: Running, auto-revealing requests
- **Operational details**: Internal only; do not publish server paths, config paths, or hosting details.

## E2E Verified
1. Consumer requests randomness (pays 0.000025 ETH)
2. Tyche detects `Requested` event within ~1–3 seconds typically
3. Tyche computes reveal value and submits `revealWithCallback`
4. Consumer's `entropyCallback()` fires with random number
5. Fees accumulate in contract (withdrawable to vault by admin)

## Wallets
| Role | Address | Type |
|------|---------|------|
| Admin | `0x4ACD2C88a239a924E47Fc4995114ca1Bb0CA3CaD` | Cold |
| Vault | `0x918EAF0b2589710B0D85ef48C12a343E68263841` | Cold |
| Keeper | `0x8741b8a825644D9Ef18Faf2DAB5e9b47B900F2b6` | Hot |

## Refunds (v10)

If a request is not revealed within about 60–90 seconds (`refundDelayBlocks = 6` L1 blocks on Robinhood/Arbitrum Nitro), the original requester can call `refundRequest(provider, sequenceNumber)` and reclaim the exact fee paid.

> Live v10 provider registration length is **500,000** (end sequence 500003). Longer chains can be registered later with `registerFor`.
