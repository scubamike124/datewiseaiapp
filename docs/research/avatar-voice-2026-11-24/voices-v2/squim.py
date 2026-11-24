import sys, glob, json, torch, torchaudio
from torchaudio.pipelines import SQUIM_OBJECTIVE
torch.set_num_threads(1)
m = SQUIM_OBJECTIVE.get_model()
out = {}
for f in sys.argv[1:]:
    w, sr = torchaudio.load(f); w = torchaudio.functional.resample(w.mean(0, keepdim=True), sr, 16000)
    # score in 8 s windows, average
    seg = 16000 * 8; vals = []
    for i in range(0, w.shape[1] - 16000, seg):
        with torch.no_grad(): s, p, d = m(w[:, i:i + seg])
        vals.append((s.item(), p.item(), d.item()))
    n = len(vals); out[f.split('/')[-1]] = {k: round(sum(v[j] for v in vals) / n, 2) for j, k in enumerate(['STOI', 'PESQ', 'SI-SDR'])}
    print(f.split('/')[-1], out[f.split('/')[-1]], flush=True)
json.dump(out, open('squim.json', 'w'), indent=1)
