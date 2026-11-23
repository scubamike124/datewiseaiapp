"""Lip-sync timing accuracy of the app's viseme timeline vs. ground truth.

Ground truth: Piper's phoneme alignments (sample-exact), mapped IPA -> viseme.
'anchored' = the app's timeline given only word start/end times (what iOS's
word callbacks provide), with the app's spelling rules inside each word.
'planned'  = the app's estimate with NO word events (rate model only).
Usage: analyze_sync.py <jobs_dir> <render_out_dir>"""
import json, glob, os, sys
import numpy as np

OPEN = {"rest": 0, "mbp": 0, "a": 1, "a2": .55, "e": .65, "e2": .4, "i": .4, "i2": .22, "o": .8, "o2": .5,
        "u": .35, "u2": .12, "fv": .1, "l": .6, "th": .45, "cons": .4, "sh": .3}
FULL = {"a2": "a", "e2": "e", "i2": "i", "o2": "o", "u2": "u"}  # class = shape ignoring the opening
IPA = {}
for ch in "pbmβ": IPA[ch] = "mbp"
for ch in "fv": IPA[ch] = "fv"
for ch in "θð": IPA[ch] = "th"
IPA["l"] = "l"; IPA["w"] = "u"
for ch in "aɑæʌɐ": IPA[ch] = "a"
for ch in "eɛəɜɚɝ": IPA[ch] = "e"
for ch in "iɪy": IPA[ch] = "i"
for ch in "oɔɒ": IPA[ch] = "o"
for ch in "uʊ": IPA[ch] = "u"
for ch in "ʃʒ": IPA[ch] = "sh"


def gt_series(job, t):
    out = np.array(["rest"] * len(t), dtype=object)
    for w in job["words"]:
        prev = None
        for p in w["phonemes"]:
            sym = p["p"]
            if sym in "ˈˌː":
                v = prev
            else:
                v = IPA.get(sym, "cons")
                prev = v
            if v is None:
                continue
            out[(t >= p["start"]) & (t < p["end"])] = v
    return out


def cue_series(cues, t, lead=0.0):
    """The shape shown at each time: the app samples the timeline `lead`
    seconds ahead, so a cue is on screen `lead` earlier than its time."""
    out = np.array(["rest"] * len(t), dtype=object)
    for name, s, e in cues:
        out[(t >= s - lead) & (t < e - lead)] = name
    return out


def wav_rms(path, t):
    import wave
    w = wave.open(path)
    sr = w.getframerate()
    x = np.frombuffer(w.readframes(w.getnframes()), np.int16).astype(float)
    out = []
    for c in t:
        seg = x[int(max(0, c - 0.015) * sr):int((c + 0.015) * sr)]
        out.append(np.sqrt((seg ** 2).mean()) if len(seg) else 0)
    return np.array(out)


def longest(mask, dt=0.01):
    best = cur = 0
    for m in mask:
        cur = cur + 1 if m else 0
        best = max(best, cur)
    return best * dt


def main():
    jobs_dir, out_dir = sys.argv[1:3]
    rows = []
    for jf in sorted(glob.glob(os.path.join(jobs_dir, "*.json"))):
        name = os.path.basename(jf)[:-5]
        cf = os.path.join(out_dir, name + ".cues.json")
        if not os.path.exists(cf):
            continue
        job, cues = json.load(open(jf)), json.load(open(cf))
        t = np.arange(0, job["duration"], 0.01)
        gt = gt_series(job, t)
        speech = gt != "rest"
        r = {"clip": name}
        lead = cues.get("lead_visemes", 0.0)
        rms = wav_rms(job["wav"], t)
        audible = rms > 0.15 * rms.max()
        for kind in ("anchored", "planned"):
            if kind == "anchored" and "shown" in cues:
                # What the rendered frames actually showed (the app's driver,
                # lead included), held from frame to frame.
                sh = cues["shown"]
                # LEAD_REMOVED=1 shifts the shown shapes back by the lead,
                # to judge the alignment itself rather than the lead.
                st = np.array([x[0] for x in sh]) + (lead if os.environ.get("LEAD_REMOVED") else 0.0)
                idx = np.clip(np.searchsorted(st, t, side="right") - 1, 0, len(sh) - 1)
                pr = np.array([sh[i][1] for i in idx], dtype=object)
            else:
                pr = cue_series(cues[kind], t, lead if kind == "anchored" else 0.0)
            go = np.array([OPEN[v] for v in gt]); po = np.array([OPEN[v] for v in pr])
            cls = np.array([FULL.get(v, v) for v in pr])
            r[kind + "_exact"] = float((cls[speech] == gt[speech]).mean())
            r[kind + "_rest_audible_s"] = longest(audible & (pr == "rest"))
            same = np.concatenate([[False], pr[1:] == pr[:-1]])
            run = 0; hold = 0.0
            for k in range(len(pr)):
                run = run + 1 if (same[k] and audible[k] and pr[k] != "rest") else 0
                hold = max(hold, run * 0.01)
            r[kind + "_max_hold_audible_s"] = hold
            r[kind + "_open_r"] = float(np.corrcoef(go, po)[0, 1])
            r[kind + "_open_mae"] = float(np.abs(go - po).mean())
            # Lag of the shown mouth behind the true phonemes (+ = mouth late), 10 ms steps.
            best = (0, -2)
            for lag in range(-30, 31):
                a, b = (po[lag:], go[:len(go) - lag]) if lag >= 0 else (po[:lag], go[-lag:])
                rr = np.corrcoef(a, b)[0, 1]
                if rr > best[1]:
                    best = (lag * 10, rr)
            r[kind + "_lag_ms"] = best[0]
            # Lip closures: every ground-truth M/B/P, is the predicted mouth
            # closed (mbp) within +-80 ms of its centre?
            hits = tot = 0
            for w in job["words"]:
                for p in w["phonemes"]:
                    if IPA.get(p["p"]) == "mbp":
                        tot += 1
                        c = (p["start"] + p["end"]) / 2
                        m = (t >= c - 0.08) & (t <= c + 0.08)
                        hits += bool((pr[m] == "mbp").any())
            r[kind + "_closure_hit"] = hits / tot if tot else float("nan")
            r["closures"] = tot
        rows.append(r)
    keys = ["anchored_exact", "planned_exact", "anchored_open_r", "planned_open_r", "anchored_open_mae",
            "planned_open_mae", "anchored_closure_hit", "planned_closure_hit", "anchored_lag_ms", "anchored_rest_audible_s",
            "anchored_max_hold_audible_s"]
    print("clip        " + " ".join(f"{k:>20}" for k in keys))
    for r in rows:
        print(f"{r['clip']:<11} " + " ".join(f"{r[k]:>20.2f}" for k in keys))
    print(f"{'MEAN':<11} " + " ".join(f"{np.nanmean([r[k] for r in rows]):>20.2f}" for k in keys))
    json.dump(rows, open(os.path.join(out_dir, "sync_accuracy.json"), "w"), indent=1)


if __name__ == "__main__":
    main()
