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
        pct = int((core.get("daily_avg", avg or 0) - ca) / max(core.get("daily_avg", avg or 1), 0.01) * 100)
        parts.append(
            f"Billigaste 4-timmarsfönster är {s:02d}:00–{e:02d}:00 "
            f"({ca:.1f} öre/kWh, {pct}% under dagsnitt)."
        )

    if r.get("count", 0) > 0:
        plants = ", ".join(r.get("plants", []))
        mw = r.get("total_unavail_mw", 0)
        parts.append(
            f"Aktiv nukleär UMM: {plants} ({mw} MW otillgängliga) — "
            f"kan höja spotpriset."
        )
    else:
        parts.append("Inga aktiva nukleära UMM just nu.")

    wind = (vader.get("daily_avg_wind_ms") or 0)
    if wind >= 6:
        parts.append(f"Hög vindproduktion ({wind} m/s) pressar sannolikt priserna.")
    elif wind <= 2:
        parts.append(f"Vindstilla ({wind} m/s) — kärnkraft och vattenkraft driver produktionen.")

    return " ".join(parts)


def run(custom_briefing: str | None = None):
    from plugins.elpris        import fetch_prices
    from plugins.reaktorstatus import fetch_umm
    from plugins.core          import analyze
    from plugins.vader         import fetch_weather
    from concurrent.futures    import ThreadPoolExecutor, as_completed

    fns = {"elpris": fetch_prices, "reaktorstatus": fetch_umm,
           "core": analyze, "vader": fetch_weather}

    results = {}
    errors  = {}
    print("Fetching plugins…", end=" ", flush=True)
    with ThreadPoolExecutor(max_workers=4) as pool:
        futures = {pool.submit(fn): name for name, fn in fns.items()}
        for future in as_completed(futures):
            name = futures[future]
            try:
                results[name] = future.result(timeout=20)
                print(f"✓{name}", end=" ", flush=True)
            except Exception as e:
                errors[name] = str(e)
                results[name] = {"plugin": name, "error": str(e), "summary": f"[{name} failed]", "data": {}}
                print(f"✗{name}({e})", end=" ", flush=True)
    print()

    plugins_data = {name: r for name, r in results.items()}
    briefing = custom_briefing or _template_briefing({n: r for n, r in results.items()})

    payload = {
        "briefing":     briefing,
        "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "plugins":      plugins_data,
        "summaries":    [results[n]["summary"] for n in fns if n in results],
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
