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

PLUGINS = {
    "elpris":        fetch_prices,
    "reaktorstatus": fetch_umm,
    "core":          analyze,
    "vader":         fetch_weather,
}


def run_all() -> dict:
    results = {}
    errors  = {}

    with ThreadPoolExecutor(max_workers=4) as pool:
        futures = {pool.submit(fn): name for name, fn in PLUGINS.items()}
        for future in as_completed(futures):
            name = futures[future]
            try:
                results[name] = future.result(timeout=30)
            except Exception as e:
                errors[name] = str(e)
                results[name] = {"plugin": name, "error": str(e), "summary": f"[{name} failed: {e}]", "data": {}}

    return {
        "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "plugins":       results,
        "errors":        errors,
        "summaries":     [results[n]["summary"] for n in PLUGINS if n in results],
    }


if __name__ == "__main__":
    payload = run_all()
    print(json.dumps(payload, ensure_ascii=False, indent=2))
