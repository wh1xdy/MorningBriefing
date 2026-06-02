#!/usr/bin/env python3
"""
Fetches live production data for Forsmark (F1/F2/F3) from Vattenfall's
public website. Data is embedded as JSON in a <script type="application/json">
tag — no API key required.

Source: karnkraft.vattenfall.se/forsmark/produktion/
Updates: continuously during office hours per Vattenfall.
"""
import json
import re
import requests
from datetime import datetime, timezone

URL = "https://karnkraft.vattenfall.se/forsmark/produktion/"
HEADERS = {"Accept": "text/html", "User-Agent": "MorningBriefing/1.0"}

# Installed capacity (MW) per block — used to compute offline fraction
CAPACITY = {"F1": 1121, "F2": 1120, "F3": 1172}


def fetch_forsmark() -> dict:
    resp = requests.get(URL, headers=HEADERS, timeout=15)
    resp.raise_for_status()

    # Extract the JSON blob from <script type="application/json" data-json-data>
    match = re.search(
        r'<script[^>]+type=["\']application/json["\'][^>]+data-json-data[^>]*>(.*?)</script>',
        resp.text,
        re.DOTALL,
    )
    if not match:
        raise ValueError("Could not find JSON data block on Vattenfall page")

    raw = json.loads(match.group(1).strip())
    blocks = raw.get("blockProductionDataList", [])
    ts_str = raw.get("timestamp", "")

    result = []
    offline = []
    for b in blocks:
        name  = b.get("name", "?")           # "F1", "F2", "F3"
        mw    = round(b.get("production", 0))
        pct   = round(b.get("percent", 0), 1)
        cap   = CAPACITY.get(name, 0)
        is_offline = pct < 5                  # < 5 % = effectively offline

        result.append({
            "block":       name,
            "production_mw": mw,
            "capacity_mw": cap,
            "percent":     pct,
            "offline":     is_offline,
        })
        if is_offline:
            offline.append(name)

    total_mw  = sum(b["production_mw"] for b in result)
    total_cap = sum(b["capacity_mw"]   for b in result)

    if offline:
        summary = (
            f"Forsmark: {len(offline)} block offline ({', '.join(offline)}). "
            f"Totalt {total_mw} / {total_cap} MW."
        )
    else:
        summary = f"Forsmark: alla block i drift. Totalt {total_mw} / {total_cap} MW."

    return {
        "plugin":  "vattenfall",
        "summary": summary,
        "data": {
            "plant":      "Forsmark",
            "blocks":     result,
            "offline":    offline,
            "total_mw":   total_mw,
            "total_cap_mw": total_cap,
            "source_ts":  ts_str,
            "fetched_at": datetime.now(timezone.utc).isoformat(),
        },
    }


if __name__ == "__main__":
    try:
        r = fetch_forsmark()
        print(json.dumps(r, ensure_ascii=False, indent=2))
    except Exception as e:
        print(json.dumps({"plugin": "vattenfall", "error": str(e)}, ensure_ascii=False))
