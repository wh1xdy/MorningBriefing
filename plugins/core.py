#!/usr/bin/env python3
"""
Analyzes today's SE3 prices and finds the cheapest consecutive 4-hour window.
Depends on elpris.fetch_prices() — imports directly from sibling module.
"""
import json
import sys
import os

sys.path.insert(0, os.path.dirname(__file__))
from elpris import fetch_prices

WINDOW_HOURS = 4


def find_cheapest_window(prices: list[dict], window: int = WINDOW_HOURS):
    """
    Sliding-window search over hourly prices.
    Returns (start_hour, end_hour, avg_ore_kwh) or (None, None, None) if insufficient data.
    """
    if len(prices) < window:
        return None, None, None

    best_avg   = float("inf")
    best_start = prices[0]["hour"]
    best_end   = best_start + window

    for i in range(len(prices) - window + 1):
        segment = prices[i : i + window]
        avg = sum(p["price_ore_kwh"] for p in segment) / window
        if avg < best_avg:
            best_avg   = avg
            best_start = segment[0]["hour"]
            # Derive the end from the segment's last hour, not start+window, so a
            # gap in the hourly data (DST spring-forward, API hole) stays correct.
            best_end   = segment[-1]["hour"] + 1

    return best_start, best_end, round(best_avg, 2)


def analyze() -> dict:
    price_data = fetch_prices()
    prices     = price_data["data"]["prices"]
    daily_avg  = price_data["data"]["avg_price"]
    daily_min  = price_data["data"]["min_price"]
    daily_max  = price_data["data"]["max_price"]

    start, end, window_avg = find_cheapest_window(prices)

    if start is not None:
        recommendation = (
            f"Kör tunga jobb {start:02d}:00–{end:02d}:00 "
            f"({window_avg} öre/kWh, {round((daily_avg - window_avg) / max(daily_avg, 0.01) * 100, 1)}% under dagsnitt)"
        )
        summary = (
            f"Billigaste {WINDOW_HOURS}h: {start:02d}–{end:02d} @ {window_avg} öre/kWh. "
            f"Dagsnitt {daily_avg}, spread {daily_min}–{daily_max} öre/kWh."
        )
    else:
        recommendation = "Otillräcklig prisdata – kan ej rekommendera körtidsfönster."
        summary        = recommendation

    return {
        "plugin":  "core",
        "summary": summary,
        "data": {
            "cheapest_window_start": start,
            "cheapest_window_end":   end,
            "cheapest_window_avg":   window_avg,
            "daily_avg":             daily_avg,
            "daily_min":             daily_min,
            "daily_max":             daily_max,
            "recommendation":        recommendation,
            "window_hours":          WINDOW_HOURS,
        },
    }


if __name__ == "__main__":
    try:
        result = analyze()
        print(json.dumps(result, ensure_ascii=False, indent=2))
    except Exception as e:
        print(json.dumps({"plugin": "core", "error": str(e)}, ensure_ascii=False, indent=2))
