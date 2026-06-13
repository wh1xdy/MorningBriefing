#!/usr/bin/env python3
"""
Local MLX inference using Mistral-7B-Instruct-v0.3-4bit.
Accepts aggregator JSON (stdin or dict), returns a 3-5 sentence Swedish briefing.
Model is loaded once and cached for the process lifetime.
"""
import json
import re
import sys
from pathlib import Path

MODEL_ID   = "mlx-community/Mistral-7B-Instruct-v0.3-4bit"
MAX_TOKENS = 420   # Swedish tokenizes ~1.5× English; 280 truncated the 3–5 sentence briefing

_RULES = {
    "sv": (
        "REGLER: Skriv 3–4 meningar sammanhängande prosa på svenska. "
        "Inga punktlistor, inga rubriker, ingen inledningsfras. "
        "Börja direkt med ett faktapåstående. "
        "Skriv INGEN rekommendation om när man ska köra tunga jobb – den läggs till automatiskt."
    ),
    "en": (
        "RULES: Write 3–4 sentences of continuous prose in English. "
        "No bullet lists, no headings, no preamble. "
        "Start directly with a factual statement. "
        "Do NOT write any recommendation about when to run heavy loads – it is appended automatically."
    ),
}


def build_user_prompt(payload: dict, language: str = "sv") -> str:
    plugins   = payload.get("plugins", {})
    elpris    = plugins.get("elpris",        {}).get("data", {})
    core      = plugins.get("core",          {}).get("data", {})
    reaktor   = plugins.get("reaktorstatus", {}).get("data", {})
    vader     = plugins.get("vader",         {}).get("data", {})

    sv = language == "sv"
    facts = []

    avg  = elpris.get("avg_price")
    mn   = elpris.get("min_price")
    mx   = elpris.get("max_price")
    date = elpris.get("date", "today" if not sv else "idag")
    if avg is not None:
        facts.append(
            f"SE3 spot price {date}: avg {avg:.1f}, min {mn:.1f}, max {mx:.1f} öre/kWh."
            if not sv else
            f"SE3 spotpris {date}: snitt {avg:.1f}, min {mn:.1f}, max {mx:.1f} öre/kWh."
        )

    if core.get("cheapest_window_start") is not None:
        s  = core["cheapest_window_start"]
        e  = core["cheapest_window_end"]
        ca = core["cheapest_window_avg"]
        da = core.get("daily_avg", avg or 0)
        pct = round((da - ca) / max(da, 0.01) * 100, 1)
        facts.append(
            f"Cheapest 4h window: {s:02d}:00–{e:02d}:00 ({ca:.1f} öre/kWh, {pct}% below daily avg)."
            if not sv else
            f"Billigaste 4h-fönster: {s:02d}:00–{e:02d}:00 ({ca:.1f} öre/kWh, {pct}% under dagsnitt)."
        )

    umms = reaktor.get("active_umms") or []
    upcoming = reaktor.get("upcoming_umms") or []
    if umms:
        for u in umms:
            end = (u.get("event_end") or ("unknown date" if not sv else "okänt datum"))[:10]
            facts.append(
                f"Nuclear UMM (active): {u['plant']} ({u['zone']}) has {u.get('unavailable_mw','?')} MW unavailable until {end}."
                if not sv else
                f"Nukleär UMM (aktiv): {u['plant']} ({u['zone']}) har {u.get('unavailable_mw','?')} MW otillgängliga t.o.m. {end}."
            )
    if upcoming:
        # Dedup by plant, keep earliest start date so the model can't read
        # "planned" as "under construction".
        earliest: dict[str, str] = {}
        for u in upcoming:
            p = u["plant"]
            start = (u.get("event_start") or "")[:10]
            if p not in earliest or (start and start < earliest[p]):
                earliest[p] = start
        for p, start in sorted(earliest.items()):
            when_en = f" starting {start}" if start else ""
            when_sv = f" från {start}" if start else ""
            facts.append(
                f"Operating nuclear reactor with a planned upcoming outage: {p}{when_en} (running normally now)."
                if not sv else
                f"Kärnreaktor i drift med planerat kommande avbrott: {p}{when_sv} (i normal drift just nu)."
            )
    if not umms and not upcoming:
        facts.append("No nuclear UMMs right now." if not sv else "Inga nukleära UMM just nu.")

    wind = vader.get("daily_avg_wind_ms")
    if wind is not None:
        note = vader.get("wind_note", "")
        facts.append(
            f"Daily avg wind Stockholm: {wind} m/s. {note}"
            if not sv else
            f"Vindsnitt Stockholm idag: {wind} m/s. {note}"
        )

    label   = "Energy data:" if not sv else "Energidata:"
    context = "\n".join(facts)
    rules   = _RULES.get(language, _RULES["sv"])
    return f"{label}\n{context}\n\n{rules}"


def generate_briefing(payload: dict, language: str = "sv") -> str:
    from mlx_lm import load, generate
    from mlx_lm.sample_utils import make_sampler, make_logits_processors

    model, tokenizer = load(MODEL_ID)

    messages = [{"role": "user", "content": build_user_prompt(payload, language=language)}]

    prompt = tokenizer.apply_chat_template(
        messages,
        tokenize=False,
        add_generation_prompt=True,
    )

    sampler   = make_sampler(temp=0.3)            # low temp for factual prose
    logit_fns = make_logits_processors(repetition_penalty=1.2)
    response = generate(
        model,
        tokenizer,
        prompt=prompt,
        max_tokens=MAX_TOKENS,
        verbose=False,
        sampler=sampler,
        logits_processors=logit_fns,
    )

    body = _strip_model_recommendation(response.strip(), language)
    return (body + _recommendation_sentence(payload, language)).rstrip()


def _strip_model_recommendation(text: str, language: str = "sv") -> str:
    """Mistral-7B ignores 'write no recommendation' and tacks on its own line
    with unreliable numbers. Drop any sentence that mentions running loads so
    the deterministic appended line is the only recommendation."""
    markers = ("heavy load", "run heavy") if language != "sv" else ("tunga jobb", "tung last")
    sentences = re.split(r"(?<=[.!?])\s+", text)
    kept = [s for s in sentences if not any(m in s.lower() for m in markers)]
    return " ".join(kept).strip()


def _recommendation_sentence(payload: dict, language: str = "sv") -> str:
    """Deterministic closing recommendation — the model parrots exact numbers
    unreliably, so we append this from core data instead of generating it."""
    core = payload.get("plugins", {}).get("core", {}).get("data", {})
    s, e, ca = core.get("cheapest_window_start"), core.get("cheapest_window_end"), core.get("cheapest_window_avg")
    if s is None or e is None or ca is None:
        return ""
    return (
        f" Run heavy loads {s:02d}:00–{e:02d}:00 ({ca:.1f} öre/kWh)."
        if language != "sv" else
        f" Kör tunga jobb {s:02d}:00–{e:02d}:00 ({ca:.1f} öre/kWh)."
    )


if __name__ == "__main__":
    if len(sys.argv) > 1:
        payload = json.loads(Path(sys.argv[1]).read_text())
    else:
        payload = json.load(sys.stdin)

    briefing = generate_briefing(payload)
    print(briefing)
