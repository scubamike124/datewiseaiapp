#!/usr/bin/env bash
# One-time setup of the avatar frame generator, OUTSIDE the repository.
# Everything goes to $AVATAR_TOOLS (default ~/.cache/datewise-avatar-tools):
# a Python venv (CPU PyTorch), LivePortrait's code (MIT) at a pinned commit,
# its human-face weights (MIT; the InsightFace models are NOT downloaded), and
# OpenCV Zoo's YuNet (MIT) and SFace (Apache-2.0). About 2.5 GB. No GPU needed.
# Every model file is fetched from a pinned revision and checked by SHA-256.
set -euo pipefail
T="${AVATAR_TOOLS:-$HOME/.cache/datewise-avatar-tools}"
LP_COMMIT=9b294b3d0536135442ea73cb01e6cb3ca7029dd3
LP_REV=82a4fa6735ca58432b6ce39301b4b9ee066dea47        # HF KlingTeam/LivePortrait
YUNET_REV=3cc26e7f1014a5ee5d74a42acee58bafc9d0a310     # HF opencv/face_detection_yunet
SFACE_REV=3d7082438a6e4551e840c9b2bb60b71e8da4b524     # HF opencv/face_recognition_sface
TORCH_VERSION=2.9.1   # >= 2.6: torch.load defaults to weights_only=True
HF=https://huggingface.co

if [ ! -d "$T" ] && [ "${AVATAR_YES:-}" != 1 ]; then
  if [ -t 0 ]; then
    read -r -p "Install the avatar generator (~2.5 GB) into $T? [y/N] " ok
    case "$ok" in y|Y|yes) ;; *) echo "cancelled"; exit 1;; esac
  else
    echo "Refusing to download ~2.5 GB without confirmation: rerun with AVATAR_YES=1." >&2; exit 1
  fi
fi
mkdir -p "$T/models"

# fetch <url> <dest> <sha256>: download to .part, verify, then move into place.
fetch() {
  local url="$1" dest="$2" sum="$3"
  if [ -s "$dest" ] && echo "$sum  $dest" | sha256sum -c --status; then return; fi
  mkdir -p "$(dirname "$dest")"
  curl -fsSL -o "$dest.part" "$url"
  echo "$sum  $dest.part" | sha256sum -c --quiet
  mv "$dest.part" "$dest"
}

if [ ! -x "$T/venv/bin/python" ]; then
  python3 -m venv "$T/venv"
  "$T/venv/bin/pip" install -q --index-url https://download.pytorch.org/whl/cpu "torch==$TORCH_VERSION"
  "$T/venv/bin/pip" install -q numpy scipy pyyaml onnxruntime imageio rich tqdm opencv-python-headless==4.10.0.84
  "$T/venv/bin/pip" cache purge >/dev/null || true
fi
if [ ! -d "$T/LivePortrait/.git" ]; then
  git clone -q https://github.com/KwaiVGI/LivePortrait.git "$T/LivePortrait"
fi
git -C "$T/LivePortrait" checkout -q "$LP_COMMIT"

W="$T/LivePortrait/pretrained_weights/liveportrait"
while read -r sum f; do
  fetch "$HF/KlingTeam/LivePortrait/resolve/$LP_REV/liveportrait/$f" "$W/$f" "$sum"
done <<'SUMS'
5279bb8654293dbdf327030b397f107237dd9212fb11dd75b83dfb635211ceb5 base_models/appearance_feature_extractor.pth
251e6a94ad667a1d0c69526d292677165110ef7f0cf0f6d199f0e414e8aa0ca5 base_models/motion_extractor.pth
4780afc7909a9f84e24c01d73b31a555ef651521a1fe3b2429bd04534d992aee base_models/spade_generator.pth
2f61a6f265fe344f14132364859a78bdbbc2068577170693da57fb96d636e282 base_models/warping_module.pth
3652d5a3f95099141a56986aaddec92fadf0a73c87a20fac9a2c07c32b28b611 retargeting_models/stitching_retargeting_module.pth
31d22a5041326c31f19b78886939a634a5aedcaa5ab8b9b951a1167595d147db landmark.onnx
SUMS
fetch "$HF/opencv/face_detection_yunet/resolve/$YUNET_REV/face_detection_yunet_2023mar.onnx" "$T/models/yunet.onnx" \
  8f2383e4dd3cfbb4553ea8718107fc0423210dc964f9f4280604804ed2552fa4
fetch "$HF/opencv/face_recognition_sface/resolve/$SFACE_REV/face_recognition_sface_2021dec.onnx" "$T/models/sface.onnx" \
  0ba9fbfa01b5270c96627c4ef784da859931e02f04419c829e83484087c34e79
echo "avatar tools ready in $T"
