#!/usr/bin/env python3
"""
Chat endpoint. Called by Swift via NSTask.
Loads briefing context from latest.json, supports multi-turn history, runs MLX inference.
Usage: python chat.py --question "Varför är priset högt imorgon?" [--history '[...]']
"""
import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

CONTEXT_FILE = Path.home() / ".morningbriefing/latest.json"
MODEL_ID     = "mlx-community/Mistral-7B-Instruct-v0.3-4bit"
MAX_TOKENS   = 340   # room for a natural, complete answer

_SYSTEM = {
    "sv": (
        "Du är en hjälpsam och vänlig assistent i appen MorningBriefing, som handlar om "
        "den nordiska elmarknaden – SE3-spotpriser, billigaste timmar, kärnkraftstatus och väder. "
        "Prata naturligt och avslappnat: hälsa tillbaka och förklara gärna vad du kan hjälpa till med. "
        "Vid hälsningar och småprat, svara kort och vänligt – rabbla INTE upp all data om "
        "användaren inte frågat efter den. "
        "Den enda hårda regeln: konkreta fakta – siffror, datum, MW och dina datakällor – får BARA "
        "komma från energidatan nedan. Hitta aldrig på siffror, datum eller källor. "
        "Saknar du en uppgift, säg det ärligt istället för att gissa. Svara på svenska."
    ),
    "en": (
        "You are a helpful, friendly assistant inside the MorningBriefing app, which is about the "
        "Nordic electricity market – SE3 spot prices, cheapest hours, nuclear status and weather. "
        "Talk naturally and conversationally: greet back and feel free to explain what you can help with. "
        "For greetings and small talk, reply briefly and warmly – do NOT dump all the data unless the "
        "user asked for it. "
        "The one hard rule: concrete facts – numbers, dates, MW and your data sources – may come ONLY "
        "from the energy data below. Never invent figures, dates or sources. "
        "If you lack a detail, say so honestly instead of guessing. Reply in English."
    ),
}


def load_context() -> str:
    if not CONTEXT_FILE.exists():
        return "Ingen energidata tillgänglig."
    try:
        data = json.loads(CONTEXT_FILE.read_text())
        parts = []

        elpris = (data.get("plugins") or {}).get("elpris") or {}
        ed = elpris.get("data") or {}
        if ed.get("date"):
            parts.append(f"Datum: {ed['date']}")
        if ed.get("avg_price") is not None:
            mn, mx = ed.get("min_price"), ed.get("max_price")
            parts.append(
                f"SE3 spotpris — snitt: {ed['avg_price']:.1f}, "
                f"min: {f'{mn:.1f}' if mn is not None else '?'}, "
                f"max: {f'{mx:.1f}' if mx is not None else '?'} öre/kWh"
            )
        prices = ed.get("prices") or []
        if prices:
            rows = "  ".join(f"{p['hour']:02d}:{p['price_ore_kwh']:.0f}" for p in prices)
            parts.append(f"Timpriser (timme:öre/kWh): {rows}")
        tomorrow = ed.get("tomorrow_prices") or []
        if tomorrow:
            rows = "  ".join(f"{p['hour']:02d}:{p['price_ore_kwh']:.0f}" for p in tomorrow)
            parts.append(f"Morgondagens timpriser: {rows}")

        core = (data.get("plugins") or {}).get("core") or {}
        cd = core.get("data") or {}
        if cd.get("cheapest_window_start") is not None:
            davg = cd.get("daily_avg")
            parts.append(
                f"Billigaste 4h-fönster: {cd['cheapest_window_start']:02d}:00–"
                f"{cd['cheapest_window_end']:02d}:00 ({cd['cheapest_window_avg']:.1f} öre/kWh, "
                f"dagsnitt {f'{davg:.1f}' if davg is not None else '?'} öre/kWh)"
            )

        reaktor = (data.get("plugins") or {}).get("reaktorstatus") or {}
        rd = reaktor.get("data") or {}
        active_count   = rd.get("count", 0)
        upcoming_count = rd.get("upcoming_count", 0)
        if active_count == 0 and upcoming_count == 0:
            parts.append("Nukleär UMM: inga pågående eller planerade driftstörningar.")
        else:
            if active_count > 0 and rd.get("plants"):
                mw = rd.get("total_unavail_mw")
                plants = ", ".join(rd["plants"])
                parts.append(
                    f"Nukleär UMM aktiv ({active_count} st): {plants}"
                    + (f" — {mw} MW otillgängliga" if mw else "")
                )
            if upcoming_count > 0 and rd.get("upcoming_plants"):
                up = ", ".join(rd["upcoming_plants"])
                parts.append(f"Nukleär UMM planerad ({upcoming_count} st): {up}")

        # Vattenfall live production
        vf = (data.get("plugins") or {}).get("vattenfall") or {}
        vd = vf.get("data") or {}
        if vd.get("blocks"):
            block_rows = "  ".join(
                f"{b['block']}:{'offline' if b['offline'] else str(b['production_mw'])+'MW'}"
                for b in vd["blocks"]
            )
            offline = vd.get("offline") or []
            if offline:
                parts.append(f"Forsmark realtidsproduktion (Vattenfall): {block_rows}. Offline: {', '.join(offline)}")
            else:
                parts.append(f"Forsmark realtidsproduktion (Vattenfall): {block_rows}. Alla block i drift.")

        briefing = data.get("briefing", "")
        if briefing:
            parts.append(f"Dagens sammanfattning: {briefing}")

        # Ground the "what are your sources?" question so the model doesn't invent.
        parts.append(
            "Datakällor: Nord Pool Day-Ahead (SE3 spotpriser), Nord Pool UMM "
            "(kärnkraft-driftstörningar), Open-Meteo (väder i Stockholm), Vattenfall "
            "(Forsmark realtidsproduktion). Briefingtexten skrivs av en lokal Mistral-7B-modell."
        )

        return "\n".join(parts) if parts else "Ingen energidata tillgänglig."
    except Exception:
        return "Ingen energidata tillgänglig."


def build_messages(history: list, question: str, context: str, lang: str = "sv") -> list:
    """Build Mistral-compatible alternating user/assistant messages."""
    system = _SYSTEM.get(lang, _SYSTEM["sv"])
    data_label = "Current energy data:" if lang == "en" else "Aktuell energidata:"
    context_prefix = (
        f"{system}\n\n"
        f"{data_label}\n{context or ('No data available.' if lang == 'en' else 'Ingen data tillgänglig.')}\n\n"
    )

    messages = []
    for i, msg in enumerate(history):
        role    = msg.get("role", "user")
        content = msg.get("content", "")
        if role == "user":
            # Prepend context only into the very first user turn
            content = (context_prefix + content) if i == 0 else content
            messages.append({"role": "user", "content": content})
        else:
            messages.append({"role": "assistant", "content": content})

    # Current question
    if messages:
        messages.append({"role": "user", "content": question})
    else:
        messages.append({"role": "user", "content": context_prefix + question})

    return messages


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--question",  required=True)
    parser.add_argument("--history",   default="[]")
    parser.add_argument("--language",  default="sv", choices=["sv", "en"])
    args = parser.parse_args()

    try:
        history = json.loads(args.history)
    except Exception:
        history = []

    if len(history) > 6:
        history = history[-6:]

    context  = load_context()
    messages = build_messages(history, args.question, context, lang=args.language)

    from mlx_lm import load, stream_generate
    from mlx_lm.sample_utils import make_sampler, make_logits_processors
    model, tokenizer = load(MODEL_ID)

    prompt = tokenizer.apply_chat_template(
        messages, tokenize=False, add_generation_prompt=True
    )
    sampler   = make_sampler(temp=0.4)
    logit_fns = make_logits_processors(repetition_penalty=1.3)
    for response in stream_generate(
        model, tokenizer, prompt=prompt,
        max_tokens=MAX_TOKENS,
        sampler=sampler,
        logits_processors=logit_fns,
    ):
        sys.stdout.write(response.text)
        sys.stdout.flush()


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        sys.stderr.write(str(e) + "\n")
        sys.exit(1)
