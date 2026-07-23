#!/usr/bin/env python3
"""
Dice Protocol — Public RPC Doomsday Watchdog

Runs on a schedule. STAYS SILENT when healthy (empty stdout).
Prints an alert ONLY when the public RPC / keeper crosses a danger threshold.

Designed for `hermes cronjob` with no_agent=True:
  - empty stdout  -> nothing sent (healthy, the normal case)
  - non-empty     -> delivered verbatim as a Telegram alert

Signals monitored (all measured, no estimates):
  1. HTTP 429 rate-limit errors over the last window (public RPC choking)
  2. i/o timeouts to internal backend nodes (10.31.x.x)
  3. Keeper block lag vs chain head (are we falling behind?)
  4. systemd service health (is the keeper even alive?)

Thresholds are set well ABOVE the measured healthy baseline
(~2x429/min, ~11 block lag) so normal noise never pages anyone.
"""

import subprocess
import re
import sys
import json

# ---- Config -------------------------------------------------------------
SERVICE = "dice-tyche"
RPC_URL = "https://rpc.mainnet.chain.robinhood.com"
CAST = "/root/.foundry/bin/cast"
WINDOW = "5 minutes ago"          # measurement window
WINDOW_MINUTES = 5

# Alert thresholds (healthy baseline: 0 actual 429 errors, ~11 block lag)
MAX_429_PER_WINDOW = 10           # any real 429 is bad — alert at 10 (was 60, false-positive prone)
MAX_TIMEOUTS_PER_WINDOW = 20      # baseline is ~0-4
MAX_BLOCK_LAG = 150               # ~15s behind head (healthy ~11 = ~1s)
# -------------------------------------------------------------------------


def journal(since):
    try:
        r = subprocess.run(
            ["journalctl", "-u", SERVICE, "--since", since, "--no-pager", "-o", "cat"],
            capture_output=True, text=True, timeout=30,
        )
        return r.stdout
    except Exception as e:
        return f"__JOURNAL_ERROR__ {e}"


def count(pattern, text, flags=0):
    return len(re.findall(pattern, text, flags))


def cast_block_number():
    try:
        r = subprocess.run(
            [CAST, "block-number", "--rpc-url", RPC_URL],
            capture_output=True, text=True, timeout=15,
        )
        m = re.match(r"\s*(\d+)", r.stdout or "")
        return int(m.group(1)) if m else None
    except Exception:
        return None


def last_processed_block(text):
    matches = re.findall(r'"batch_to_block":(\d+)', text)
    if not matches:
        matches = re.findall(r'"range_to_block":(\d+)', text)
    return int(matches[-1]) if matches else None


def service_active():
    r = subprocess.run(["systemctl", "is-active", SERVICE],
                       capture_output=True, text=True, timeout=10)
    return r.stdout.strip() == "active"


def main():
    alerts = []

    # 1. Service alive?
    if not service_active():
        alerts.append(f"🔴 CRITICAL: `{SERVICE}` service is NOT active (keeper down).")

    logs = journal(WINDOW)
    if logs.startswith("__JOURNAL_ERROR__"):
        alerts.append(f"🔴 CRITICAL: cannot read keeper logs: {logs}")
        logs = ""

    # 2. 429 rate-limit errors — match ONLY actual HTTP 429 error messages,
    #    NOT block numbers or timestamps that happen to contain "429".
    #    Alchemy/public RPC 429 errors appear as: "Too Many Requests" or
    #    "error code 429" or "status.*429" or JSON-RPC "code": -32005 (rate limit)
    n429 = count(r"Too Many Requests|error code 429|HTTP 429|\"code\":\s*-32005|rate.?limit", logs, re.I)
    if n429 > MAX_429_PER_WINDOW:
        alerts.append(
            f"🟠 RPC RATE-LIMITED: {n429} HTTP 429 errors in last {WINDOW_MINUTES}m "
            f"(threshold {MAX_429_PER_WINDOW}). RPC is throttling the keeper — "
            f"reveals may be delayed. Check keeper RPC endpoint."
        )

    # 3. i/o timeouts — match actual network timeout errors
    ntimeout = count(r"i/o timeout|dial tcp.*timeout|connection refused", logs, re.I)
    if ntimeout > MAX_TIMEOUTS_PER_WINDOW:
        alerts.append(
            f"🟠 RPC TIMEOUTS: {ntimeout} i/o timeouts in last {WINDOW_MINUTES}m "
            f"(threshold {MAX_TIMEOUTS_PER_WINDOW}). Backend nodes (10.31.x.x) unreachable."
        )

    # 4. Block lag
    head = cast_block_number()
    last = last_processed_block(logs)
    if head is None:
        alerts.append("🟠 RPC UNREACHABLE: cast block-number failed against public RPC.")
    elif last is not None:
        lag = head - last
        if lag > MAX_BLOCK_LAG:
            alerts.append(
                f"🟠 KEEPER LAGGING: {lag} blocks behind head "
                f"(threshold {MAX_BLOCK_LAG}, ~{lag * 0.1:.0f}s). "
                f"Head={head}, last processed={last}. Reveals delayed."
            )

    # Output: SILENT when healthy, alert block when not
    if alerts:
        header = "⚠️ *DICE PROTOCOL — RPC WATCHDOG ALERT*\n"
        stats = (
            f"\n_diagnostics: 429s={n429}/{WINDOW_MINUTES}m, "
            f"timeouts={ntimeout}, "
            f"lag={head - last if (head and last) else 'n/a'} blocks_"
        )
        print(header + "\n".join(f"• {a}" for a in alerts) + stats)
        sys.exit(0)
    # healthy -> print nothing, exit 0 (silent)


if __name__ == "__main__":
    main()
