# Dice Protocol - Testnet Deployment

## Current deployment

| Property | Value |
|----------|-------|
| Address | `0xE4F1cc334a3d5FFf8b588573921CA9e2FFE22E5c` |
| Chain | Robinhood Chain Testnet (`46630`) |
| RPC | `https://rpc.testnet.chain.robinhood.com` |
| Explorer | `https://explorer.testnet.chain.robinhood.com/address/0xE4F1cc334a3d5FFf8b588573921CA9e2FFE22E5c` |
| Creation transaction | `0x62e4c625505fe51783ea35909df0c2f85160f06cbd20bc0753fd0a6608b73ff4` |
| Created | 2026-07-31 |
| Provider | `0x8741b8a825644D9Ef18Faf2DAB5e9b47B900F2b6` |
| Fee | `0.000025 ETH` exact (`25000000000000` wei) |
| Registered end sequence | `10000` |

These values were read from the current testnet deployment. Provider sequence and commitment advance as requests are fulfilled, so integrations should query `getProviderInfoV2(provider)` instead of copying a snapshot.

## Integration rules

- Generate the 32-byte user contribution with a cryptographically secure random-number generator.
- Call `getFeeV2(provider, gasLimit)` immediately before requesting and send that exact value.
- Use `requestV2(provider, userRandomNumber, gasLimit)`; legacy overloads without an explicit user contribution are disabled.
- Treat fulfillment as asynchronous and verify the `Revealed` event or callback result.
- Do not commit hash-chain seeds or private operational configuration.

## Read-only verification

```bash
cast call 0xE4F1cc334a3d5FFf8b588573921CA9e2FFE22E5c \
  "getDefaultProvider()(address)" \
  --rpc-url https://rpc.testnet.chain.robinhood.com

cast call 0xE4F1cc334a3d5FFf8b588573921CA9e2FFE22E5c \
  "getProtocolFee()(uint128)" \
  --rpc-url https://rpc.testnet.chain.robinhood.com
```

The explorer currently exposes the bytecode and transaction history. Source-verification status should be checked live rather than assumed from this document.
