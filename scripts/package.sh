#!/usr/bin/env bash
# Package the channel into a sideloadable zip (out/reversion-tv-roku.zip).
# The zip must contain manifest/, source/, components/, images/ at its ROOT.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p out
OUT="out/reversion-tv-roku.zip"
rm -f "$OUT"

zip -r -q "$OUT" manifest source components images fonts \
    -x '*.DS_Store'

echo "Built $OUT"
unzip -l "$OUT" | tail -n +2 | head -n 5
