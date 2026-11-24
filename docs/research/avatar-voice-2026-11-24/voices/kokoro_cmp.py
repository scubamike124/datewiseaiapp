import json, sys, numpy as np, soundfile as sf
from kokoro import KPipeline
D = json.load(open('../avatar-demo/dialogue.json'))
VOICES = {'ava': ['af_heart', 'af_bella', 'af_nicole'], 'ethan': ['am_michael', 'am_fenrir', 'am_puck'],
          'sofia': ['ef_dora'], 'diego': ['em_alex', 'em_santa']}
pipes = {'en': KPipeline(lang_code='a'), 'es': KPipeline(lang_code='e')}
for coach, voices in VOICES.items():
    lang = D[coach]['lang']; lines = [t for r, t in D[coach]['turns'] if r == 'coach']
    for v in voices:
        out = []
        for line in lines:
            for _, _, a in pipes[lang](line, voice=v, speed=1.0):
                out.append(a.numpy() if hasattr(a, 'numpy') else a)
            out.append(np.zeros(int(24000 * 0.7), dtype=np.float32))
        sf.write(f'kokoro-{coach}-{v}.wav', np.concatenate(out), 24000); print('done', coach, v, flush=True)
