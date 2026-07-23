#!/usr/bin/env python3
"""Sidecar: subscribe to alchemy_minedTransactions, write requestV2 blocks to stdout.
The keeper reads stdout and processes the block ranges."""

import asyncio
import json
import sys
import os

import websockets

WS_URL = os.environ.get("MINED_TX_WS_URL", "")
CONTRACT = "0x2ad7fc99e3d8a8da72802936dd5145bf672206b0"
REQUEST_V2_SELECTOR = "0xf77b45e1"
REVEAL_DELAY = 0

async def main():
    while True:
        try:
            async with websockets.connect(WS_URL, max_size=10*1024*1024) as ws:
                # Subscribe to ALL mined txs
                sub = {
                    "jsonrpc": "2.0",
                    "id": 1,
                    "method": "eth_subscribe",
                    "params": ["alchemy_minedTransactions", {"hashesOnly": False}]
                }
                await ws.send(json.dumps(sub))
                ack = await ws.recv()
                sys.stderr.write(f"[mined_tx_watcher] subscribed: {ack[:60]}\n")
                sys.stderr.flush()

                async for raw in ws:
                    try:
                        d = json.loads(raw)
                        if "params" not in d:
                            continue
                        result = d["params"].get("result", {})
                        tx = result.get("transaction", result)
                        to_addr = (tx.get("to") or "").lower()
                        input_data = tx.get("input") or ""
                        block_hex = tx.get("blockNumber")

                        if to_addr != CONTRACT:
                            continue
                        if not input_data.startswith(REQUEST_V2_SELECTOR):
                            continue
                        if not block_hex:
                            continue

                        block_num = int(block_hex, 16)
                        safe = block_num - REVEAL_DELAY
                        # Write block number to stdout for the keeper to read
                        print(json.dumps({"block": safe, "tx": tx.get("hash","")[:18]}), flush=True)
                        sys.stderr.write(f"[mined_tx_watcher] requestV2 at block {block_num} (safe: {safe})\n")
                        sys.stderr.flush()
                    except Exception as e:
                        sys.stderr.write(f"[mined_tx_watcher] parse error: {e}\n")
                        sys.stderr.flush()
        except Exception as e:
            sys.stderr.write(f"[mined_tx_watcher] connection error: {e}, retrying in 2s\n")
            sys.stderr.flush()
            await asyncio.sleep(2)

if __name__ == "__main__":
    asyncio.run(main())
