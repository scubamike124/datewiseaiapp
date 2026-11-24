import json, numpy as np, torch, soundfile as sf, sys
from chatterbox.mtl_tts import ChatterboxMultilingualTTS
torch.set_num_threads(2)
D = json.load(open('../avatar-demo/dialogue.json'))
REF = {'ava': 'kokoro-ava-af_heart.wav', 'ethan': 'kokoro-ethan-am_michael.wav', 'sofia': 'kokoro-sofia-ef_dora.wav', 'diego': 'kokoro-diego-em_alex.wav'}
m = ChatterboxMultilingualTTS.from_pretrained(device='cpu')
for coach in sys.argv[1:]:
    lang = D[coach]['lang']; lines = [t for r, t in D[coach]['turns'] if r == 'coach']
    out = []
    for line in lines:
        torch.manual_seed(7)
        w = m.generate(line, language_id=lang, audio_prompt_path=REF[coach], exaggeration=0.55, cfg_weight=0.45)
        out += [w.squeeze().numpy(), np.zeros(int(m.sr * 0.7), dtype=np.float32)]
    sf.write(f'chatterbox-{coach}.wav', np.concatenate(out), m.sr); print('done', coach, flush=True)
