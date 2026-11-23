#!/usr/bin/env bash
# One-time setup of the avatar frame generator, OUTSIDE the repository.
# Everything goes to $AVATAR_TOOLS (default ~/.cache/datewise-avatar-tools):
# a Python venv (CPU PyTorch), LivePortrait's code (MIT) at a pinned commit,
# its human-face weights (MIT; the InsightFace models are NOT downloaded), and
# OpenCV Zoo's YuNet (MIT) and SFace (Apache-2.0). About 2.5 GB. No GPU needed.
set -euo pipefail
T="${AVATAR_TOOLS:-$HOME/.cache/datewise-avatar-tools}"
LP_COMMIT=9b294b3d0536135442ea73cb01e6cb3ca7029dd3
HF=https://huggingface.co
mkdir -p "$T/models"
if [ ! -x "$T/venv/bin/python" ]; then
  python3 -m venv "$T/venv"
  "$T/venv/bin/pip" install -q --index-url https://download.pytorch.org/whl/cpu torch
  "$T/venv/bin/pip" install -q numpy scipy pyyaml onnxruntime imageio rich tqdm opencv-python-headless==4.10.0.84
  "$T/venv/bin/pip" cache purge >/dev/null || true
fi
if [ ! -d "$T/LivePortrait/.git" ]; then
  git clone -q https://github.com/KwaiVGI/LivePortrait.git "$T/LivePortrait"
fi
git -C "$T/LivePortrait" checkout -q "$LP_COMMIT"
W="$T/LivePortrait/pretrained_weights/liveportrait"
for f in base_models/appearance_feature_extractor.pth base_models/motion_extractor.pth \
         base_models/spade_generator.pth base_models/warping_module.pth \
         retargeting_models/stitching_retargeting_module.pth landmark.onnx; do
  [ -s "$W/$f" ] || { mkdir -p "$(dirname "$W/$f")"; curl -fsSL -o "$W/$f" "$HF/KlingTeam/LivePortrait/resolve/main/liveportrait/$f"; }
done
[ -s "$T/models/yunet.onnx" ] || curl -fsSL -o "$T/models/yunet.onnx" "$HF/opencv/face_detection_yunet/resolve/main/face_detection_yunet_2023mar.onnx"
[ -s "$T/models/sface.onnx" ] || curl -fsSL -o "$T/models/sface.onnx" "$HF/opencv/face_recognition_sface/resolve/main/face_recognition_sface_2021dec.onnx"
echo "avatar tools ready in $T"
