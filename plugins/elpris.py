#!/usr/bin/env python3
"""
Fetches SE3 day-ahead spot prices from Nord Pool.

Endpoint status (tested 2026-05-22):
  PRIMARY:  dataportal-api.nordpoolgroup.com/api/DayAheadPrices - works unauthenticated
  FALLBACK: data.nordpoolgroup.com/api/DayAheadPrices           - not yet tested
  NOTE: The API returns 15-minute resolution (96 entries/day). _parse_entries
        averages the four quarter-hour blocks into hourly prices (24 normally,
        23/25 on DST switch days).
"""
import json
import sys
import requests
from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo

ZONE = "SE3"
CURRENCY = "SEK"
TZ = ZoneInfo("Europe/Stockholm")

PRIMARY_URL  = "https://dataportal-api.nordpoolgroup.com/api/DayAheadPrices"
FALLBACK_URL = "https://data.nordpoolgroup.com/api/DayAheadPrices"

HEADERS = {"Accept": "application/json", "User-Agent": "MorningBriefing/1.0"}


def _parse_entries(raw: dict, delivery_area: str) -> list[dict]:
    """
    API returns 15-minute blocks (96/day). Aggregate to hourly averages.
    Bucketed by UTC delivery hour — not local hour-of-day — so the duplicated
    local 02:00 on the DST fall-back day stays two separate market hours
    (25 entries) instead of being averaged into one distorted price.
    Conversion: SEK/MWh ÷ 10 = öre/kWh.
    """
    entries = raw.get("multiAreaEntries", [])
    hour_buckets: dict[datetime, list[float]] = {}

    for entry in entries:
        price_mwh = entry.get("entryPerArea", {}).get(delivery_area)
        if price_mwh is None:
            continue
        start_str = entry.get("deliveryStart", "")
        try:
            start_utc = datetime.fromisoformat(start_str.replace("Z", "+00:00"))
        except ValueError:
            continue
        utc_hour = start_utc.replace(minute=0, second=0, microsecond=0)
        hour_buckets.setdefault(utc_hour, []).append(price_mwh)

    prices = []
    for utc_hour in sorted(hour_buckets):
        avg_mwh = sum(hour_buckets[utc_hour]) / len(hour_buckets[utc_hour])
        prices.append({
            "hour":           utc_hour.astimezone(TZ).hour,
            "price_ore_kwh":  round(avg_mwh / 10, 2),
        })
    return prices


def _get(url: str, params: dict) -> dict:
    resp = requests.get(url, params=params, headers=HEADERS, timeout=10)
    resp.raise_for_status()
    return resp.json()


def _fetch_for_date(date_str: str, delivery_area: str, currency: str) -> tuple[list[dict], str]:
    """Fetch and parse prices for a given date string (YYYY-MM-DD). Returns (prices, endpoint_used)."""
    params = {
        "market":       "DayAhead",
        "deliveryArea": delivery_area,
        "currency":     currency,
        "date":         date_str,
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
                continue
            raise
        except requests.RequestException as e:
            last_exc = e
            continue
    if raw is None:
        raise RuntimeError(f"Both price endpoints failed. Last error: {last_exc}")
    prices = _parse_entries(raw, delivery_area)
    return prices, used_endpoint


def fetch_prices(delivery_area: str = ZONE, currency: str = CURRENCY) -> dict:
    now = datetime.now(TZ)
    today = now.date().isoformat()
    tomorrow = (now.date() + timedelta(days=1)).isoformat()

    prices, used_endpoint = _fetch_for_date(today, delivery_area, currency)
    if not prices:
        raise ValueError(f"No price entries for {delivery_area} on {today}")

    avg = round(sum(p["price_ore_kwh"] for p in prices) / len(prices), 2)
    mx  = max(p["price_ore_kwh"] for p in prices)
    mn  = min(p["price_ore_kwh"] for p in prices)

    # Tomorrow's prices are published ~13:00 CET — omit if unavailable, but
    # log to stderr so a real regression (schema change, auth wall) is visible.
    # RuntimeError = both endpoints failed (raised by _fetch_for_date).
    tomorrow_prices = None
    try:
        t_prices, _ = _fetch_for_date(tomorrow, delivery_area, currency)
        if t_prices:
            tomorrow_prices = t_prices
    except (requests.RequestException, ValueError, RuntimeError) as e:
        print(f"[elpris] tomorrow's prices unavailable for {tomorrow}: {e}", file=sys.stderr)

    data = {
        "zone":          delivery_area,
        "currency":      currency,
        "unit":          "öre/kWh",
        "date":          today,
        "prices":        prices,
        "avg_price":     avg,
        "max_price":     mx,
        "min_price":     mn,
        "endpoint_used": used_endpoint,
    }
    if tomorrow_prices is not None:
        data["tomorrow_prices"] = tomorrow_prices

    return {
        "plugin":  "elpris",
        "summary": f"{delivery_area} snittpris {today}: {avg} öre/kWh (min {mn} / max {mx}). Källa: {used_endpoint}",
        "data": data,
    }


if __name__ == "__main__":
    try:
        result = fetch_prices()
        print(json.dumps(result, ensure_ascii=False, indent=2))
    except Exception as e:
        print(json.dumps({"plugin": "elpris", "error": str(e)}, ensure_ascii=False, indent=2))
