import json, glob, re, jiwer
from faster_whisper import WhisperModel
D = json.load(open('../avatar-demo/dialogue.json'))
m = WhisperModel('small', device='cpu', compute_type='int8', cpu_threads=2)
norm = lambda s: re.sub(r"[^\w\s']", ' ', s.lower()).split()
rows = []
for f in sorted(glob.glob('mp3/*.mp3')):
    coach = f.split('-')[1].split('.')[0]
    ref = ' '.join(t for r, t in D[coach]['turns'] if r == 'coach')
    segs, info = m.transcribe(f, language=D[coach]['lang'], beam_size=1)
    hyp = ' '.join(s.text for s in segs)
    w = jiwer.wer(' '.join(norm(ref)), ' '.join(norm(hyp)))
    rows.append({'file': f, 'wer': round(w, 3), 'duration': round(info.duration, 1), 'hyp': hyp.strip()})
    print(f, round(w, 3), flush=True)
json.dump(rows, open('asr.json', 'w'), ensure_ascii=False, indent=1)
