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


def analyze(price_data: dict | None = None) -> dict:
    """Analyze SE3 prices. Accepts an already-fetched elpris payload so the
    aggregator can share one Nord Pool fetch; self-fetches when run standalone."""
    if price_data is None:
        price_data = fetch_prices()
    prices     = price_data["data"]["prices"]
    daily_avg  = price_data["data"]["avg_price"]
    daily_min  = price_data["data"]["min_price"]
    daily_max  = price_data["data"]["max_price"]

    start, end, window_avg = find_cheapest_window(prices)

    if start is not None:
        # Guard on magnitude — daily_avg can be negative on windy low-demand
        # days, and max(daily_avg, 0.01) would then explode the percentage.
        pct_under = round((daily_avg - window_avg) / max(abs(daily_avg), 0.01) * 100, 1)
        recommendation = (
            f"Kör tunga jobb {start:02d}:00–{end:02d}:00 "
            f"({window_avg} öre/kWh, {pct_under}% under dagsnitt)"
        )
        summary = (
            f"Billigaste {WINDOW_HOURS}h: {start:02d}–{end:02d} @ {window_avg} öre/kWh. "
            f"Dagsnitt {daily_avg}, spread {daily_min}–{daily_max} öre/kWh."
        )
    else:
        recommendation = "Otillräcklig prisdata – kan ej rekommendera körtidsfönster."
        summary        = recommendation

    data = {
        "daily_avg":      daily_avg,
        "daily_min":      daily_min,
        "daily_max":      daily_max,
        "recommendation": recommendation,
        "window_hours":   WINDOW_HOURS,
    }
    # Omit the window keys entirely on insufficient data — emitting null makes
    # Swift's decoder drop the whole core block, hiding the fallback
    # recommendation and the valid daily stats.
    if start is not None:
        data["cheapest_window_start"] = start
        data["cheapest_window_end"]   = end
        data["cheapest_window_avg"]   = window_avg

    return {
        "plugin":  "core",
        "summary": summary,
        "data":    data,
    }


if __name__ == "__main__":
    try:
        result = analyze()
        print(json.dumps(result, ensure_ascii=False, indent=2))
    except Exception as e:
        print(json.dumps({"plugin": "core", "error": str(e)}, ensure_ascii=False, indent=2))
