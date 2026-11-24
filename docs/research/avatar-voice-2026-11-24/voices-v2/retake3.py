# Sentence-level best-of-N Chatterbox takes, picked by Whisper word accuracy; pauses normalized.
import json, re, sys, numpy as np, torch, soundfile as sf, jiwer
from chatterbox.mtl_tts import ChatterboxMultilingualTTS
from faster_whisper import WhisperModel
torch.set_num_threads(3)
D = json.load(open('../avatar-demo/dialogue.json'))
REF = {'ava': '../voices/kokoro-ava-af_heart.wav', 'ethan': '../voices/kokoro-ethan-am_michael.wav',
       'sofia': '../voices/kokoro-sofia-ef_dora.wav', 'diego': '../voices/kokoro-diego-em_alex.wav'}
coach, n = sys.argv[1], int(sys.argv[2])
hard = set(sys.argv[3].split(',')) if len(sys.argv) > 3 else set()
si = -1
lang = D[coach]['lang']
m = ChatterboxMultilingualTTS.from_pretrained(device='cpu')
asr = WhisperModel('small', device='cpu', compute_type='int8', cpu_threads=1)
norm = lambda s: ' '.join(re.sub(r"[^\w\s']", ' ', s.lower()).split())
def trim(w, sr, thr=0.012, keep=0.08):
    idx = np.where(np.abs(w) > thr)[0]
    if not len(idx): return w
    return w[max(0, idx[0] - int(keep*sr)): idx[-1] + int(keep*sr)]
def cap_gaps(w, sr, maxgap=0.35, thr=0.012):
    # shorten any internal silence longer than maxgap
    env = np.convolve(np.abs(w) > thr, np.ones(int(0.02*sr)), 'same') > 0
    out, i = [], 0
    while i < len(w):
        j = i
        while j < len(w) and env[j] == env[i]: j += 1
        seg = w[i:j]
        if not env[i] and len(seg) > maxgap*sr: seg = seg[:int(maxgap*sr)]
        out.append(seg); i = j
    return np.concatenate(out)
report, turns = [], []
for t, line in enumerate([x for r, x in D[coach]['turns'] if r == 'coach']):
    sents = [s for s in re.split(r'(?<=[.!?])\s+', line) if s]
    parts = []
    global_si = None
    for s in sents:
        si += 1
        import os
        cache = f'cache/{coach}-{si}.npy'
        if os.path.exists(cache):
            w = np.load(cache); parts += [w, np.zeros(int(m.sr*0.22), np.float32)]
            print(coach, t, 'cached', s[:50], flush=True); continue
        best = None
        for k in range(12 if str(si) in hard else n + 2):
            torch.manual_seed(100 + k)
            try:
                w = m.generate(s, language_id=lang, audio_prompt_path=REF[coach], exaggeration=0.5, cfg_weight=0.5).squeeze().numpy()
            except Exception as ex:
                print('take failed', coach, repr(ex)[:80], flush=True); continue
            w = cap_gaps(trim(w, m.sr), m.sr)
            sf.write('/tmp/_take.wav', w, m.sr)
            hyp = ' '.join(x.text for x in asr.transcribe('/tmp/_take.wav', language=lang, beam_size=1)[0])
            err = jiwer.wer(norm(s), norm(hyp)) if norm(hyp) else 1.0
            score = err + 0.02 * max(0, len(w)/m.sr - len(s.split())*0.42)  # prefer accurate, then not slow
            if best is None or score < best[0]: best = (score, err, w, hyp)
        report.append({'turn': t, 'text': s, 'wer': round(best[1], 3), 'hyp': best[3].strip(), 'sec': round(len(best[2])/m.sr, 2)})
        print(coach, t, round(best[1], 3), s[:50], '->', best[3].strip()[:60], flush=True)
        os.makedirs('cache', exist_ok=True); np.save(cache, best[2])
        parts += [best[2], np.zeros(int(m.sr*0.22), np.float32)]
    turns.append(np.concatenate(parts))
out = np.concatenate(sum([[x, np.zeros(int(m.sr*0.7), np.float32)] for x in turns], []))
sf.write(f'chatterbox2-{coach}.wav', out, m.sr)
np.save(f'turns-{coach}.npy', np.array([len(x) for x in turns]))
json.dump(report, open(f'report-{coach}.json', 'w'), ensure_ascii=False, indent=1)
print('done', coach, round(len(out)/m.sr, 1), 's', flush=True)
