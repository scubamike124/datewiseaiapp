"""Demo jobs: Piper TTS audio (a stand-in for the iPhone's voices) + word
timings derived from Piper's phoneme alignments (what iOS's word-range
callbacks give the app). Writes <out>/<coach>-<lang>.{wav,json}.

Usage: make_jobs.py <out_dir>
Needs a separate venv with `pip install piper-tts onnx` (Piper is GPL-3.0:
used offline for review audio only, never shipped) and the voices below in
$AVATAR_TOOLS/voices/ (from huggingface.co/rhasspy/piper-voices)."""
import json, os, re, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.environ.get("AVATAR_TOOLS", os.path.expanduser("~/.cache/datewise-avatar-tools"))
PY = os.environ.get("PIPER_PYTHON", os.path.join(TOOLS, "ttsenv", "bin", "python"))
# Every coach's voice in every language: (Piper voice, speaker id, pitch shift
# in semitones). Spanish: only two Mexican voices exist in Piper (claude,
# female; ald, male), and the app speaks es-MX, so Ava and Ethan in Spanish
# use them too with a formant-preserving pitch shift. That is also what the
# app does on an iPhone with one voice per language and gender: the coaches
# differ by pitch and rate.
VOICES = {
    ("ava", "en"): ("en_US-ljspeech-medium", None, 0),      # female, public domain
    ("ethan", "en"): ("en_US-john-medium", None, 0),        # male, public domain
    ("sofia", "en"): ("en_US-libritts_r-medium", 4, 0),     # female speaker, CC BY 4.0
    ("diego", "en"): ("en_US-norman-medium", None, 0),      # male, public domain
    ("sofia", "es"): ("es_MX-claude-high", None, 0),        # female, Apache-2.0
    ("diego", "es"): ("es_MX-ald-medium", None, 0),         # male, Unlicense
    ("ava", "es"): ("es_MX-claude-high", None, -1.5),       # same es-MX voice, lower and slower
    ("ethan", "es"): ("es_MX-ald-medium", None, +0.5),      # same es-MX voice, slightly higher, faster
}
# Piper length scale (1 = the voice's own pace; > 1 slower). Coaches that
# share a voice differ by about 8% in rate, like the app's voice profiles.
PACE = {
    ("ava", "en"): 1.0, ("ethan", "en"): 1.05, ("sofia", "en"): 1.0, ("diego", "en"): 1.06,
    ("sofia", "es"): 1.0, ("ava", "es"): 1.08, ("diego", "es"): 1.06, ("ethan", "es"): 0.97,
}
TEXT = {
    ("ava", "en"): "Hi, I'm Ava. Your profile already shows warmth. Change one thing: lead with a specific story, then ask a playful question.",
    ("ethan", "en"): "Hey, I'm Ethan. Keep the opener simple. Mention something from her photos, keep it light, and suggest coffee this week.",
    ("sofia", "en"): "Hi, I'm Sofia. You did great by reaching out. Tonight, send one honest message and notice how it feels.",
    ("diego", "en"): "Hi, I'm Diego. Be clear about what you want. Say it kindly, listen to the answer, and respect boundaries.",
    ("ava", "es"): "Hola, soy Ava. Tu perfil ya transmite calidez. Cambia una sola cosa: empieza con una historia concreta y termina con una pregunta divertida.",
    ("ethan", "es"): "Hola, soy Ethan. Mantén el primer mensaje sencillo. Menciona algo de sus fotos y propón un café esta semana.",
    ("sofia", "es"): "Hola, soy Sofía. Diste un gran paso al escribirle. Esta noche, envía un mensaje honesto y observa cómo te sientes.",
    ("diego", "es"): "Hola, soy Diego. Sé claro con lo que buscas. Dilo con respeto, escucha su respuesta y cuida tus límites.",
}
WORD = re.compile(r"[^\W_][\w'’]*", re.UNICODE)


def words_from_phonemes(phones):
    """Group phonemes into words (Piper/espeak separate words with spaces and
    punctuation). Returns [(start, end, [phonemes])]."""
    out, cur = [], []
    for p in phones:
        sym = p["p"]
        if sym in (" ", ",", ".", "!", "?", ";", ":", "^", "$", "_", "—") or sym.strip() == "":
            if cur:
                out.append((cur[0]["start"], cur[-1]["end"], cur)); cur = []
            continue
        if sym in ("ˈ", "ˌ", "ː") and not cur:
            continue
        cur.append(p)
    if cur:
        out.append((cur[0]["start"], cur[-1]["end"], cur))
    return out


def rms_levels(path, hop=0.01):
    import wave
    import numpy as np
    w = wave.open(path)
    sr = w.getframerate()
    x = np.frombuffer(w.readframes(w.getnframes()), np.int16).astype(float) / 32768
    n = int(sr * hop)
    return [round(float(np.sqrt((x[i:i + n] ** 2).mean())), 5) for i in range(0, len(x) - n + 1, n)]


def main():
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    for (coach, lang), text in TEXT.items():
        voice, speaker, semitones = VOICES[(coach, lang)]
        base = os.path.join(out, f"{coach}-{lang}")
        cmd = [PY, "-I", os.path.join(HERE, "tts_align.py"), os.path.join(TOOLS, "voices", voice + ".onnx"),
               text, base + ".wav", base + ".ph.json", str(PACE[(coach, lang)])]
        if speaker is not None:
            cmd.append(str(speaker))
        subprocess.run(cmd, check=True, capture_output=True)
        if semitones:
            # Pitch only (timing and formants kept), so the alignments stay exact.
            subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", base + ".wav", "-af",
                            f"rubberband=pitch={2 ** (semitones / 12):.4f}:formant=preserved", base + ".p.wav"], check=True)
            os.replace(base + ".p.wav", base + ".wav")
        levels = rms_levels(base + ".wav")
        ph = json.load(open(base + ".ph.json"))
        pw = words_from_phonemes(ph["phonemes"])
        tw = [(m.start(), m.end(), m.group(0)) for m in WORD.finditer(text)]
        if len(pw) != len(tw):
            print(f"WARNING {coach}-{lang}: {len(tw)} words vs {len(pw)} phoneme words", file=sys.stderr)
        n = min(len(pw), len(tw))
        words = [{"text": tw[i][2], "charStart": tw[i][0], "charEnd": tw[i][1], "start": pw[i][0], "end": pw[i][1],
                  "phonemes": [{"p": p["p"], "start": p["start"], "end": p["end"]} for p in pw[i][2]]} for i in range(n)]
        job = {"coach": coach, "language": lang, "voice": voice, "speaker": speaker, "pitch_semitones": semitones,
               "text": text, "duration": ph["duration"], "wav": base + ".wav", "words": words,
               # What the native audio path streams: RMS per 10 ms.
               "levels_hop": 0.01, "levels": levels}
        json.dump(job, open(base + ".json", "w"), ensure_ascii=False, indent=1)
        os.remove(base + ".ph.json")
        print(f"{coach}-{lang}: {ph['duration']:.2f}s, {len(tw)} words / {len(pw)} phoneme words ({voice})")


if __name__ == "__main__":
    main()
