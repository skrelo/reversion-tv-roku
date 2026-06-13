#!/usr/bin/env bash
# Validate the BrightScript/SceneGraph, then package the sideload zip.
#
#   bash scripts/build.sh          # validate + build
#   bash scripts/build.sh --skip-validate
#
# First run only: `npm install` (installs the brighterscript validator).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SKIP_VALIDATE=0
for arg in "$@"; do
    case "$arg" in
        --skip-validate) SKIP_VALIDATE=1 ;;
    esac
done

if [ "$SKIP_VALIDATE" -eq 0 ]; then
    echo "==> Validating (brighterscript)…"
    if [ -x "./node_modules/.bin/bsc" ]; then
        BSC="./node_modules/.bin/bsc"
    else
        echo "    local bsc not found; using npx (run 'npm install' once to make this faster)"
        BSC="npx -y brighterscript@latest"
    fi
    # bsc reads bsconfig.json. Non-zero exit on any error → abort the build.
    if ! $BSC; then
        echo ""
        echo "✗ Validation failed — fix the errors above before sideloading."
        exit 1
    fi
    echo "✓ Validation passed."
fi

echo "==> Packaging…"
bash scripts/package.sh

# Auto-sideload only if a Roku device is configured (env vars or .env.roku).
# Otherwise skip silently — the stick may not be set up yet.
DEV_HOST="${ROKU_DEV_HOST:-}"
if [ -z "$DEV_HOST" ] && [ -f ".env.roku" ]; then
    DEV_HOST="$(grep -E '^ROKU_DEV_HOST=' .env.roku | head -n1 | cut -d= -f2- || true)"
fi

if [ -n "$DEV_HOST" ]; then
    echo "==> Roku device configured ($DEV_HOST) — deploying…"
    bash scripts/deploy.sh
else
    echo "✓ Done. No Roku device configured — skipping sideload."
    echo "  Sideload manually: upload out/reversion-tv-roku.zip at http://<device-ip>"
    echo "  Or set up .env.roku (ROKU_DEV_HOST + ROKU_DEV_PASSWORD) to auto-deploy."
fi
