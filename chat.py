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
MAX_TOKENS   = 120

SYSTEM = (
    "Du är en energianalytiker. Svara på svenska. "
    "ABSOLUTA REGLER:\n"
    "1. Använd BARA siffror och fakta som finns i energidatan nedan. Hitta inte på något.\n"
    "2. Svar på frågor om spotpris, timpriser, kärnkraft-UMM och billigaste laddningstid är OK.\n"
    "3. Frågor om elavtal, rörligt pris, fast pris, elnätsavgift, slutkundspris, "
    "elbolag, kontrakt, skatter eller annat utanför spotpris/UMM/timpriser: "
    "svara exakt 'Den informationen finns inte i tillgänglig data.' — ingenting mer.\n"
    "4. MAX 2 meningar. Aldrig mer. Ingen inledning, inga parenteser."
)


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
            parts.append(
                f"SE3 spotpris — snitt: {ed['avg_price']:.1f}, "
                f"min: {ed.get('min_price', '?'):.1f}, "
                f"max: {ed.get('max_price', '?'):.1f} öre/kWh"
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
            parts.append(
                f"Billigaste 4h-fönster: {cd['cheapest_window_start']:02d}:00–"
                f"{cd['cheapest_window_end']:02d}:00 ({cd['cheapest_window_avg']:.1f} öre/kWh, "
                f"dagsnitt {cd.get('daily_avg', '?'):.1f} öre/kWh)"
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

        briefing = data.get("briefing", "")
        if briefing:
            parts.append(f"Dagens sammanfattning: {briefing}")

        return "\n".join(parts) if parts else "Ingen energidata tillgänglig."
    except Exception:
        return "Ingen energidata tillgänglig."


_OUT_OF_SCOPE = [
    "rörligt", "fast pris", "fastpris", "elavtal", "elbolag", "elleverantör",
    "elnätsavgift", "elnät", "kontrakt", "skatt", "moms", "nätavgift",
    "slutkund", "hushåll", "villa", "lägenhet", "bostad", "abonnemang",
]

def is_out_of_scope(question: str) -> bool:
    q = question.lower()
    return any(kw in q for kw in _OUT_OF_SCOPE)


def build_messages(history: list, question: str, context: str) -> list:
    """Build Mistral-compatible alternating user/assistant messages."""
    context_prefix = (
        f"{SYSTEM}\n\n"
        f"Aktuell energidata:\n{context or 'Ingen data tillgänglig.'}\n\n"
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
    parser.add_argument("--question", required=True)
    parser.add_argument("--history",  default="[]",
                        help="JSON array of {role, content} prior turns")
    args = parser.parse_args()

    try:
        history = json.loads(args.history)
    except Exception:
        history = []

    # Keep at most the last 3 complete turns (6 messages) to avoid context overflow
    # that triggers repetition loops in the model.
    if len(history) > 6:
        history = history[-6:]

    if is_out_of_scope(args.question):
        sys.stdout.write("Den informationen finns inte i tillgänglig data.")
        sys.stdout.flush()
        return

    context  = load_context()
    messages = build_messages(history, args.question, context)

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
