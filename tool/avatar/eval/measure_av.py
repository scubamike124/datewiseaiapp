"""Reviewer-style A/V measurement of a demo MP4.

Mouth activity = mean absolute difference of the mouth region from the first
(idle) frame, after aligning each frame to it by phase correlation (removes
the breathing/sway motion). Loudness = audio RMS per video frame.
Both are resampled to 100 Hz; Pearson r is computed for lags in +-300 ms.
Positive lag = the mouth trails the audio.
Also reports the longest stretch where audio is active (RMS > 15% of max)
but the mouth region is unchanged from idle (diff < 15% of its max).
Usage: measure_av.py <yunet.onnx> <video.mp4> [...]   (AV_OUT=<json> to save)"""
import json, subprocess, sys, tempfile, wave, os
import cv2, numpy as np


def frames(path):
    cap = cv2.VideoCapture(path)
    fps = cap.get(cv2.CAP_PROP_FPS)
    out = []
    while True:
        ok, f = cap.read()
        if not ok:
            break
        out.append(f)
    return fps, out


def audio_rms(path, fps, n):
    with tempfile.TemporaryDirectory() as d:
        w = os.path.join(d, "a.wav")
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", path, "-ac", "1", "-ar", "16000", w], check=True)
        wf = wave.open(w)
        x = np.frombuffer(wf.readframes(wf.getnframes()), np.int16).astype(float)
    hop = 16000 / fps
    rms = []
    for i in range(n):
        c = int((i + 0.5) * hop)
        seg = x[max(0, c - int(hop / 2)):c + int(hop / 2)]
        rms.append(np.sqrt((seg ** 2).mean()) if len(seg) else 0)
    return np.array(rms)


def main():
    det_path = sys.argv[1]
    results = {}
    for path in sys.argv[2:]:
        fps, fr = frames(path)
        g0 = cv2.cvtColor(fr[0], cv2.COLOR_BGR2GRAY).astype(np.float32)
        h, w = g0.shape
        det = cv2.FaceDetectorYN.create(det_path, "", (w, h), 0.8, 0.3, 5000)
        _, f = det.detect(fr[0])
        f = max(f, key=lambda r: r[2] * r[3])
        mx, my = (f[10] + f[12]) / 2, (f[11] + f[13]) / 2
        mw = abs(f[12] - f[10])
        x0, x1 = int(mx - 0.9 * mw), int(mx + 0.9 * mw)
        y0, y1 = int(my - 0.45 * mw), int(my + 0.75 * mw)
        win = cv2.createHanningWindow((w, h), cv2.CV_32F)
        diff, opn = [], []
        for im in fr:
            g = cv2.cvtColor(im, cv2.COLOR_BGR2GRAY).astype(np.float32)
            (dx, dy), _ = cv2.phaseCorrelate(g0, g, win)
            M = np.float32([[1, 0, -dx], [0, 1, -dy]])
            ga = cv2.warpAffine(g, M, (w, h), borderMode=cv2.BORDER_REPLICATE)
            diff.append(np.abs(ga[y0:y1, x0:x1] - g0[y0:y1, x0:x1]).mean())
            # Openness proxy: area of mouth cavity (very dark) + teeth (bright, unsaturated).
            roi = cv2.warpAffine(im, M, (w, h), borderMode=cv2.BORDER_REPLICATE)[y0:y1, x0:x1]
            hsv = cv2.cvtColor(roi, cv2.COLOR_BGR2HSV)
            v, sat = hsv[..., 2].astype(int), hsv[..., 1].astype(int)
            opn.append(float(((v < 55) | ((v > 170) & (sat < 70))).mean()))
        diff = np.array(diff)
        opn = np.array(opn)
        rms = audio_rms(path, fps, len(fr))
        t = np.arange(len(fr)) / fps
        tt = np.arange(0, t[-1], 0.01)
        # Loudness envelope: RMS smoothed over ~100 ms (3 frames).
        env = np.convolve(rms, np.ones(3) / 3, mode="same")
        r100 = np.interp(tt, t, env)

        def corr(series):
            d100 = np.interp(tt, t, series)
            best = None
            for lag in range(-30, 31):  # 10 ms steps
                a, b = (d100[lag:], r100[:len(r100) - lag]) if lag >= 0 else (d100[:lag], r100[-lag:])
                r = np.corrcoef(a, b)[0, 1]
                if best is None or r > best[1]:
                    best = (lag * 10, r)
            return float(np.corrcoef(d100, r100)[0, 1]), best

        r0, best = corr(diff)
        o0, obest = corr(opn)
        active = rms > 0.15 * rms.max()
        still = np.abs(np.diff(np.concatenate([[opn[0]], opn]))) + np.abs(np.diff(np.concatenate([[diff[0]], diff]))) < 1e-3
        longest = cur = 0
        for a, s_ in zip(active, still):
            cur = cur + 1 if (a and s_) else 0
            longest = max(longest, cur)
        # Longest stretch showing the idle (rest) mouth while audio is audible.
        at_rest = diff < 0.08 * diff.max()
        rest_long = cur = 0
        for a, s_ in zip(active, at_rest):
            cur = cur + 1 if (a and s_) else 0
            rest_long = max(rest_long, cur)
        name = os.path.basename(path)[:-4]
        results[name] = {"rest_while_audible_ms": round(rest_long * 1000 / fps), "diff_r0": round(r0, 3), "diff_best_lag_ms": best[0], "diff_r_best": round(float(best[1]), 3),
                         "open_r0": round(o0, 3), "open_best_lag_ms": obest[0], "open_r_best": round(float(obest[1]), 3),
                         "frozen_ms": round(longest * 1000 / fps)}
        print(f"{name:10} diff-from-master r(0)={r0:+.2f} best {best[0]:+4d}ms r={best[1]:+.2f} | "
              f"openness r(0)={o0:+.2f} best {obest[0]:+4d}ms r={obest[1]:+.2f} | frozen {longest * 1000 / fps:.0f} ms, rest-while-audible {rest_long * 1000 / fps:.0f} ms")
    rs = list(results.values())
    m = lambda k: np.mean([x[k] for x in rs])
    print(f"MEAN       diff-from-master r(0)={m('diff_r0'):+.2f} best {m('diff_best_lag_ms'):+.0f}ms r={m('diff_r_best'):+.2f} | "
          f"openness r(0)={m('open_r0'):+.2f} best {m('open_best_lag_ms'):+.0f}ms r={m('open_r_best'):+.2f} | frozen max {max(x['frozen_ms'] for x in rs)} ms, rest-while-audible max {max(x['rest_while_audible_ms'] for x in rs)} ms")
    json.dump(results, open(os.environ.get("AV_OUT", "/dev/null"), "w"), indent=1)


if __name__ == "__main__":
    main()
