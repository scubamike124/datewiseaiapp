"""Re-run the frame gate (verify.check_frame) on the committed frames.

Usage: python tool/avatar/regate.py [--portraits assets/coaches] [--frames assets/avatar]

For each coach it scales the hero to the manifest size (as gen_frames.py
does), pastes every committed JPEG patch at its rect and gates the result
with the same thresholds. It prints every frame's values and each coach's
worst eye shift, and exits 1 if any frame fails. gen_frames.py gates the
same JPEG round-trip before writing, so the two agree.
"""
import argparse, json, os, sys
import cv2

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import verify  # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--portraits", default="assets/coaches")
    ap.add_argument("--frames", default="assets/avatar")
    args = ap.parse_args()
    refs = verify.reference_embeddings()
    total = failed = 0
    for coach in verify.COACHES:
        man = json.load(open(os.path.join(args.frames, coach, "manifest.json")))
        hero = cv2.imread(os.path.join(args.portraits, f"{coach}-hero.jpg"))
        if hero.shape[1] != man["width"]:
            hero = cv2.resize(hero, (man["width"], man["height"]), interpolation=cv2.INTER_AREA)
        master = verify.analyse(hero)
        worst = {"ab": 0.0, "L": 0.0, "identity": 1.0, "master": 1.0}
        for name, fr in man["frames"].items():
            x, y, w, h = fr["rect"]
            img = hero.copy()
            img[y:y + h, x:x + w] = cv2.imread(os.path.join(args.frames, coach, f"{name}.jpg"))
            r = verify.check_frame(img, coach, refs, master, eyes_closed=name.startswith("blink"),
                                   eyes_moved=name == "gaze")
            total += 1
            failed += not r["ok"]
            es = r.get("eye_shift", {})
            worst["ab"] = max(worst["ab"], es.get("ab", 0))
            worst["L"] = max(worst["L"], es.get("L", 0))
            worst["identity"] = min(worst["identity"], r["identity"])
            worst["master"] = min(worst["master"], r["master"])
            print(f"{coach}/{name}: {'ok' if r['ok'] else 'FAIL'} id={r['identity']:.3f} master={r['master']:.3f} "
                  f"eye={es} {'; '.join(r['notes'])}", flush=True)
        print(f"{coach} worst: eye chroma {worst['ab']} (max {verify.AB_MAX}), eye lightness {worst['L']} "
              f"(max {verify.L_MAX}), identity {worst['identity']} (min {verify.ID_MIN}), "
              f"master {worst['master']} (min {verify.MASTER_MIN})", flush=True)
    print(f"\n{total - failed}/{total} frames pass")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
