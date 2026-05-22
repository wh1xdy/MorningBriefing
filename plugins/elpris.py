#!/usr/bin/env python3
"""
Fetches SE3 day-ahead spot prices from Nord Pool.

Endpoint status (tested 2026-05-22):
  PRIMARY:  dataportal-api.nordpoolgroup.com/api/DayAheadPrices — works unauthenticated ✓
  FALLBACK: data.nordpoolgroup.com/api/DayAheadPrices           — not yet tested
  NOTE: The API returns 15-minute resolution (96 entries/day). _parse_entries
        averages the four quarter-hour blocks into 24 hourly prices.
"""
import json
import requests
from datetime import datetime, timezone
from zoneinfo import ZoneInfo

ZONE = "SE3"
CURRENCY = "SEK"
TZ = ZoneInfo("Europe/Stockholm")

PRIMARY_URL  = "https://dataportal-api.nordpoolgroup.com/api/DayAheadPrices"
FALLBACK_URL = "https://data.nordpoolgroup.com/api/DayAheadPrices"

HEADERS = {"Accept": "application/json", "User-Agent": "MorningBriefing/1.0"}


def _parse_entries(raw: dict, delivery_area: str) -> list[dict]:
    """
    API returns 15-minute blocks (96/day). Aggregate to 24 hourly averages.
    Conversion: SEK/MWh ÷ 10 = öre/kWh.
    """
    entries = raw.get("multiAreaEntries", [])
    hour_buckets: dict[int, list[float]] = {}

    for entry in entries:
        price_mwh = entry.get("entryPerArea", {}).get(delivery_area)
        if price_mwh is None:
            continue
        start_str = entry.get("deliveryStart", "")
        try:
            start_utc  = datetime.fromisoformat(start_str.replace("Z", "+00:00"))
            local_hour = start_utc.astimezone(TZ).hour
        except ValueError:
            continue
        hour_buckets.setdefault(local_hour, []).append(price_mwh)

    prices = []
    for hour in sorted(hour_buckets):
        avg_mwh = sum(hour_buckets[hour]) / len(hour_buckets[hour])
        prices.append({
            "hour":           hour,
            "price_ore_kwh":  round(avg_mwh / 10, 2),
        })
    return prices


def _get(url: str, params: dict) -> dict:
    resp = requests.get(url, params=params, headers=HEADERS, timeout=10)
    resp.raise_for_status()
    return resp.json()


def fetch_prices(delivery_area: str = ZONE, currency: str = CURRENCY) -> dict:
    today = datetime.now(TZ).date().isoformat()
    params = {
        "market":       "DayAhead",
        "deliveryArea": delivery_area,
        "currency":     currency,
        "date":         today,
    }

    raw = None
    used_endpoint = None
    last_exc = None

    for url in (PRIMARY_URL, FALLBACK_URL):
        try:
            raw = _get(url, params)
            used_endpoint = url
            break
        except requests.HTTPError as e:
            last_exc = e
            if e.response is not None and e.response.status_code in (401, 403):
                continue  # try fallback
            raise
        except requests.RequestException as e:
            last_exc = e
            continue

    if raw is None:
        raise RuntimeError(f"Both price endpoints failed. Last error: {last_exc}")

    prices = _parse_entries(raw, delivery_area)
    if not prices:
        raise ValueError(f"No price entries for {delivery_area} in response from {used_endpoint}")

    avg = round(sum(p["price_ore_kwh"] for p in prices) / len(prices), 2)
    mx  = max(p["price_ore_kwh"] for p in prices)
    mn  = min(p["price_ore_kwh"] for p in prices)

    return {
        "plugin":  "elpris",
        "summary": f"{delivery_area} snittpris {today}: {avg} öre/kWh (min {mn} / max {mx}). Källa: {used_endpoint}",
        "data": {
            "zone":         delivery_area,
            "currency":     currency,
            "unit":         "öre/kWh",
            "date":         today,
            "prices":       prices,
            "avg_price":    avg,
            "max_price":    mx,
            "min_price":    mn,
            "endpoint_used": used_endpoint,
        },
    }


if __name__ == "__main__":
    try:
        result = fetch_prices()
        print(json.dumps(result, ensure_ascii=False, indent=2))
    except Exception as e:
        print(json.dumps({"plugin": "elpris", "error": str(e)}, ensure_ascii=False, indent=2))
