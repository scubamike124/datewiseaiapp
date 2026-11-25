#!/usr/bin/env python3
"""Sentence-by-sentence Kokoro speech with a mouth-openness timeline for the avatar.

Why: the avatar needs audio that starts quickly and a mouth track that matches the audio. Kokoro renders a whole text
in one call and returns no word timings, so this renders one sentence at a time (the first sentence plays while the
next is rendered) and derives a mouth-openness curve from the audio envelope (10 frames per second).

Usage: kokoro_sentences.py MODEL VOICES LANG VOICE TEXT_FILE OUT_DIR [SPEED]
Output: OUT_DIR/s001.wav ... and OUT_DIR/timeline.json with, per sentence, start/end seconds and the mouth curve.
"""
import json
import os
import re
import sys
import time

import numpy as np
import soundfile as sf
from kokoro_onnx import Kokoro

FPS = 10
SENT = re.compile(r'(?<=[.!?¿¡])\s+')


def split_sentences(text: str) -> list[str]:
    parts = [p.strip() for p in SENT.split(text.strip()) if p.strip()]
    return parts


def mouth_curve(samples: np.ndarray, sr: int) -> list[float]:
    """Mouth openness 0..1 at FPS frames: RMS envelope, normalised by its own peak so quiet and loud voices both move."""
    hop = int(sr / FPS)
    frames = max(1, len(samples) // hop)
    rms = np.array([np.sqrt(np.mean(samples[i * hop:(i + 1) * hop] ** 2)) for i in range(frames)])
    peak = rms.max() if rms.size and rms.max() > 0 else 1.0
    curve = np.clip(rms / peak, 0.0, 1.0)
    # Light smoothing so the mouth does not flicker frame to frame.
    smooth = np.convolve(curve, np.array([0.25, 0.5, 0.25]), mode='same')
    return [round(float(x), 3) for x in smooth]


def main() -> int:
    model, voices, lang, voice, text_file, out_dir = sys.argv[1:7]
    speed = float(sys.argv[7]) if len(sys.argv) > 7 else 0.95
    os.makedirs(out_dir, exist_ok=True)
    text = open(text_file, encoding='utf-8').read()
    sentences = split_sentences(text)
    k = Kokoro(model, voices)
    timeline = {'voice': voice, 'lang': lang, 'speed': speed, 'fps': FPS, 'sentences': []}
    clock = 0.0
    first_audio_s = None
    t0 = time.time()
    for i, sent in enumerate(sentences, 1):
        t = time.time()
        samples, sr = k.create(sent, voice=voice, speed=speed, lang=lang)
        render_s = time.time() - t
        if first_audio_s is None:
            first_audio_s = time.time() - t0
        dur = len(samples) / sr
        wav = os.path.join(out_dir, f's{i:03d}.wav')
        sf.write(wav, samples, sr)
        timeline['sentences'].append({
            'index': i,
            'text': sent,
            'start_s': round(clock, 3),
            'duration_s': round(dur, 3),
            'render_s': round(render_s, 3),
            'mouth': mouth_curve(samples, sr),
        })
        clock += dur
    timeline['first_audio_s'] = round(first_audio_s or 0.0, 3)
    timeline['total_audio_s'] = round(clock, 3)
    timeline['total_render_s'] = round(time.time() - t0, 3)
    with open(os.path.join(out_dir, 'timeline.json'), 'w', encoding='utf-8') as f:
        json.dump(timeline, f, ensure_ascii=False, indent=1)
    print(json.dumps({k2: timeline[k2] for k2 in ('voice', 'first_audio_s', 'total_audio_s', 'total_render_s')}))
    return 0


if __name__ == '__main__':
    sys.exit(main())
