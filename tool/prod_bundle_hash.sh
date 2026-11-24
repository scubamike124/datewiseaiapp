#!/usr/bin/env bash
# Prints the sha256 of the PRODUCTION Worker bundle (no --env, no credentials, nothing uploaded) so a change can prove
# that production is byte-identical before and after:
#   git worktree add --detach ../base <base-commit>
#   tool/prod_bundle_hash.sh ../base/backend      # before
#   tool/prod_bundle_hash.sh backend              # after: worker.js must match; worker.js.map embeds the checkout folder name
# Same wrangler version as the deploy workflow.
set -euo pipefail
dir="$(cd "${1:?usage: prod_bundle_hash.sh <backend dir>}" && pwd)"
out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT
(cd "$dir" && npx --yes wrangler@4.158.0 deploy --dry-run --outdir "$out" >/dev/null 2>&1)
(cd "$out" && sha256sum worker.js && sed "s#$(basename "$(cd "$dir/.." && pwd)")#CHECKOUT#g" worker.js.map | sha256sum | sed 's#-$#worker.js.map (checkout folder name normalized)#')
