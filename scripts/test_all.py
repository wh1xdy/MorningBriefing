#!/usr/bin/env python3
"""
test_all.py — fast test suite for MorningBriefing Python layer.
NO MLX / model loading. Tests pure functions + live API smoke tests.

Usage:
    python scripts/test_all.py           # all tests
    python scripts/test_all.py --unit    # pure-function tests only (no network)
    python scripts/test_all.py --live    # live API smoke tests only
    python scripts/test_all.py --chat    # chat logic tests only
"""
import argparse
import json
import sys
import time
import traceback
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

PASS = "✓"
FAIL = "✗"
SKIP = "○"

results: list[tuple[str, str, str]] = []   # (status, name, detail)

_UNIT_REGISTRY: list = []
_LIVE_REGISTRY: list = []


def test(name: str):
    def decorator(fn):
        def wrapper():
            try:
                fn()
                results.append((PASS, name, ""))
            except AssertionError as e:
                results.append((FAIL, name, str(e)))
            except Exception as e:
                results.append((FAIL, name, f"{type(e).__name__}: {e}"))
        wrapper.__test_name__ = name
        _UNIT_REGISTRY.append(wrapper)
        return wrapper
    return decorator


# ─── core.py ──────────────────────────────────────────────────────────────────

@test("core: find_cheapest_window — normal case")
def _():
    from plugins.core import find_cheapest_window
    prices = [{"hour": i, "price_ore_kwh": float(50 + i)} for i in range(24)]
    s, e, avg = find_cheapest_window(prices, window=4)
    assert s == 0, f"expected start=0, got {s}"
    assert e == 4, f"expected end=4, got {e}"
    assert avg < 55, f"avg too high: {avg}"


@test("core: find_cheapest_window — low window in middle")
def _():
    from plugins.core import find_cheapest_window
    prices = [{"hour": i, "price_ore_kwh": 100.0} for i in range(24)]
    prices[10]["price_ore_kwh"] = 10.0
    prices[11]["price_ore_kwh"] = 10.0
    prices[12]["price_ore_kwh"] = 10.0
    prices[13]["price_ore_kwh"] = 10.0
    s, e, avg = find_cheapest_window(prices, window=4)
    assert s == 10, f"expected start=10, got {s}"
    assert avg < 50


@test("core: find_cheapest_window — insufficient data")
def _():
    from plugins.core import find_cheapest_window
    s, e, avg = find_cheapest_window([{"hour": 0, "price_ore_kwh": 50}], window=4)
    assert s is None and e is None and avg is None


@test("core: find_cheapest_window — hour gap (DST day)")
def _():
    from plugins.core import find_cheapest_window
    # 23 timmar — timme 02 saknas (DST spring-forward / API-hål).
    hours = [h for h in range(24) if h != 2]
    prices = [{"hour": h, "price_ore_kwh": 10.0 if h in (0, 1, 3, 4) else 100.0}
              for h in hours]
    s, e, avg = find_cheapest_window(prices, window=4)
    assert s == 0, f"expected start=0, got {s}"
    # End derives from the segment's real last hour (4 + 1), not start+window.
    assert e == 5, f"expected end=5 (gap-aware), got {e}"
    assert abs(avg - 10.0) < 0.01, f"avg={avg}"


# ─── elpris.py ────────────────────────────────────────────────────────────────

@test("elpris: _parse_entries — 15min blocks aggregated to 24h")
def _():
    from plugins.elpris import _parse_entries
    # Use +01:00 offset so the timestamps land in Stockholm local hours 0-23.
    entries = []
    for hour in range(24):
        for q in range(4):
            entries.append({
                "deliveryStart": f"2026-01-01T{hour:02d}:{q*15:02d}:00+01:00",
                "entryPerArea":  {"SE3": float((hour + 1) * 100)},   # SEK/MWh → (hour+1)*10 öre/kWh
            })
    prices = _parse_entries({"multiAreaEntries": entries}, "SE3")
    assert len(prices) == 24, f"expected 24 prices, got {len(prices)}"
    assert prices[0]["hour"] == 0
    assert abs(prices[0]["price_ore_kwh"] - 10.0) < 0.01, f"h0={prices[0]['price_ore_kwh']}"
    assert abs(prices[23]["price_ore_kwh"] - 240.0) < 0.01


@test("elpris: _parse_entries — missing area skipped")
def _():
    from plugins.elpris import _parse_entries
    entries = [
        {"deliveryStart": "2026-01-01T00:00:00+00:00", "entryPerArea": {"SE4": 100}},
    ]
    prices = _parse_entries({"multiAreaEntries": entries}, "SE3")
    assert prices == [], f"expected empty, got {prices}"


@test("elpris: _parse_entries — malformed deliveryStart skipped")
def _():
    from plugins.elpris import _parse_entries
    entries = [
        {"deliveryStart": "not-a-date", "entryPerArea": {"SE3": 100}},
    ]
    prices = _parse_entries({"multiAreaEntries": entries}, "SE3")
    assert prices == []


# ─── reaktorstatus.py ─────────────────────────────────────────────────────────

@test("reaktorstatus: _is_still_relevant — future stop")
def _():
    from plugins.reaktorstatus import _is_still_relevant
    from datetime import datetime, timezone
    now = datetime.now(timezone.utc)
    future = (now.replace(year=now.year + 1)).isoformat()
    assert _is_still_relevant([{"eventStop": future}], now)


@test("reaktorstatus: _is_still_relevant — past stop")
def _():
    from plugins.reaktorstatus import _is_still_relevant
    from datetime import datetime, timezone
    now = datetime.now(timezone.utc)
    past = "2020-01-01T00:00:00+00:00"
    assert not _is_still_relevant([{"eventStop": past}], now)


@test("reaktorstatus: _is_still_relevant — no stop means active")
def _():
    from plugins.reaktorstatus import _is_still_relevant
    from datetime import datetime, timezone
    now = datetime.now(timezone.utc)
    assert _is_still_relevant([{"eventStop": None}], now)


# ─── cron_patch.py ────────────────────────────────────────────────────────────

@test("cron_patch: malformed log line preserved verbatim, no duplicates")
def _():
    import contextlib
    import io
    import tempfile
    import cron_patch
    from datetime import datetime, timedelta
    from zoneinfo import ZoneInfo

    yesterday = (datetime.now(ZoneInfo("Europe/Stockholm")) - timedelta(days=1)).strftime("%Y-%m-%d")
    # Korrupt rad FÖRST — får inte krascha och får inte dubblera någon annan post.
    corrupt_first = '{"timestamp": "' + yesterday + 'T07:00'   # avhuggen JSON
    valid = json.dumps(
        {"timestamp": f"{yesterday}T07:00:00+02:00", "avg_price": 80.0, "actual_avg_price": None},
        ensure_ascii=False,
    )
    corrupt_last = "not json at all"

    old_log, old_fetch = cron_patch.LOG_FILE, cron_patch.fetch_actual_avg
    try:
        with tempfile.TemporaryDirectory() as td:
            log = Path(td) / "log.jsonl"
            log.write_text("\n".join([corrupt_first, valid, corrupt_last]) + "\n")
            cron_patch.LOG_FILE = log
            cron_patch.fetch_actual_avg = lambda *a, **kw: 55.5   # ingen nätverkstrafik
            with contextlib.redirect_stdout(io.StringIO()):
                cron_patch.patch_yesterday()
            lines = log.read_text().splitlines()
    finally:
        cron_patch.LOG_FILE, cron_patch.fetch_actual_avg = old_log, old_fetch

    assert len(lines) == 3, f"expected 3 lines back, got {len(lines)}: {lines}"
    assert lines[0] == corrupt_first, f"first corrupt line not preserved verbatim: {lines[0]!r}"
    assert lines[2] == corrupt_last,  f"corrupt line not preserved verbatim: {lines[2]!r}"
    patched = json.loads(lines[1])
    assert patched["actual_avg_price"] == 55.5, f"entry not patched: {patched}"


# ─── chat.py ─────────────────────────────────────────────────────────────────

@test("chat: system prompt is conversational, not a refusal bot")
def _():
    from chat import _SYSTEM
    for lang in ("sv", "en"):
        sysp = _SYSTEM[lang].lower()
        # No hard length cap or blanket refusal anymore.
        assert "max 2" not in sysp, f"{lang}: stale length cap in prompt"
        assert "information is not available" not in sysp, f"{lang}: stale refusal in prompt"
        assert "finns inte i tillgänglig data" not in sysp, f"{lang}: stale refusal in prompt"
        # But the one grounding guardrail must remain.
        assert ("hitta aldrig på" in sysp) or ("never invent" in sysp), \
            f"{lang}: missing don't-invent-numbers guardrail"


@test("chat: build_messages — no history, context injected once")
def _():
    from chat import build_messages
    msgs = build_messages([], "Vad är snittpriset?", "Snitt: 89 öre/kWh")
    assert len(msgs) == 1
    assert msgs[0]["role"] == "user"
    assert "89" in msgs[0]["content"]
    assert "Vad är snittpriset?" in msgs[0]["content"]


@test("chat: build_messages — history: context only in first user turn")
def _():
    from chat import build_messages
    history = [
        {"role": "user",      "content": "Förra frågan"},
        {"role": "assistant", "content": "Förra svaret"},
    ]
    msgs = build_messages(history, "Ny fråga?", "CONTEXT")
    # First user msg should have context, last should not
    assert "CONTEXT" in msgs[0]["content"]
    assert "CONTEXT" not in msgs[-1]["content"]
    assert msgs[-1]["content"] == "Ny fråga?"


@test("chat: build_messages — alternating roles maintained")
def _():
    from chat import build_messages
    history = [
        {"role": "user",      "content": "Q1"},
        {"role": "assistant", "content": "A1"},
        {"role": "user",      "content": "Q2"},
        {"role": "assistant", "content": "A2"},
    ]
    msgs = build_messages(history, "Q3", "ctx")
    roles = [m["role"] for m in msgs]
    for i in range(len(roles) - 1):
        assert roles[i] != roles[i+1], f"Consecutive same roles at {i}: {roles}"


# ─── Models JSON decode (Swift-facing shapes) ─────────────────────────────────

@test("models: BriefingResult JSON round-trip")
def _():
    sample = {
        "briefing":     "Test briefing.",
        "generated_at": "2026-05-31T12:00:00Z",
        "summaries":    ["summary 1"],
        "errors":       {},
        "plugins": {
            "elpris": {
                "plugin": "elpris",
                "summary": "SE3 89 öre/kWh",
                "data": {
                    "zone": "SE3", "currency": "SEK", "unit": "öre/kWh",
                    "date": "2026-05-31",
                    "prices": [{"hour": 0, "price_ore_kwh": 89.5}],
                    "tomorrow_prices": [{"hour": 0, "price_ore_kwh": 70.0}],
                    "avg_price": 89.5, "min_price": 40.0, "max_price": 142.0,
                    "endpoint_used": "https://example.com",
                }
            },
            "core": {
                "plugin": "core", "summary": "ok",
                "data": {
                    "recommendation": "Kör 10-14",
                    "cheapest_window_start": 10, "cheapest_window_end": 14,
                    "cheapest_window_avg": 41.0, "daily_avg": 89.5,
                    "daily_min": 40.0, "daily_max": 142.0, "window_hours": 4,
                }
            },
            "reaktorstatus": {
                "plugin": "reaktorstatus", "summary": "1 UMM",
                "data": {
                    "active_umms": [], "count": 1,
                    "plants": ["Forsmark Block3"],
                    "total_unavail_mw": 473,
                    "fetched_at": "2026-05-31T12:00:00+00:00",
                }
            },
            "vader": {
                "plugin": "vader", "summary": "22°C",
                "data": {
                    "current_temp_c": 22.4, "current_wind_ms": 3.5,
                    "current_cloud_pct": 81, "daily_avg_temp_c": 20.0,
                    "daily_avg_wind_ms": 2.4, "daily_avg_cloud": 75.0,
                    "wind_note": "Svag vind.", "source": "open-meteo.com",
                    "location": "Stockholm",
                }
            },
        }
    }
    # Verify it round-trips through JSON without key errors
    raw = json.dumps(sample)
    back = json.loads(raw)
    assert back["briefing"] == "Test briefing."
    assert back["plugins"]["elpris"]["data"]["tomorrow_prices"][0]["hour"] == 0
    assert back["plugins"]["core"]["data"]["cheapest_window_start"] == 10
    assert back["plugins"]["reaktorstatus"]["data"]["total_unavail_mw"] == 473


@test("models: latest.json on disk has required Swift-facing keys")
def _():
    output = Path.home() / ".morningbriefing" / "latest.json"
    if not output.exists():
        return   # no data yet — not a failure
    d = json.loads(output.read_text())
    assert "briefing" in d,     "missing briefing key"
    assert "plugins"  in d,     "missing plugins key"
    assert d["briefing"],       "briefing is empty"
    plugins = d["plugins"]
    # A snapshot written while offline has every plugin in an error state and
    # no data — that is a network condition at capture time, not a code defect.
    def _ok(name: str) -> bool:
        return name in plugins and not plugins[name].get("error")
    if _ok("elpris"):
        ed = plugins["elpris"].get("data", {})
        assert "prices"    in ed, "elpris.data missing prices"
        assert "avg_price" in ed, "elpris.data missing avg_price"
        for p in ed["prices"]:
            assert "hour"          in p, f"price missing hour: {p}"
            assert "price_ore_kwh" in p, f"price missing price_ore_kwh: {p}"
    if _ok("core"):
        cd = plugins["core"].get("data", {})
        assert "cheapest_window_start" in cd
        assert "cheapest_window_avg"   in cd
    if _ok("reaktorstatus"):
        rd = plugins["reaktorstatus"].get("data", {})
        assert "count"           in rd, "reaktorstatus missing count"
        assert "plants"          in rd, "reaktorstatus missing plants"
        assert "upcoming_count"  in rd, "reaktorstatus missing upcoming_count (new field)"
        assert "upcoming_plants" in rd, "reaktorstatus missing upcoming_plants (new field)"
        assert "total_unavail_mw" in rd


@test("chat: load_context includes prices and UMM data")
def _():
    output = Path.home() / ".morningbriefing" / "latest.json"
    if not output.exists():
        return
    d = json.loads(output.read_text())
    elpris = (d.get("plugins") or {}).get("elpris") or {}
    if elpris.get("error") or not (elpris.get("data") or {}).get("prices"):
        return   # offline snapshot — no prices to surface, not a code defect
    from chat import load_context
    ctx = load_context()
    assert ctx != "Ingen energidata tillgänglig.", f"load_context returned fallback: {ctx}"
    assert "öre/kWh" in ctx, "context missing price unit"


@test("chat: load_context — None min/max/daily_avg render as '?' (fixture)")
def _():
    import tempfile
    import chat

    fixture = {
        "briefing": "Testbriefing.",
        "plugins": {
            "elpris": {"plugin": "elpris", "data": {
                "date": "2026-07-02",
                "avg_price": 89.0, "min_price": None, "max_price": None,
                "prices": [{"hour": 0, "price_ore_kwh": 89.0}],
            }},
            "core": {"plugin": "core", "data": {
                "cheapest_window_start": 10, "cheapest_window_end": 14,
                "cheapest_window_avg": 41.0, "daily_avg": None,
            }},
        },
    }
    old = chat.CONTEXT_FILE
    try:
        with tempfile.TemporaryDirectory() as td:
            ctx_file = Path(td) / "latest.json"
            ctx_file.write_text(json.dumps(fixture, ensure_ascii=False))
            chat.CONTEXT_FILE = ctx_file
            ctx = chat.load_context()
    finally:
        chat.CONTEXT_FILE = old

    # load_context sväljer exceptions till "" — en regression i None-guarderna
    # skulle synas här som tom kontext.
    assert ctx, "load_context returned empty for a valid partial payload"
    assert "öre/kWh" in ctx, "context missing price unit"
    assert "min: ?" in ctx and "max: ?" in ctx, f"None min/max not rendered as '?': {ctx}"
    assert "dagsnitt ? öre/kWh" in ctx, f"None daily_avg not rendered as '?': {ctx}"


# ─── Live API smoke tests ─────────────────────────────────────────────────────

def live_test(name: str):
    def decorator(fn):
        def wrapper():
            try:
                fn()
                results.append((PASS, f"[live] {name}", ""))
            except Exception as e:
                results.append((FAIL, f"[live] {name}", f"{type(e).__name__}: {e}"))
        _LIVE_REGISTRY.append(wrapper)
        return wrapper
    return decorator


@live_test("elpris: fetch_prices returns 24 SE3 prices")
def live_elpris():
    from plugins.elpris import fetch_prices
    r = fetch_prices()
    assert r["plugin"] == "elpris"
    prices = r["data"]["prices"]
    assert len(prices) == 24, f"expected 24, got {len(prices)}"
    assert all(isinstance(p["price_ore_kwh"], float) for p in prices)
    assert r["data"]["avg_price"] > 0


@live_test("elpris: tomorrow_prices field present after 13:00 or None before")
def live_elpris_tomorrow():
    from plugins.elpris import fetch_prices
    from datetime import datetime
    from zoneinfo import ZoneInfo
    r = fetch_prices()
    hour = datetime.now(ZoneInfo("Europe/Stockholm")).hour
    if hour >= 13:
        assert "tomorrow_prices" in r["data"], "tomorrow_prices should be available after 13:00"
    else:
        # Either present (early publish) or absent — both fine
        pass


@live_test("reaktorstatus: fetch_umm returns valid structure")
def live_reaktor():
    from plugins.reaktorstatus import fetch_umm
    r = fetch_umm()
    assert r["plugin"] == "reaktorstatus"
    assert "count" in r["data"]
    assert isinstance(r["data"]["plants"], list)
    assert isinstance(r["data"]["total_unavail_mw"], int)


@live_test("vader: fetch_weather returns Stockholm data")
def live_vader():
    from plugins.vader import fetch_weather
    r = fetch_weather()
    assert r["plugin"] == "vader"
    assert r["data"]["location"] == "Stockholm"
    assert r["data"]["current_temp_c"] is not None
    assert isinstance(r["data"]["daily_avg_wind_ms"], float)


@live_test("core: analyze returns cheapest window")
def live_core():
    from plugins.core import analyze
    r = analyze()
    assert r["plugin"] == "core"
    d = r["data"]
    assert d["cheapest_window_start"] is not None
    assert 0 <= d["cheapest_window_start"] <= 20
    # Gap-aware end: derived from the segment's last real hour, so on a DST
    # spring-forward day (hour 02 missing) the window may span 5 clock hours.
    assert d["cheapest_window_start"] + 4 <= d["cheapest_window_end"] <= d["cheapest_window_start"] + 5, \
        f"window {d['cheapest_window_start']}–{d['cheapest_window_end']} inconsistent"


@live_test("aggregator: run_all all plugins succeed")
def live_aggregator():
    from aggregator import run_all
    payload = run_all()
    assert "generated_at" in payload
    for name in ("elpris", "reaktorstatus", "core", "vader"):
        assert name in payload["plugins"], f"missing plugin: {name}"
        assert "error" not in payload["plugins"][name] or payload["errors"].get(name) is None, \
            f"{name} failed: {payload['plugins'][name].get('error')}"


# ─── Runner ──────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser()
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--unit", action="store_true", help="Pure unit tests only (no network)")
    group.add_argument("--live", action="store_true", help="Live API tests only")
    group.add_argument("--chat", action="store_true", help="Chat logic tests only")
    args = parser.parse_args()

    to_run = []
    if args.unit:
        to_run = list(_UNIT_REGISTRY)
    elif args.live:
        to_run = list(_LIVE_REGISTRY)
    elif args.chat:
        to_run = [t for t in _UNIT_REGISTRY if "chat" in t.__test_name__]
    else:
        to_run = list(_UNIT_REGISTRY) + list(_LIVE_REGISTRY)

    t0 = time.time()
    for fn in to_run:
        fn()

    passed = sum(1 for s, _, _ in results if s == PASS)
    failed = sum(1 for s, _, _ in results if s == FAIL)

    print(f"\n{'─'*60}")
    for status, name, detail in results:
        line = f"  {status}  {name}"
        if detail:
            line += f"\n       {detail}"
        print(line)
    print(f"{'─'*60}")
    print(f"  {passed} passed  {failed} failed  ({time.time()-t0:.1f}s)")
    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()
