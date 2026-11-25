# Render Ava from audio

The shipped reference is Ava’s approved 10-second closed-mouth IMTalker study.
Ava’s source portrait is the corrected soft-smile JPEG exported in DateWise research.
The published player serves only media. Rendering happens on a separate machine.

On a render host, use IMTalker source revision bd91867, the IMTalker generator and renderer checkpoints and wav2vec2-base-960h folder, a MediaPipe face_landmarker.task model, ffmpeg, ffprobe and the CPU runner's Python dependencies. Set IMT_SOURCE, IMT_CHECKPOINTS and FACE_LANDMARKER to their paths. Run the command with the render environment's Python:

    python render/add_line.py recording.wav --title "Ava’s reply" --language English

The runner normalizes the audio to mono 16 kHz, crops the portrait using the face landmarks, and renders 512 px frames using seed 42, ten inference steps and an audio guidance scale of three. The new clip and catalog entry appear in dist/ava after encoding and validation. Review the mouth, eye movement and timing before publishing the private pilot. The approved reference remains the default. Reprocessing an identical encoded file updates one entry.

Sources: scubamike124/datewiseaiapp, revision cfb56c1738c51a892a1aa766f7824f40ccf746f9, under docs/research/portraits-2026-11-24/softsmile and docs/research/avatar-tech-2026-11-24/imtalker-cpu/tools.

## Environment used for the CPU integration

Python 3.12 with CPU PyTorch 2.5.1, torchvision 0.20.1, numpy 1.26.4, MediaPipe 0.10.21, transformers 4.46.3, PyAV 13.1.0, timm 1.0.9, pytorch-lightning 2.2.1, torchmetrics 1.4.3, torchdiffeq, librosa, einops and psutil. Use the official bigai-nlco/IMTalker source. Use the official Hugging Face cbsjtu01/IMTalker model files at revision 9e3149b and validate the file hashes against that revision before loading. The three model files occupy about 3.1 GB. The face landmarker is Google's MediaPipe face_landmarker/float16/1 model.

Select an additional DateWise portrait with --coach ethan, --coach diego, or --coach sofia. Pass --language Spanish for the Spanish recordings. The player displays the selected coach's name and language. Ethan and Sofía use the DateWise soft-smile portrait selections; Diego uses the DateWise coach avatar portrait.
