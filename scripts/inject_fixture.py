#!/usr/bin/env python3
"""
inject_fixture.py — populate ~/.morningbriefing/latest.json with real plugin
data and the real (deterministic) briefing.

Since the briefing composer no longer uses the language model, this is simply
a lighter bridge.py: same plugins, same composer, but no log append and no
status-file choreography. Kept for quick UI iteration and for overriding the
briefing text:
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


def run(custom_briefing: str | None = None):
    # Samma orkestrering som produktion (core matas med elpris-resultatet,
    # felposter får samma form) — annars testar fixturen fel pipeline.
    from aggregator import run_plugins, PLUGINS
    from inference import generate_briefing

    print("Fetching plugins…", end=" ", flush=True)
    results, errors = run_plugins(
        on_result=lambda name, err: print(
            f"✓{name}" if err is None else f"✗{name}({err})", end=" ", flush=True
        )
    )
    print()

    briefing = custom_briefing or generate_briefing({"plugins": results}, language="sv")

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
