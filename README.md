# MorningBriefing

A macOS menu bar app that gives you a daily briefing on the Nordic electricity
market: SE3 spot prices, the cheapest hours to run heavy loads, nuclear plant
status, live Forsmark production, and Stockholm weather. The briefing text is
composed deterministically from the data; the in-app chat is answered locally
by a quantized Mistral 7B model running on Apple MLX. No market data or
questions leave the machine.

The app targets a single user who wants to know, at a glance each morning, when
power is cheap and what is moving the price.

## How it works

The system has two halves: a Python data and inference layer, and a SwiftUI menu
bar app. They communicate through a single JSON file.

```
Public APIs
     |
     v
  plugins/    ->  aggregator.py  ->  inference.py  ->  ~/.morningbriefing/latest.json
  (fetch)         (run parallel)     (compose text)              |
                                                                 |  file watched
                                                                 v
                                              MorningBriefingApp menu bar popover
```

1. Each plugin in `plugins/` fetches one slice of data from a public API.
2. `aggregator.py` runs the plugins in parallel and isolates failures, so one
   dead API degrades the briefing rather than breaking it.
3. `inference.py` composes a short Swedish or English briefing from the
   aggregated facts using templates: price level and daily shape, nuclear
   outages, tomorrow's direction, wind, and the run-heavy-loads
   recommendation. It is deterministic on purpose — an earlier version
   generated the text with the local model, which was slow every morning and
   occasionally misread planned outages as permanent shutdowns. The model is
   reserved for chat, where open-ended interpretation earns its latency.
4. `bridge.py` ties the pipeline together and writes the result to
   `~/.morningbriefing/latest.json`.
5. The Swift app watches that file and renders the briefing, a price chart, and
   a set of cards. It also drives `chat.py` for follow-up questions.

## Components

### Data plugins (`plugins/`)

| Plugin             | Source                                  | Provides                                                        |
| ------------------ | --------------------------------------- | --------------------------------------------------------------- |
| `elpris.py`        | Nord Pool Day-Ahead API (no auth)       | SE3 hourly spot prices, daily average, min and max              |
| `reaktorstatus.py` | Nord Pool UMM API (no auth)             | Nordic nuclear outages, split into active and upcoming          |
| `vader.py`         | Open-Meteo (no key)                     | Stockholm temperature, wind, and cloud cover                    |
| `vattenfall.py`    | karnkraft.vattenfall.se (scraped JSON)  | Live Forsmark F1/F2/F3 production in MW                         |
| `core.py`          | derived from `elpris.py`                | Cheapest four-hour window and the recommendation                |

The Vattenfall plugin exists because the Nord Pool UMM API reports market
messages but not routine annual maintenance, so a reactor can be offline without
an outage message. Scraping Vattenfall's public production page fills that gap.

### Pipeline and inference

| File                | Role                                                                          |
| ------------------- | ----------------------------------------------------------------------------- |
| `aggregator.py`     | Runs all plugins in parallel and returns a combined payload.                  |
| `inference.py`      | Composes the briefing text from the data (deterministic, Swedish or English). |
| `chat.py`           | Answers follow-up questions with the local MLX model, grounded in the data.   |
| `bridge.py`         | Full pipeline entry point; writes `latest.json` and a status file.            |
| `cron_patch.py`     | Nightly job that backfills the log with the day's actual prices.              |

### Menu bar app (`MorningBriefingApp/`)

A Swift Package targeting macOS 26, built around `NSStatusItem` and a transient
`NSPopover`. Key files live in `Sources/MorningBriefingApp/`:

| File                     | Role                                                              |
| ------------------------ | ----------------------------------------------------------------- |
| `AppDelegate.swift`      | Status item, popover lifecycle, wake-from-sleep trigger.          |
| `ContentView.swift`      | Briefing, chat, and the morning greeting screen.                  |
| `SettingsView.swift`     | Settings screen: language picker, model and data-source info.     |
| `BriefingViewModel.swift`| Runs `bridge.py`, watches `latest.json`, tracks connectivity.     |
| `ChatViewModel.swift`    | Runs `chat.py` and streams replies.                               |
| `PriceChartView.swift`   | Hourly price chart with a hover crosshair.                        |
| `Models.swift`           | Codable types matching the JSON written by the Python layer.      |

The interface uses the native macOS 26 Liquid Glass material throughout and is
fully localized in Swedish and English.

## Requirements

- macOS 26 or later (required for the Liquid Glass APIs).
- A Swift toolchain (Xcode 26 or the matching command-line tools).
- Python 3.11 or later. Developed and run on Python 3.14.
- Roughly 4 GB of disk for the chat model, which downloads on first use.

Python dependencies are listed in `requirements.txt`:

- `requests` for the data plugins.
- `mlx-lm` for local chat inference on Apple silicon.

## Setup

```sh
git clone https://github.com/wh1xdy/MorningBriefing.git
cd MorningBriefing
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

## Running

### Generate a briefing

```sh
.venv/bin/python bridge.py --language sv      # or --language en
```

This fetches all sources, composes the briefing, and writes the result to
`~/.morningbriefing/latest.json`. It completes in a few seconds — the language
model is not involved.

### Refresh data during UI work

The fixture injector runs the same plugins and composer but skips the log
append and status-file choreography. Useful for quick iteration, or to force
a specific briefing text:

```sh
.venv/bin/python scripts/inject_fixture.py
.venv/bin/python scripts/inject_fixture.py --briefing "Custom text."
```

### Ask a question

```sh
.venv/bin/python chat.py --question "Varför är priset högt ikväll?" --language sv
```

This is the only command that loads the Mistral model (and the only heavy
CPU/GPU user).

### Build and run the app

```sh
cd MorningBriefingApp
swift build
.build/debug/MorningBriefingApp
```

Alternatively, open `MorningBriefingApp/Package.swift` in Xcode and run from
there. The app installs itself as a menu bar item with no Dock icon.

### Tests

```sh
.venv/bin/python scripts/test_all.py --unit     # offline unit tests, no model
.venv/bin/python scripts/test_all.py --live     # live API smoke tests
```

## Scheduling

Two recurring jobs are useful in production:

- A morning run of `bridge.py` so the briefing is ready when you wake.
- A nightly run of `cron_patch.py` to backfill actual prices into the log.

`com.alexanderwh.morningbriefing.cronpatch.plist` is a launchd template for the
nightly job only. Adjust the absolute paths to your checkout, copy it into
`~/Library/LaunchAgents/`, then load it with `launchctl load`.

For the morning run, make a second copy of the template: change the `Label` to
`com.alexanderwh.morningbriefing.bridge`, point `ProgramArguments` at
`bridge.py` with `--language sv` (or `en`), and set `StartCalendarInterval` to
a time shortly before you wake. Save it as
`com.alexanderwh.morningbriefing.bridge.plist` and load it the same way.

## Configuration

- Language is selected in the app's settings (Swedish or English) and passed
  through to the Python layer with the `--language` flag.
- All runtime state lives in `~/.morningbriefing/`: `latest.json` (the current
  briefing), `status.json` (pipeline progress), and `log.jsonl` (history).

## Data sources

- Nord Pool Day-Ahead prices and Urgent Market Messages.
- Open-Meteo weather.
- Vattenfall Forsmark production data.
- Mistral 7B Instruct v0.3 (4-bit), run locally via the MLX community build
  (chat only).

## Project layout

```
MorningBriefing/
├── plugins/              Data fetchers, one per source
├── aggregator.py         Parallel plugin runner
├── inference.py          Deterministic briefing composer
├── chat.py               Grounded question answering (local MLX model)
├── bridge.py             Full pipeline entry point
├── cron_patch.py         Nightly price backfill
├── scripts/
│   ├── inject_fixture.py Quick data refresh (no log or status files)
│   └── test_all.py       Unit and live tests
└── MorningBriefingApp/   SwiftUI menu bar app
```
