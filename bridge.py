#!/usr/bin/env python3
"""
Full pipeline runner: aggregator → inference → write output file.
Swift calls this as an NSTask on wake; reads the result from OUTPUT_FILE.

Output file: ~/.morningbriefing/latest.json
Swift watches for mtime change on that file to know when the briefing is ready.
"""
import argparse
import json
import sys
import time
import traceback
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

OUTPUT_FILE  = Path.home() / ".morningbriefing" / "latest.json"
LOG_FILE     = Path.home() / ".morningbriefing" / "log.jsonl"
STATUS_FILE  = Path.home() / ".morningbriefing" / "status.json"   # Swift polls this for progress


def _write_status(stage: str, error: str | None = None):
    STATUS_FILE.write_text(json.dumps({
        "stage": stage,
        "error": error,
        "ts":    time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    }))


def _append_log(payload: dict, briefing: str):
    core = payload.get("plugins", {}).get("core", {}).get("data", {})
    entry = {
        "timestamp":            payload.get("generated_at"),
        "predicted_avg_price":  core.get("daily_avg"),
        "recommendation_window": (
            f"{core.get('cheapest_window_start', 0):02d}-"
            f"{core.get('cheapest_window_end', 0):02d}"
        ),
        "briefing":             briefing,
        "plugin_data":          payload.get("plugins", {}),
        "actual_avg_price":     None,   # patched by cron_patch.py
    }
    with LOG_FILE.open("a") as f:
        f.write(json.dumps(entry, ensure_ascii=False) + "\n")


def run(language: str = "sv"):
    OUTPUT_FILE.parent.mkdir(parents=True, exist_ok=True)

    _write_status("aggregating")
    from aggregator import run_all
    payload = run_all()

    _write_status("generating_briefing")
    from inference import generate_briefing
    briefing = generate_briefing(payload, language=language)

    result = {
        "briefing":     briefing,
        "generated_at": payload["generated_at"],
        "plugins":      payload["plugins"],
        "summaries":    payload["summaries"],
        "errors":       payload["errors"],
    }

    OUTPUT_FILE.write_text(json.dumps(result, ensure_ascii=False, indent=2))
    _append_log(payload, briefing)
    _write_status("ready")

    return result


def _friendly_error(tb: str, language: str = "sv") -> str:
    low = tb.lower()
    sv = language != "en"
    if any(k in low for k in ("connectionerror", "timeout", "network", "socket", "gaierror", "ssl")):
        return ("Nätverksfel – kontrollera anslutningen." if sv
                else "Network error – check your connection.")
    if "modulenotfounderror" in low or "importerror" in low:
        return ("Saknar Python-beroende – kör: pip install -r requirements.txt" if sv
                else "Missing Python dependency – run: pip install -r requirements.txt")
    return "Uppdatering misslyckades." if sv else "Update failed."


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--language", default="sv", choices=["sv", "en"])
    args = parser.parse_args()
    try:
        result = run(language=args.language)
        print(result["briefing"])
    except Exception:
        err = traceback.format_exc()
        _write_status("error", _friendly_error(err, language=args.language))
        print(f"[bridge error]\n{err}", file=sys.stderr)
        sys.exit(1)
