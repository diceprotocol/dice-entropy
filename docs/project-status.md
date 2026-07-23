# Project Status

## Live protocol (v10)

| Item | Value |
|------|-------|
| DiceEntropy | `0xd8a0680e7699526b57140ed4eafdcc7219dc0a0c` |
| Chain | Robinhood Chain mainnet (`4663`) |
| Fee | exact `0.000025 ETH` / `25000000000000` wei |
| Refund delay | `6` L1 blocks (~60–90s) |
| Provider | `0x8741b8a825644D9Ef18Faf2DAB5e9b47B900F2b6` |
| Vault | `0x918EAF0b2589710B0D85ef48C12a343E68263841` |
| Package | `@diceprotocol/sdk` |
| License | Apache-2.0 + Pyth Entropy NOTICE |

## Verified

- Foundry tests green for v10 fee/refund/callback suite
- Live E2E: request/reveal, early RefundNotAvailable, post-delay refund, setFee, withdrawFees
- Public address residue for old v9 scrubbed from active surfaces

## Pending human ops

- Admin wallet `0x4ACD…` should call `acceptAdmin()` if ownership transfer was proposed to it
- Production keeper should be pointed at `0xd8a0680e7699526b57140ed4eafdcc7219dc0a0c` (config updated locally)
- Optional: register a long production hash chain (current live registration used for launch E2E)

> Live v10 provider registration length is **1,000** (end sequence 1000). A longer production chain can be registered later with `registerFor`.
