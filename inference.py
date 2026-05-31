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

# Mistral 7B follows late-in-prompt instructions most reliably.
# Put the RULES block last so they're fresh in context at generation time.
_RULES = (
    "REGLER: Skriv 3–5 meningar sammanhängande prosa på svenska. "
    "Inga punktlistor, inga rubriker, ingen inledningsfras. "
    "Börja direkt med ett faktapåstående. "
    "Avsluta sista meningen med: 'Kör tunga jobb HH:00–HH:00 (XX öre/kWh).'"
)


def build_user_prompt(payload: dict) -> str:
    plugins   = payload.get("plugins", {})
    elpris    = plugins.get("elpris",        {}).get("data", {})
    core      = plugins.get("core",          {}).get("data", {})
    reaktor   = plugins.get("reaktorstatus", {}).get("data", {})
    vader     = plugins.get("vader",         {}).get("data", {})

    facts = []

    # Price facts
    avg = elpris.get("avg_price")
    mn  = elpris.get("min_price")
    mx  = elpris.get("max_price")
    date = elpris.get("date", "idag")
    if avg is not None:
        facts.append(f"SE3 spotpris {date}: snitt {avg:.1f}, min {mn:.1f}, max {mx:.1f} öre/kWh.")

    # Cheapest window
    if core.get("cheapest_window_start") is not None:
        s = core["cheapest_window_start"]
        e = core["cheapest_window_end"]
        ca = core["cheapest_window_avg"]
        da = core.get("daily_avg", avg or 0)
        pct = round((da - ca) / max(da, 0.01) * 100, 1)
        facts.append(f"Billigaste 4h-fönster: {s:02d}:00–{e:02d}:00 ({ca:.1f} öre/kWh, {pct}% under dagsnitt).")

    # Nuclear UMMs
    umms = reaktor.get("active_umms") or []
    if umms:
        for u in umms:
            end = (u.get("event_end") or "okänt datum")[:10]
            facts.append(
                f"Nukleär UMM: {u['plant']} ({u['zone']}) har {u.get('unavailable_mw', '?')} MW "
                f"otillgängliga t.o.m. {end}."
            )
    else:
        facts.append("Inga aktiva nukleära UMM just nu.")

    # Wind/weather context
    wind = vader.get("daily_avg_wind_ms")
    if wind is not None:
        facts.append(f"Vindsnitt Stockholm idag: {wind} m/s. {vader.get('wind_note', '')}")

    context = "\n".join(facts)
    return f"Energidata:\n{context}\n\n{_RULES}"


def generate_briefing(payload: dict) -> str:
    from mlx_lm import load, generate

    model, tokenizer = load(MODEL_ID)

    # Mistral v0.3 has no system role — put all instructions in the user turn.
    messages = [{"role": "user", "content": build_user_prompt(payload)}]

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
