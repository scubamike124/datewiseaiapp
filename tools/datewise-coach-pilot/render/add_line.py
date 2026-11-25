"""Render a new Ava line locally and add it to the private pilot catalog."""
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
MEDIA = ROOT / "dist" / "ava"

def register(video, title, language, coach="ava"):
    info = json.loads(subprocess.check_output([
        "ffprobe", "-v", "error", "-show_streams", "-show_format", "-of", "json", video]))
    codecs = {s["codec_type"]: s["codec_name"] for s in info["streams"]}
    if codecs.get("video") != "h264" or codecs.get("audio") != "aac":
        raise ValueError("The pilot requires H.264 video and AAC audio.")
    subprocess.run(["ffmpeg", "-v", "error", "-xerror", "-i", video, "-f", "null", "-"], check=True)
    data = video.read_bytes()
    name = hashlib.sha256(data).hexdigest()[:24] + ".mp4"
    catalog = MEDIA / "lines.json"
    with (ROOT / "render" / ".catalog.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        lines = json.loads(catalog.read_text())
        entry = dict(src="ava/" + name, title=title, language=language, coach=coach,
                     seconds=round(float(info["format"]["duration"]), 1))
        lines = [x for x in lines if x["src"] != entry["src"]] + [entry]
        with tempfile.TemporaryDirectory(dir=MEDIA) as t:
            tmp = Path(t)
            (tmp / name).write_bytes(data)
            (tmp / "lines.json").write_text(json.dumps(lines, ensure_ascii=False, indent=2) + "\n")
            os.replace(tmp / name, MEDIA / name)
            os.replace(tmp / "lines.json", catalog)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("audio", type=Path)
    parser.add_argument("--title", required=True)
    parser.add_argument("--coach", choices=["ava", "ethan", "diego", "sofia"], default="ava")
    parser.add_argument("--language", choices=["English", "Spanish"], default="English")
    args = parser.parse_args()
    if not args.audio.is_file():
        parser.error("Audio file does not exist")
    for name in ("IMT_SOURCE", "IMT_CHECKPOINTS", "FACE_LANDMARKER"):
        if not os.getenv(name) or not Path(os.environ[name]).exists():
            parser.error(f"Set {name} to its installed path on the render machine")
    with tempfile.TemporaryDirectory() as t:
        tmp = Path(t)
        wav, raw, output = tmp / "line.wav", tmp / "render.mp4", tmp / "line.mp4"
        pace = ["-af", "atempo=0.85"] if args.coach in ("diego", "sofia") and args.language == "Spanish" else []
        subprocess.run(["ffmpeg", "-v", "error", "-i", args.audio, "-vn", *pace, "-ar", "16000",
                        "-ac", "1", "-c:a", "pcm_s16le", wav], check=True)
        subprocess.run([sys.executable, str(ROOT/"render/run_cpu.py"), os.environ["IMT_SOURCE"],
                        os.environ["IMT_CHECKPOINTS"], str(ROOT / "render" / (args.coach + ".jpg")), str(wav),
                        str(raw), str(tmp/"crop.png"), "10", "3"], check=True)
        subprocess.run(["ffmpeg", "-v", "error", "-i", raw, "-i", wav, "-map", "0:v:0",
                        "-map", "1:a:0", "-c:v", "libx264", "-pix_fmt", "yuv420p",
                        "-c:a", "aac", "-movflags", "+faststart", "-shortest", output], check=True)
        register(output, args.title, args.language, args.coach)

if __name__ == "__main__":
    main()
