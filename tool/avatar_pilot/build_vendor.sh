#!/usr/bin/env bash
# Rebuilds assets/avatar_pilot/vendor/{simli,anam}.js: the vendors' MIT-licensed JS SDKs
# bundled into one file each, so the app never loads vendor code from a CDN at runtime.
# Pinned versions; needs node + npm and network access to the npm registry (build time only).
#   tool/avatar_pilot/build_vendor.sh
set -euo pipefail
SIMLI_VERSION=3.2.0   # npm: simli-client (MIT)   https://www.npmjs.com/package/simli-client
ANAM_VERSION=4.29.3   # npm: @anam-ai/js-sdk (MIT) https://www.npmjs.com/package/@anam-ai/js-sdk
ESBUILD_VERSION=0.24.0
out="$(cd "$(dirname "$0")/../.." && pwd)/assets/avatar_pilot/vendor"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cd "$tmp"
npm init -y >/dev/null
npm i --silent --ignore-scripts "simli-client@$SIMLI_VERSION" "@anam-ai/js-sdk@$ANAM_VERSION" "esbuild@$ESBUILD_VERSION"
cat > e_simli.js <<'JS'
import { SimliClient, LogLevel } from 'simli-client';
window.DWVendor = Object.assign(window.DWVendor || {}, { simli: { SimliClient, LogLevel } });
JS
cat > e_anam.js <<'JS'
import { createClient, AnamEvent } from '@anam-ai/js-sdk';
window.DWVendor = Object.assign(window.DWVendor || {}, { anam: { createClient, AnamEvent } });
JS
mkdir -p "$out"
npx esbuild e_simli.js --bundle --minify --format=iife --target=safari15 --outfile="$out/simli.js"
npx esbuild e_anam.js --bundle --minify --format=iife --target=safari15 --outfile="$out/anam.js"
cp node_modules/simli-client/LICENSE "$out/LICENSE.simli-client.txt"
echo "simli-client $SIMLI_VERSION, @anam-ai/js-sdk $ANAM_VERSION (MIT), bundled with esbuild $ESBUILD_VERSION" > "$out/VERSIONS.txt"
ls -la "$out"
