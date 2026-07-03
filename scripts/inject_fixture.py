#!/usr/bin/env python3
"""
inject_fixture.py — populate ~/.morningbriefing/latest.json with real plugin
data but a *template* briefing (no MLX needed).

Use this to test the Swift UI without loading the language model.
Run from the repo root:
    python scripts/inject_fixture.py
    python scripts/inject_fixture.py --briefing "Custom text here."
"""
import argparse
import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

OUTPUT = Path.home() / ".morningbriefing" / "latest.json"


def _template_briefing(plugins: dict) -> str:
    elpris = (plugins.get("elpris") or {}).get("data") or {}
    core   = (plugins.get("core")   or {}).get("data") or {}
    r      = (plugins.get("reaktorstatus") or {}).get("data") or {}
    vader  = (plugins.get("vader")  or {}).get("data") or {}

    avg = elpris.get("avg_price")
    mn  = elpris.get("min_price")
    mx  = elpris.get("max_price")
    date = elpris.get("date", "idag")

    parts = []
    if avg is not None:
        parts.append(
            f"SE3 spotpris {date}: {avg:.1f} öre/kWh i snitt "
            f"(min {mn:.1f} / max {mx:.1f})."
        )

    if core.get("cheapest_window_start") is not None:
        s, e, ca = core["cheapest_window_start"], core["cheapest_window_end"], core["cheapest_window_avg"]
        # abs() — dagsnittet kan vara negativt; se motsvarande guard i core.py
        pct = int((core.get("daily_avg", avg or 0) - ca) / max(abs(core.get("daily_avg", avg or 1)), 0.01) * 100)
        parts.append(
            f"Billigaste 4-timmarsfönster är {s:02d}:00–{e:02d}:00 "
            f"({ca:.1f} öre/kWh, {pct}% under dagsnitt)."
        )

    if r.get("count", 0) > 0:
        plants = ", ".join(r.get("plants", []))
        mw = r.get("total_unavail_mw", 0)
        parts.append(
            f"Aktiv nukleär UMM: {plants} ({mw} MW otillgängliga) — kan höja spotpriset."
        )
    elif r.get("upcoming_count", 0) > 0:
        up = ", ".join(r.get("upcoming_plants", []))
        parts.append(f"Planerad nukleär UMM: {up}.")
    else:
        parts.append("Inga nukleära UMM just nu.")

    wind = (vader.get("daily_avg_wind_ms") or 0)
    if wind >= 6:
        parts.append(f"Hög vindproduktion ({wind} m/s) pressar sannolikt priserna.")
    elif wind <= 2:
        parts.append(f"Vindstilla ({wind} m/s) — kärnkraft och vattenkraft driver produktionen.")

    return " ".join(parts)


def run(custom_briefing: str | None = None):
    # Samma orkestrering som produktion (core matas med elpris-resultatet,
    # felposter får samma form) — annars testar fixturen fel pipeline.
    from aggregator import run_plugins, PLUGINS

    print("Fetching plugins…", end=" ", flush=True)
    results, errors = run_plugins(
        on_result=lambda name, err: print(
            f"✓{name}" if err is None else f"✗{name}({err})", end=" ", flush=True
        )
    )
    print()

    briefing = custom_briefing or _template_briefing(results)

    payload = {
        "briefing":     briefing,
        "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "plugins":      results,
        "summaries":    [results[n]["summary"] for n in PLUGINS if n in results],
        "errors":       errors,
    }

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(payload, ensure_ascii=False, indent=2))
    print(f"Written → {OUTPUT}")
    print(f"Briefing: {briefing[:120]}…")
    return payload


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--briefing", default=None, help="Override briefing text")
    args = parser.parse_args()
    run(custom_briefing=args.briefing)
