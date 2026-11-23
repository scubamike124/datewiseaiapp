#!/usr/bin/env bash
# Rebuild every talking-avatar frame from the portraits in assets/coaches/.
# Run from anywhere after replacing the portraits (e.g. the owner's finals):
#
#   tool/avatar/regenerate.sh                 # all four coaches
#   tool/avatar/regenerate.sh --coaches ava   # one coach
#
# Installs the generator on first use (tool/avatar/setup.sh), writes
# assets/avatar/<coach>/, and fails if any frame does not pass the identity
# and eye-colour gate. Review sheets go to $AVATAR_REVIEW (default
# build/avatar-review/). Then run `flutter test test/avatar_widget_test.dart`.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
export AVATAR_TOOLS="${AVATAR_TOOLS:-$HOME/.cache/datewise-avatar-tools}"
PY="${AVATAR_PYTHON:-$AVATAR_TOOLS/venv/bin/python}"
if [ ! -x "$PY" ] || [ ! -s "$AVATAR_TOOLS/models/sface.onnx" ]; then "$ROOT/tool/avatar/setup.sh"; fi
cd "$ROOT"
"$PY" -u tool/avatar/gen_frames.py --portraits assets/coaches --out assets/avatar \
  --review "${AVATAR_REVIEW:-build/avatar-review}" "$@"
