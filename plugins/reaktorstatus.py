#!/usr/bin/env python3
"""
Fetches active REMIT UMM production messages from Nord Pool, filtered for Nordic nuclear.
API: ummapi.nordpoolgroup.com/messages — public, no auth required.

Schema (confirmed 2026-05-22):
  Response:  {"items": [...], "total": N}  — paginated, default 2000 items/page
  messageType 1 = Production UMM
  productionUnits[].fuelType 14 = Nuclear (ENTSO-E fuel type code)
  productionUnits[].areaName  = bidding zone ("SE3", "FI", …)

Nordic nuclear plants: Forsmark 1-3 (SE3), Ringhals 1-4 (SE3),
Oskarshamn 1-3 (SE3), Olkiluoto 1-3 (FI), Loviisa 1-2 (FI).
"""
import json
import re
import requests
from datetime import datetime, timezone

UMM_URL      = "https://ummapi.nordpoolgroup.com/messages"
NORDIC_ZONES = frozenset({"SE1", "SE2", "SE3", "SE4", "FI"})


def _normalize_plant(name: str) -> str:
    """Nord Pool returns unit names inconsistently ('Forsmark Block3',
    'Forsmark block 3'). Canonicalize so dedup + display collapse to one."""
    s = re.sub(r"\s+", " ", (name or "Unknown").strip())
    s = re.sub(r"(?i)\bblock\s*", "Block ", s)   # 'block3'/'Block3' -> 'Block 3'
    return re.sub(r"\s+", " ", s).strip()
FUEL_NUCLEAR = 14
MSG_PRODUCTION = 1

HEADERS = {"Accept": "application/json", "User-Agent": "MorningBriefing/1.0"}


def _is_still_relevant(periods: list[dict], now: datetime) -> bool:
    """True if any time period ends in the future (or has no end)."""
    if not periods:
        return True
    for p in periods:
        stop_str = p.get("eventStop")
        if stop_str is None:
            return True
        try:
            stop = datetime.fromisoformat(stop_str.replace("Z", "+00:00"))
            if stop > now:
                return True
        except ValueError:
            return True
    return False


def fetch_umm() -> dict:
    now = datetime.now(timezone.utc)

    resp = requests.get(UMM_URL, headers=HEADERS, timeout=15)
    resp.raise_for_status()
    payload = resp.json()
    messages = payload.get("items", [])

    nuclear = []
    for msg in messages:
        if msg.get("messageType") != MSG_PRODUCTION:
            continue
        if msg.get("isOutdated", False):
            continue

        for unit in msg.get("productionUnits", []):
            if unit.get("fuelType") != FUEL_NUCLEAR:
                continue
            zone = (unit.get("areaName") or "").upper()
            if zone not in NORDIC_ZONES:
                continue
            periods = unit.get("timePeriods", [])
            if not _is_still_relevant(periods, now):
                continue

            for period in periods:
                stop_str = period.get("eventStop")
                if stop_str:
                    try:
                        stop = datetime.fromisoformat(stop_str.replace("Z", "+00:00"))
                        if stop <= now:
                            continue
                    except ValueError:
                        pass

                start_str = period.get("eventStart")
                is_active = False
                if start_str:
                    try:
                        start = datetime.fromisoformat(start_str.replace("Z", "+00:00"))
                        is_active = start <= now
                    except ValueError:
                        is_active = True   # unknown start → assume active
                else:
                    is_active = True

                nuclear.append({
                    "id":              msg.get("messageId"),
                    "plant":           _normalize_plant(unit.get("name", "Unknown")),
                    "zone":            zone,
                    "available_mw":    period.get("availableCapacity"),
                    "unavailable_mw":  period.get("unavailableCapacity"),
                    "installed_mw":    unit.get("installedCapacity"),
                    "event_start":     period.get("eventStart"),
                    "event_end":       period.get("eventStop"),
                    "unavail_type":    msg.get("unavailabilityType"),
                    "reason":          msg.get("unavailabilityReason", "").strip(),
                    "remarks":         msg.get("remarks", "").strip(),
                    "publisher":       msg.get("publisherName", ""),
                    "status":          msg.get("eventStatus"),
                    "is_active":       is_active,
                })

    active   = [u for u in nuclear if u["is_active"]]
    upcoming = [u for u in nuclear if not u["is_active"]]

    active_plants   = sorted({u["plant"] for u in active})
    upcoming_plants = sorted({u["plant"] for u in upcoming})
    all_plants      = sorted({u["plant"] for u in nuclear})
    total_unavail   = sum(u["unavailable_mw"] or 0 for u in active)

    if active:
        summary = (
            f"{len(active_plants)} aktiva nukleära UMM i Norden. "
            f"Berörda: {', '.join(active_plants)}. "
            f"Totalt unavailable: {total_unavail} MW."
        )
        if upcoming_plants:
            summary += f" Planerade ({len(upcoming_plants)}): {', '.join(upcoming_plants)}."
    elif upcoming_plants:
        summary = (
            f"Inga pågående nukleära UMM. "
            f"Planerade ({len(upcoming_plants)}): {', '.join(upcoming_plants)}."
        )
    else:
        summary = "Inga nukleära UMM i Norden just nu."

    return {
        "plugin":  "reaktorstatus",
        "summary": summary,
        "data": {
            "active_umms":      active,
            "upcoming_umms":    upcoming,
            "count":            len(active_plants),
            "upcoming_count":   len(upcoming_plants),
            "plants":           active_plants,
            "upcoming_plants":  upcoming_plants,
            "all_plants":       all_plants,
            "total_unavail_mw": total_unavail,
            "fetched_at":       now.isoformat(),
        },
    }


if __name__ == "__main__":
    try:
        result = fetch_umm()
        print(json.dumps(result, ensure_ascii=False, indent=2))
    except Exception as e:
        print(json.dumps({"plugin": "reaktorstatus", "error": str(e)}, ensure_ascii=False, indent=2))
