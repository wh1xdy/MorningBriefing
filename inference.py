#!/usr/bin/env python3
"""
Local MLX inference using Mistral-7B-Instruct-v0.3-4bit.
Accepts aggregator JSON (stdin or dict), returns a 3-5 sentence Swedish briefing.
Model is loaded once and cached for the process lifetime.
"""
import json
import sys
from pathlib import Path

MODEL_ID   = "mlx-community/Mistral-7B-Instruct-v0.3-4bit"
MAX_TOKENS = 280

_RULES = {
    "sv": (
        "REGLER: Skriv 3–5 meningar sammanhängande prosa på svenska. "
        "Inga punktlistor, inga rubriker, ingen inledningsfras. "
        "Börja direkt med ett faktapåstående. "
        "Avsluta sista meningen med: 'Kör tunga jobb HH:00–HH:00 (XX öre/kWh).'"
    ),
    "en": (
        "RULES: Write 3–5 sentences of continuous prose in English. "
        "No bullet lists, no headings, no preamble. "
        "Start directly with a factual statement. "
        "End the last sentence with: 'Run heavy loads HH:00–HH:00 (XX öre/kWh).'"
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
        up_names = ", ".join(u["plant"] for u in upcoming)
        facts.append(
            f"Nuclear UMM (planned): {up_names}."
            if not sv else
            f"Nukleär UMM (planerad): {up_names}."
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

    model, tokenizer = load(MODEL_ID)

    messages = [{"role": "user", "content": build_user_prompt(payload, language=language)}]

    prompt = tokenizer.apply_chat_template(
        messages,
        tokenize=False,
        add_generation_prompt=True,
    )

    response = generate(
        model,
        tokenizer,
        prompt=prompt,
        max_tokens=MAX_TOKENS,
        verbose=False,
        temp=0.3,            # low temp for factual prose
        repetition_penalty=1.2,
    )

    return response.strip()


if __name__ == "__main__":
    if len(sys.argv) > 1:
        payload = json.loads(Path(sys.argv[1]).read_text())
    else:
        payload = json.load(sys.stdin)

    briefing = generate_briefing(payload)
    print(briefing)
