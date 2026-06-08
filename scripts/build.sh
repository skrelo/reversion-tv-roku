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
echo "✓ Done. Sideload out/reversion-tv-roku.zip"
