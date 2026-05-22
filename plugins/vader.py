#!/usr/bin/env python3
"""
Fetches current weather for Stockholm from Open-Meteo (free, no API key).
Wind speed is relevant for Nordic price prediction — high wind → lower spot prices.
"""
import json
import requests
from datetime import datetime
from zoneinfo import ZoneInfo

OPEN_METEO_URL = "https://api.open-meteo.com/v1/forecast"
LAT, LON = 59.3293, 18.0686  # Stockholm
TZ_NAME  = "Europe/Stockholm"
TZ       = ZoneInfo(TZ_NAME)

HEADERS = {"Accept": "application/json", "User-Agent": "MorningBriefing/1.0"}


def _wind_note(avg_wind_ms: float) -> str:
    if avg_wind_ms >= 10:
        return "Stark vind – hög vindproduktion trolig, trycker ner priser."
    if avg_wind_ms >= 6:
        return "Måttlig vind – viss vindproduktion, neutral priseffekt."
    if avg_wind_ms >= 3:
        return "Svag vind – begränsad vindproduktion."
    return "Vindstilla – vindkraft bidrar minimalt, priset drivs av annan produktion."


def fetch_weather() -> dict:
    params = {
        "latitude":        LAT,
        "longitude":       LON,
        "hourly":          "temperature_2m,wind_speed_10m,cloud_cover",
        "wind_speed_unit": "ms",
        "forecast_days":   1,
        "timezone":        TZ_NAME,
    }

    resp = requests.get(OPEN_METEO_URL, params=params, headers=HEADERS, timeout=10)
    resp.raise_for_status()
    raw = resp.json()

    hourly = raw["hourly"]
    times  = hourly["time"]
    temps  = hourly["temperature_2m"]
    winds  = hourly["wind_speed_10m"]
    clouds = hourly["cloud_cover"]

    now          = datetime.now(TZ)
    current_hour = min(now.hour, len(temps) - 1)

    temp  = temps[current_hour]
    wind  = winds[current_hour]
    cloud = clouds[current_hour]

    valid_temps  = [t for t in temps  if t is not None]
    valid_winds  = [w for w in winds  if w is not None]
    valid_clouds = [c for c in clouds if c is not None]

    avg_temp  = round(sum(valid_temps)  / len(valid_temps),  1) if valid_temps  else None
    avg_wind  = round(sum(valid_winds)  / len(valid_winds),  1) if valid_winds  else None
    avg_cloud = round(sum(valid_clouds) / len(valid_clouds), 1) if valid_clouds else None

    note = _wind_note(avg_wind or 0)

    return {
        "plugin":  "vader",
        "summary": (
            f"Stockholm nu: {temp}°C, vind {wind} m/s, molnighet {cloud}%. "
            f"Dagsnitt vind {avg_wind} m/s. {note}"
        ),
        "data": {
            "current_temp_c":    temp,
            "current_wind_ms":   wind,
            "current_cloud_pct": cloud,
            "daily_avg_temp_c":  avg_temp,
            "daily_avg_wind_ms": avg_wind,
            "daily_avg_cloud":   avg_cloud,
            "wind_note":         note,
            "source":            "open-meteo.com",
            "location":          "Stockholm",
        },
    }


if __name__ == "__main__":
    try:
        result = fetch_weather()
        print(json.dumps(result, ensure_ascii=False, indent=2))
    except Exception as e:
        print(json.dumps({"plugin": "vader", "error": str(e)}, ensure_ascii=False, indent=2))
