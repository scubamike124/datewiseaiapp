"""Piper TTS (demo only) with phoneme alignments -> wav + JSON timings.
Usage: tts_align.py <voice.onnx> <text> <out.wav> <out.json> [length_scale] [speaker_id]"""
import sys, json, wave, numpy as np
from piper import PiperVoice, SynthesisConfig
voice_path, text, out_wav, out_json = sys.argv[1:5]
ls = float(sys.argv[5]) if len(sys.argv) > 5 else 1.0
spk = int(sys.argv[6]) if len(sys.argv) > 6 else None
v = PiperVoice.load(voice_path, include_alignments=True)
sr = v.config.sample_rate
cfg = SynthesisConfig(length_scale=ls, speaker_id=spk)
audio, phones, t = [], [], 0
for ch in v.synthesize(text, cfg, include_alignments=True):
    audio.append(ch.audio_int16_array)
    for a in ch.phoneme_alignments or []:
        d = a.num_samples / sr
        phones.append({"p": a.phoneme, "start": round(t, 4), "end": round(t + d, 4)})
        t += d
    t = sum(len(x) for x in audio) / sr  # resync at chunk (sentence) end
pcm = np.concatenate(audio)
with wave.open(out_wav, "wb") as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(sr); w.writeframes(pcm.tobytes())
json.dump({"sr": sr, "duration": len(pcm) / sr, "phonemes": phones}, open(out_json, "w"), ensure_ascii=False)
print(f"{len(pcm)/sr:.2f}s {len(phones)} phonemes")
