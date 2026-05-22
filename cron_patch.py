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
from datetime import datetime, timedelta, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

LOG_FILE = Path.home() / ".morningbriefing" / "log.jsonl"


def fetch_actual_avg(date_str: str, zone: str = "SE3", currency: str = "SEK") -> float | None:
    """Fetch actual day-ahead price average for a past date."""
    try:
        from plugins.elpris import fetch_prices
        data = fetch_prices(delivery_area=zone, currency=currency)
        # fetch_prices fetches today — if date matches, use it; else re-fetch with date param
        if data["data"]["date"] == date_str:
            return data["data"]["avg_price"]

        # Re-fetch for the specific past date
        import requests
        from plugins.elpris import PRIMARY_URL, HEADERS, _parse_entries
        from zoneinfo import ZoneInfo
        params = {"market": "DayAhead", "deliveryArea": zone, "currency": currency, "date": date_str}
        resp = requests.get(PRIMARY_URL, params=params, headers=HEADERS, timeout=10)
        resp.raise_for_status()
        prices = _parse_entries(resp.json(), zone)
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

    yesterday = (datetime.now(timezone.utc) - timedelta(days=1)).strftime("%Y-%m-%d")
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
            ts    = entry.get("timestamp", "")
            if ts.startswith(yesterday) and entry.get("actual_avg_price") is None:
                entry["actual_avg_price"] = actual
                patched += 1
        except json.JSONDecodeError:
            pass
        new_lines.append(json.dumps(entry, ensure_ascii=False))

    LOG_FILE.write_text("\n".join(new_lines) + "\n")
    print(f"[cron_patch] patched {patched} entr{'y' if patched==1 else 'ies'} for {yesterday} with actual avg {actual} öre/kWh")


if __name__ == "__main__":
    patch_yesterday()
