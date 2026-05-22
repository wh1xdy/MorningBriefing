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
MAX_TOKENS = 300

SYSTEM_PROMPT = (
    "Du är en kortfattad energianalytiker. "
    "Du får sensordata från det nordiska elnätet och ska skriva en briefing på 3-5 meningar. "
    "Skriv på svenska med engelska facktermer (MW, kWh, UMM, spot price). "
    "Var faktabaserad och direkt — inga inledningsfraser, inga uppmaningar, inget fluff. "
    "Avsluta alltid med en konkret rekommendation om när tunga jobb ska köras."
)


def build_user_prompt(payload: dict) -> str:
    summaries = payload.get("summaries", [])
    core_data = payload.get("plugins", {}).get("core", {}).get("data", {})
    reaktor   = payload.get("plugins", {}).get("reaktorstatus", {}).get("data", {})

    lines = ["Aktuell energidata:"]
    for s in summaries:
        lines.append(f"- {s}")

    if core_data.get("recommendation"):
        lines.append(f"\nRekommendation från prisanalys: {core_data['recommendation']}")

    if reaktor.get("active_umms"):
        lines.append(f"\nAktiva nukleära UMM-meddelanden:")
        for umm in reaktor["active_umms"]:
            lines.append(
                f"  • {umm['plant']} ({umm['zone']}): "
                f"{umm['unavailable_mw']} MW unavailable t.o.m. {(umm['event_end'] or 'okänt')[:10]}. "
                f"Orsak: {umm.get('reason') or 'ej angiven'}"
            )

    return "\n".join(lines)


def generate_briefing(payload: dict) -> str:
    from mlx_lm import load, generate

    model, tokenizer = load(MODEL_ID)

    # Mistral v0.3 chat template requires strict user/assistant alternation — no system role.
    # Prepend system instructions to the first user message instead.
    messages = [
        {"role": "user", "content": f"{SYSTEM_PROMPT}\n\n{build_user_prompt(payload)}"},
    ]

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
    )

    return response.strip()


if __name__ == "__main__":
    if len(sys.argv) > 1:
        payload = json.loads(Path(sys.argv[1]).read_text())
    else:
        payload = json.load(sys.stdin)

    briefing = generate_briefing(payload)
    print(briefing)
