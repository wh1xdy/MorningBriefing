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
MAX_TOKENS   = 250

SYSTEM = (
    "Du är en kortfattad energianalytiker för den nordiska elmarknaden. "
    "Svara ALLTID på ren svenska oavsett vilket språk frågan ställs på. "
    "Skriv ALDRIG engelska ord eller fraser, inte ens inom parentes. "
    "Rätt svenska facktermer: 'otillgänglig', 'kärnkraftsblock', 'effekt', "
    "'priszon', 'oplanerat driftstopp', 'vindkraft', 'vattenkraft'. "
    "Max 3 meningar. Faktabaserad. Ingen inledning, ingen hälsningsfras, inga parenteser."
)


def load_context() -> str:
    if not CONTEXT_FILE.exists():
        return ""
    try:
        data = json.loads(CONTEXT_FILE.read_text())
        parts = []
        # elpris summary
        elpris = (data.get("plugins") or {}).get("elpris") or {}
        ed = (elpris.get("data") or {})
        if ed.get("avg_price"):
            parts.append(f"SE3 spotpris snitt: {ed['avg_price']:.1f} öre/kWh")
        if ed.get("min_price") and ed.get("max_price"):
            parts.append(f"Min: {ed['min_price']:.1f}, Max: {ed['max_price']:.1f} öre/kWh")
        # core recommendation
        core = (data.get("plugins") or {}).get("core") or {}
        cd = (core.get("data") or {})
        if cd.get("cheapest_window_start") is not None:
            parts.append(
                f"Billigast 4-timmarsperiod: {cd['cheapest_window_start']:02d}:00–"
                f"{cd['cheapest_window_end']:02d}:00 ({cd['cheapest_window_avg']:.1f} öre/kWh)"
            )
        # reaktor
        reaktor = (data.get("plugins") or {}).get("reaktorstatus") or {}
        rd = (reaktor.get("data") or {})
        if rd.get("plants"):
            mw = rd.get("total_unavail_mw")
            plants = ", ".join(rd["plants"])
            parts.append(
                f"Nukleär UMM: {plants}"
                + (f" ({mw} MW otillgängliga)" if mw else "")
            )
        # briefing text
        briefing = data.get("briefing", "")
        if briefing:
            parts.append(f"Sammanfattning: {briefing}")
        return "\n".join(parts)
    except Exception:
        return ""


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

    context  = load_context()
    messages = build_messages(history, args.question, context)

    from mlx_lm import load, stream_generate
    model, tokenizer = load(MODEL_ID)

    prompt = tokenizer.apply_chat_template(
        messages, tokenize=False, add_generation_prompt=True
    )
    for chunk in stream_generate(
        model, tokenizer, prompt=prompt,
        max_tokens=MAX_TOKENS,
        temp=0.7, repetition_penalty=1.3,
    ):
        sys.stdout.write(chunk)
        sys.stdout.flush()


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        sys.stderr.write(str(e) + "\n")
        sys.exit(1)
