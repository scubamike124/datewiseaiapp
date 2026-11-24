# IMTalker CPU test (2026-11-24): free, research only

Ran on CPU with the upstream code (commit bd91867), upstream defaults (10 steps, audio guidance 3, seed 42), a runner that
forces CPU and swaps in a MediaPipe crop. Same 10 s Ava slice as the MuseTalk test. Single seed, single clip.

| | Ditto | MuseTalk | IMTalker (closed-mouth portrait) | IMTalker (open-smile portrait) |
|---|---|---|---|---|
| Frames with lips closed | 0 | 6 | 86 | 47 |
| Mean lip gap while speaking | 0.113 | 0.055 | 0.041 | 0.061 |
| Smallest gap on the 5 m/b/p words | 0.038-0.083 | 0.015-0.034 | 0.001-0.004 | |
| Lip-landmark jitter | 1.22 | 1.17 | 1.83 | 2.08 |
| Head motion (nose std x,y) | 0.015, 0.020 | | 0.029, 0.041 | |

- Render time: 876 s (88 s per video second, busy machine) and 504 s (50 s per video second); peak RAM 5.3 GB. CPU only,
  so offline clips only, no live use without a GPU.
- Lip sync: the only one of the three that closes the lips on all five m/b/p words. From the closed-mouth portrait the
  vowels open only modestly; the open-smile source is more expressive. The Ditto clip appears to have been driven from
  the open-smile portrait, so the fair comparison is the open-smile run.
- Identity close, slightly softer (fewer freckles). Brown eyes kept (iris RGB about (72,46,36) vs (73,48,36)). 2 blinks
  in 10 s. Head motion about 2x Ditto's, sometimes bobbly.
- Artifacts: lips wash out at closure, lip landmarks jitter more, hair edges shimmer, output is a 512x512 face crop
  (a full portrait needs our own paste-back).
- Licences: code Apache-2.0; weights MIT (model card says only `license: mit`; training data not named);
  wav2vec2 Apache-2.0 (byte-identical to Facebook's copy); MediaPipe Apache-2.0. No InsightFace or other
  non-commercial part found. Not downloaded: S3FD/FAN face-detector weights (licence unstated). Checkpoints are
  pickled `.ckpt` files and should be converted to safetensors before any production use.

Verdict: the best lip closure of the three free options and cleanly licensed, but too slow for live use on CPU and
visibly noisier than Ditto. Worth a GPU test for real-time speed and a paste-back pipeline.
