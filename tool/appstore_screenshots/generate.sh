#!/usr/bin/env bash
# Regenerates every App Store screenshot with one command:
#   tool/appstore_screenshots/generate.sh            # build web + capture
#   tool/appstore_screenshots/generate.sh --skip-build
# Extra arguments after the flag go to capture.mjs (e.g. --sizes ipad-13 --locales es).
# Default: every set, iPhone 6.9" and 6.5" and iPad 13", in English and Spanish.
#
# Needs Flutter, Python 3 (static server) and Node with Playwright:
#   (cd tool/appstore_screenshots && npm install && npx playwright install chromium)
# or point PLAYWRIGHT_MODULE at an existing Playwright install.
set -euo pipefail
cd "$(dirname "$0")/../.."

if [[ "${1:-}" == "--skip-build" ]]; then
  shift
else
  flutter pub get
  flutter build web --release --no-web-resources-cdn --dart-define=DW_FAKE_STORE=true --dart-define=DW_MOCK_AI=true
fi

PORT="${PORT:-$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1])')}"
python3 -m http.server "$PORT" --bind 127.0.0.1 --directory build/web >/dev/null 2>&1 &
SERVER=$!
trap 'kill $SERVER 2>/dev/null || true' EXIT
sleep 1

node tool/appstore_screenshots/capture.mjs --url "http://127.0.0.1:$PORT" \
  --web-root build/web --out docs/appstore/screenshots "$@"
