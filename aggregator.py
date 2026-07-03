#!/usr/bin/env python3
"""
Runs all plugins in parallel, collects JSON output, returns combined payload for inference.
Plugin failures are isolated — a crashed plugin yields an error entry, not a crash.
"""
import json
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

from plugins.elpris        import fetch_prices
from plugins.reaktorstatus import fetch_umm
from plugins.core          import analyze
from plugins.vader         import fetch_weather
from plugins.vattenfall    import fetch_forsmark

# Ordningen styr summaries. "core" körs inte i poolen — den analyserar
# elpris-resultatet efteråt (en Nord Pool-hämtning i stället för två).
PLUGINS = {
    "elpris":        fetch_prices,
    "reaktorstatus": fetch_umm,
    "core":          analyze,
    "vader":         fetch_weather,
    "vattenfall":    fetch_forsmark,
}


def run_plugins(on_result=None) -> tuple[dict, dict]:
    """
    Runs the fetching plugins in parallel, then feeds the completed elpris
    result into core (pure computation, no second fetch). Failures are
    isolated per plugin. `on_result(name, error_or_none)` is called as each
    plugin finishes — used by inject_fixture for progress output.
    Returns (results, errors).
    """
    results = {}
    errors  = {}

    def _record_failure(name, e):
        errors[name]  = str(e)
        results[name] = {"plugin": name, "error": str(e), "summary": f"[{name} failed: {e}]", "data": {}}

    fetchers = {name: fn for name, fn in PLUGINS.items() if name != "core"}
    with ThreadPoolExecutor(max_workers=4) as pool:
        futures = {pool.submit(fn): name for name, fn in fetchers.items()}
        for future in as_completed(futures):
            name = futures[future]
            try:
                # No timeout: as_completed only yields finished futures, so a
                # result()-timeout here could never fire.
                results[name] = future.result()
            except Exception as e:
                _record_failure(name, e)
            if on_result:
                on_result(name, errors.get(name))

    try:
        if "elpris" in errors:
            raise RuntimeError(f"elpris failed — no price data to analyze: {errors['elpris']}")
        results["core"] = analyze(results["elpris"])
    except Exception as e:
        _record_failure("core", e)
    if on_result:
        on_result("core", errors.get("core"))

    return results, errors


def run_all() -> dict:
    results, errors = run_plugins()

    return {
        "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "plugins":       results,
        "errors":        errors,
        "summaries":     [results[n]["summary"] for n in PLUGINS if n in results],
    }


if __name__ == "__main__":
    payload = run_all()
    print(json.dumps(payload, ensure_ascii=False, indent=2))
