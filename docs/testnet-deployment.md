# Dice Protocol — Testnet Deployment

## Contract

| Property | Value |
|----------|-------|
| Address | `0xd8a0680e7699526b57140ed4eafdcc7219dc0a0c` |
| Chain | Robinhood Chain Testnet (46630) |
| RPC | `https://rpc.testnet.chain.robinhood.com/rpc` |
| Explorer | `https://explorer.testnet.chain.robinhood.com/address/0xd8a0680e7699526b57140ed4eafdcc7219dc0a0c` |
| Deploy Tx | `0x10b6a29b8fd07fb04b076e92287971ff713b24d5b6f28a17988b537bf03cd7ea` |
| Verified | Yes (Blockscout) |

## Provider Registration

| Property | Value |
|----------|-------|
| Provider Address | `0x8741b8a825644D9Ef18Faf2DAB5e9b47B900F2b6` |
| Registration Tx | `0x23db73acc551d592317bf4fc2b262114de0f2aa678165e773d8458fd94315a55` |
| Commitment (x_0) | `0x953114aeff79f3b330c8bee2b854d723c0d7713a3be9f6cb715c6c627091148c` |
| Chain Length | 1000 |
| Fee | 0 (free tier) |

## Hash Chain

The hash chain commitment is: x_0 = commitment (registered onchain).
Chain direction: x_n = seed, x_i = keccak256(x_{i+1}), x_0 = commitment.

**Seed stored in `secrets/` (gitignored). Never commit seeds.**

## Constructor Args

```
admin:              0x8741b8a825644D9Ef18Faf2DAB5e9b47B900F2b6
treasuryFeeInWei:   0
defaultProvider:    0x8741b8a825644D9Ef18Faf2DAB5e9b47B900F2b6
prefillRequestStorage: false
treasury:           0x8741b8a825644D9Ef18Faf2DAB5e9b47B900F2b6
```
