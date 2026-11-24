# Builds, per coach: user turns (Kokoro) + coach turns (Chatterbox v2 takes), a coach-only track (silence while
# the user speaks, so the avatar visibly listens) and the full mix, both 16 kHz mono, plus a timeline.
import json, sys, numpy as np, soundfile as sf, torch
from kokoro import KPipeline
import librosa
torch.set_num_threads(1)
S = '/tmp/claude-0/-home-user/e4099752-5f8a-5b57-9c7d-84efe288e985/scratchpad'
D = json.load(open(f'{S}/avatar-demo/dialogue.json'))
USER = {'ava': ('a', 'am_puck'), 'ethan': ('a', 'af_bella'), 'sofia': ('e', 'em_santa'), 'diego': ('e', 'em_santa')}
SR = 16000
for coach in sys.argv[1:]:
    lang, voice = USER[coach]
    kp = KPipeline(lang_code=lang)
    cw, csr = sf.read(f'{S}/voices2/chatterbox2-{coach}.wav')
    lens = np.load(f'{S}/voices2/turns-{coach}.npy')
    cw = librosa.resample(cw.astype(np.float32), orig_sr=csr, target_sr=SR); lens = (lens * SR / csr).astype(int)
    gap = int(0.7 * SR); turns, o = [], 0
    for n in lens: turns.append(cw[o:o + n]); o += n + gap
    coach_only, mix, timeline, ci, t = [], [], [], 0, 0.0
    lead = np.zeros(int(1.2 * SR), np.float32)  # a moment of idle listening before the first line
    coach_only.append(lead); mix.append(lead); t += len(lead) / SR
    for role, text in D[coach]['turns']:
        if role == 'user':
            a = np.concatenate([x.numpy() if hasattr(x, 'numpy') else x for _, _, x in kp(text, voice=voice, speed=1.0)])
            a = librosa.resample(a.astype(np.float32), orig_sr=24000, target_sr=SR) * 0.9
            coach_only.append(np.zeros_like(a)); mix.append(a)
        else:
            a = turns[ci]; ci += 1
            coach_only.append(a); mix.append(a)
        timeline.append([role, round(t, 2), round(t + len(a) / SR, 2)]); t += len(a) / SR
        pause = np.zeros(int(0.6 * SR), np.float32); coach_only.append(pause); mix.append(pause); t += 0.6
    tail = np.zeros(int(1.5 * SR), np.float32); coach_only.append(tail); mix.append(tail)
    sf.write(f'audio/{coach}-coachonly.wav', np.concatenate(coach_only), SR)
    sf.write(f'audio/{coach}-mix.wav', np.concatenate(mix), SR)
    json.dump(timeline, open(f'audio/{coach}-timeline.json', 'w'))
    print('done', coach, round(len(np.concatenate(mix)) / SR, 1), 's', flush=True)
