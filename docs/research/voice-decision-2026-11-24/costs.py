#!/usr/bin/env python3
"""DateWise AI voice cost model. Run: python3 costs.py  (writes costs.json and COSTS.md tables to stdout).
Every price is a list price read 2026-11-24 (sources in COMPARISON.md). Edit ASSUMPTIONS, re-run."""
import json, math, os, sys

PRICE = 19.99
CHARS_PER_MIN = 900            # given: ~150 wpm EN / 140 wpm ES, ~6 chars/word incl. space
MINUTES = [15, 30, 60, 120, 300]
APPLE = {"15%": 0.15, "30%": 0.30}
# Text AI per subscriber, AI_COST_MODEL.md (Llama 3.3 70B list price): typical $0.00126/msg, heavy $0.00193/msg,
# typical profile total $0.32, heavy $2.31. A voice minute = ~2 chat turns (ASSUMPTION in that model).
TURNS_PER_MIN = 2
TEXT_PER_MSG = 0.00126
TEXT_FLOOR_TYPICAL = 0.32
TEXT_HEAVY = 2.31
AVATAR = [0.0, 1.50]
BUDGET = (4.0, 5.0)

# Self-hosting inputs
CPU_SERVER_MONTH = 40.0        # ASSUMPTION: 4 vCPU dedicated-class server; Hetzner General Purpose starts EUR 36.99 (page, 2026-11-24)
GPU_4090_HOUR = 0.34           # RunPod community RTX 4090 (costs-capacity.md, 2026-11-24); Secure $0.89
HOURS_MONTH = 730
DUTY = 0.25                    # ASSUMPTION: fraction of server time actually synthesising (peak/average smoothing)

VCPUS = 4
rtf = 0.72   # fallback: CPU-seconds per audio-second per vCPU, measured below
cp = os.path.join(os.path.dirname(os.path.abspath(__file__)), "samples", "kokoro_cpu_time.json")
if os.path.exists(cp):
    runs = json.load(open(cp))
    rtf = round(sorted(r["cpu_per_audio"] for r in runs)[len(runs) // 2], 3)  # median, 1 thread, this CPU

def per_min_from_1k(p1k): return p1k * CHARS_PER_MIN / 1000
def per_min_from_1M(p1M): return p1M * CHARS_PER_MIN / 1e6

# name: dict(per_min, floor_month (fixed $/month regardless of use), free_chars_month (service-wide), note)
OPTS = {
 "System voice (today)":               dict(per_min=0.0, note="flutter_tts/AVSpeechSynthesizer; no cost, no data leaves phone"),
 "CF Workers AI Aura-2 (en+es)":       dict(per_min=per_min_from_1k(0.030), note="$0.030/1k chars via existing env.AI binding; 10k neurons/day free shared with chat (~3.6k chars/day)"),
 "Deepgram Aura-2 direct":             dict(per_min=per_min_from_1k(0.027), note="$0.027/1k Growth, $0.030 PAYG; $200 one-off credit; needs account"),
 "Azure Neural (Dalia/Jorge, Jenny/Guy)": dict(per_min=per_min_from_1M(15.0), free_chars=500_000, note="$15/1M; F0 free 0.5M chars/month (~555 min, whole service)"),
 "Azure Neural HD (DragonHD/MAI)":     dict(per_min=per_min_from_1M(22.0), note="$22/1M (Neural HD meter, retail API 2026-11-24)"),
 "Google Chirp 3 HD (es-US, no es-MX)": dict(per_min=per_min_from_1M(30.0), free_chars=1_000_000, note="$30/1M; free 1M chars/month"),
 "Google Neural2":                     dict(per_min=per_min_from_1M(16.0), free_chars=1_000_000, note="$16/1M; free 1M chars/month"),
 "Amazon Polly Neural (Mia/Andres)":   dict(per_min=per_min_from_1M(16.0), free_chars=1_000_000, note="$16/1M; free 1M/month for first 12 months only"),
 "Amazon Polly Generative (Mia/Andres)": dict(per_min=per_min_from_1M(30.0), free_chars=100_000, note="$30/1M; free 100k/month first 12 months"),
 "OpenAI gpt-4o-mini-tts":             dict(per_min=0.015, note="~$0.015/min is OpenAI's own estimate (token-billed: $0.60/M in, $12/M audio out)"),
 "ElevenLabs Flash v2.5 (API list)":   dict(per_min=per_min_from_1k(0.04), note="$0.04/1k; commercial licence needs Starter $6/mo+; free plan not commercial"),
 "ElevenLabs Multilingual v2":         dict(per_min=per_min_from_1k(0.08), note="$0.08/1k"),
 "Cartesia Sonic (Startup plan rate)": dict(per_min=per_min_from_1M(49/1.25), floor=49.0, note="$49/mo includes 1.25M credits (1 credit = 1 char) = $39.2/M; overage $45/M; Pro $5 = 100k credits, $65/M overage"),
 "Kokoro-82M self-hosted, CPU":        dict(per_min=(CPU_SERVER_MONTH / (VCPUS * HOURS_MONTH * 60 * DUTY / rtf)), floor=CPU_SERVER_MONTH,
                                            note=f"measured {rtf} CPU-s per audio-s per vCPU (1 thread, loaded host); server ${CPU_SERVER_MONTH}/mo ASSUMPTION; capacity at {int(DUTY*100)}% duty"),
 "Kokoro-82M self-hosted, 4090 GPU":   dict(per_min=None, floor=GPU_4090_HOUR * HOURS_MONTH, note="GPU always-on $248/mo (community) ; RTF NOT measured here, vendor claims far below 0.1"),
 "Chatterbox (MIT) self-hosted, 4090": dict(per_min=None, floor=GPU_4090_HOUR * HOURS_MONTH, note="needs GPU for real time; RTF not measured here"),
}

def text_cost(m):
    return max(TEXT_FLOOR_TYPICAL, TURNS_PER_MIN * m * TEXT_PER_MSG)

rows = []
for name, o in OPTS.items():
    pm = o.get("per_min")
    for m in MINUTES:
        voice = None if pm is None else pm * m
        row = dict(option=name, minutes=m, per_min=pm, voice_usd=None if voice is None else round(voice, 3), text_usd=round(text_cost(m), 3))
        for k, c in APPLE.items():
            net = PRICE * (1 - c)
            row[f"net_after_apple_{k}"] = round(net, 2)
            row[f"remaining_{k}"] = None if voice is None else round(net - voice, 2)
            row[f"remaining_incl_text_{k}"] = None if voice is None else round(net - voice - text_cost(m), 2)
        for av in AVATAR:
            tot = None if voice is None else voice + text_cost(m) + av
            row[f"total_ai_avatar{av}"] = None if tot is None else round(tot, 3)
            row[f"fits4_avatar{av}"] = None if tot is None else tot <= BUDGET[0]
            row[f"fits5_avatar{av}"] = None if tot is None else tot <= BUDGET[1]
        rows.append(row)

out = dict(price=PRICE, chars_per_min=CHARS_PER_MIN, kokoro_cpu_s_per_audio_s=rtf, text_heavy_sensitivity=TEXT_HEAVY,
           assumptions=dict(cpu_server_month=CPU_SERVER_MONTH, duty=DUTY, gpu_hour=GPU_4090_HOUR, turns_per_min=TURNS_PER_MIN),
           options={k: {kk: vv for kk, vv in v.items()} for k, v in OPTS.items()}, rows=rows)
json.dump(out, open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "costs.json"), "w"), indent=1)

def f(x, p=2): return "n/m" if x is None else f"${x:.{p}f}"
print(f"Kokoro CPU-seconds per audio-second used: {rtf}\n")
print("| Option | $/min | " + " | ".join(f"{m} min" for m in MINUTES) + " |\n|---|---|" + "---|" * len(MINUTES))
for name, o in OPTS.items():
    pm = o.get("per_min")
    print(f"| {name} | {f(pm,4) if pm is not None else 'n/m'} | " + " | ".join(f(None if pm is None else pm*m) for m in MINUTES) + " |")
print("\nRemaining revenue per subscriber per month after Apple and voice (before text AI), 15% / 30% Apple:")
print("| Option | " + " | ".join(f"{m} min" for m in MINUTES) + " |\n|---|" + "---|" * len(MINUTES))
for name, o in OPTS.items():
    pm = o.get("per_min")
    print(f"| {name} | " + " | ".join("n/m" if pm is None else f"{PRICE*.85-pm*m:.2f} / {PRICE*.70-pm*m:.2f}" for m in MINUTES) + " |")
print("\nText AI per subscriber (typical rate; floor $0.32): " + ", ".join(f"{m} min: ${text_cost(m):.2f}" for m in MINUTES))
print("\nTotal AI (voice + text) per subscriber; avatar $0 | $1.50; F = fits $4 budget, f = fits $5 only, X = over $5")
print("| Option | " + " | ".join(f"{m} min" for m in MINUTES) + " |\n|---|" + "---|" * len(MINUTES))
def flag(t):
    return "F" if t <= 4 else ("f" if t <= 5 else "X")
for name, o in OPTS.items():
    pm = o.get("per_min")
    if pm is None: continue
    cells = []
    for m in MINUTES:
        t = pm*m + text_cost(m)
        cells.append(f"{t:.2f} {flag(t)} | {t+1.5:.2f} {flag(t+1.5)}".replace(" | ", "/"))
    print(f"| {name} | " + " | ".join(cells) + " |")
