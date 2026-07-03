#!/usr/bin/env python3
"""
Nightly cron job: patches yesterday's log entry with actual SE3 spot prices.
Run via launchd at e.g. 01:00 each night.

Launchd plist example (~/.local/share/morningbriefing or see README):
  ProgramArguments: ["/path/to/.venv/bin/python", "/path/to/cron_patch.py"]
  StartCalendarInterval: {Hour: 1, Minute: 0}
"""
import json
import sys
from datetime import datetime, timedelta
from pathlib import Path
from zoneinfo import ZoneInfo

sys.path.insert(0, str(Path(__file__).parent))

LOG_FILE = Path.home() / ".morningbriefing" / "log.jsonl"


def fetch_actual_avg(date_str: str, zone: str = "SE3", currency: str = "SEK") -> float | None:
    """Fetch actual day-ahead price average for a past date. Uses elpris's
    date-parameterized helper directly, so the fallback endpoint is tried too."""
    try:
        from plugins.elpris import _fetch_for_date
        prices, _ = _fetch_for_date(date_str, zone, currency)
        if not prices:
            return None
        return round(sum(p["price_ore_kwh"] for p in prices) / len(prices), 2)
    except Exception as e:
        print(f"[cron_patch] fetch failed for {date_str}: {e}", file=sys.stderr)
        return None


def patch_yesterday():
    if not LOG_FILE.exists():
        print("[cron_patch] no log file found, skipping")
        return

    # Lokal Stockholmstid — jobbet körs 01:00 lokalt; UTC vore två dygn bakåt
    # under sommartid (01:00 CEST = 23:00 UTC föregående dag).
    yesterday = (datetime.now(ZoneInfo("Europe/Stockholm")) - timedelta(days=1)).strftime("%Y-%m-%d")
    actual    = fetch_actual_avg(yesterday)

    if actual is None:
        print(f"[cron_patch] could not fetch actual price for {yesterday}")
        return

    lines   = LOG_FILE.read_text().splitlines()
    patched = 0

    new_lines = []
    for line in lines:
        if not line.strip():
            continue
        try:
            entry = json.loads(line)
        except json.JSONDecodeError:
            # Preserve the original line verbatim rather than dropping it or
            # re-emitting a stale entry from a previous iteration.
            new_lines.append(line)
            continue
        ts = entry.get("timestamp", "")
        if ts.startswith(yesterday) and entry.get("actual_avg_price") is None:
            entry["actual_avg_price"] = actual
            patched += 1
        new_lines.append(json.dumps(entry, ensure_ascii=False))

    LOG_FILE.write_text("\n".join(new_lines) + "\n")
    print(f"[cron_patch] patched {patched} entr{'y' if patched==1 else 'ies'} for {yesterday} with actual avg {actual} öre/kWh")


if __name__ == "__main__":
    patch_yesterday()
