#!/usr/bin/env bash
# Generate a SIGNED .pkg from the dev channel currently sideloaded on the Roku.
#
#   bash scripts/package-signed.sh
#
# Prerequisites (all already true for this channel):
#   - The channel is sideloaded on the device with a debug=false manifest
#     (run scripts/build.sh first so the running dev channel is the build you
#     want to package).
#   - A signing key exists on the device (genkey) and its password is in
#     .env.roku as ROKU_SIGN_PASSWORD.
#
# Device config + signing password are read from .env.roku:
#   ROKU_DEV_HOST, ROKU_DEV_PASSWORD (web login), ROKU_SIGN_PASSWORD (signing).
#
# The signed .pkg is downloaded to out/. Upload THAT file to the Roku Developer
# Dashboard (Package Upload), not the sideload zip.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# This environment forces grep to colorize (GREP_OPTIONS / GREP_COLORS), which
# injects ANSI escape codes into captured output and corrupts URLs/filenames.
# Neutralize it for this script.
unset GREP_OPTIONS GREP_COLORS 2>/dev/null || true
grep() { command grep --color=never "$@"; }

if [ -f ".env.roku" ]; then
    # shellcheck disable=SC1091
    set -a; . ./.env.roku; set +a
fi

HOST="${ROKU_DEV_HOST:-}"
WEB_PW="${ROKU_DEV_PASSWORD:-}"
USER_NAME="${ROKU_DEV_USER:-rokudev}"
SIGN_PW="${ROKU_SIGN_PASSWORD:-}"

if [ -z "$HOST" ] || [ -z "$WEB_PW" ] || [ -z "$SIGN_PW" ]; then
    echo "✗ Need ROKU_DEV_HOST + ROKU_DEV_PASSWORD + ROKU_SIGN_PASSWORD in .env.roku"
    exit 2
fi

# App name/version for the package label (from the manifest).
VER_MAJOR="$(grep -E '^major_version=' manifest | cut -d= -f2 | tr -d '\r')"
VER_MINOR="$(grep -E '^minor_version=' manifest | cut -d= -f2 | tr -d '\r')"
APP_NAME="ReversionTV/${VER_MAJOR:-1}.${VER_MINOR:-0}"
PKG_TIME="$(date +%s)000"

mkdir -p out

echo "==> Asking $HOST to build + sign the package ($APP_NAME) …"
RESP=$(curl -sS \
    --connect-timeout 10 \
    --user "${USER_NAME}:${WEB_PW}" --digest \
    -F "mysubmit=Package" \
    -F "app_name=${APP_NAME}" \
    -F "passwd=${SIGN_PW}" \
    -F "pkg_time=${PKG_TIME}" \
    "http://${HOST}/plugin_package")

# The response HTML links the generated pkg, e.g. href="pkgs//P<devid>.pkg".
# Strip escape/control chars first, then match only safe filename chars so no
# stray bytes leak into the URL (curl would treat [ ] as glob ranges).
PKG_FILE=$(printf '%s' "$RESP" | tr -d '\000-\037' | grep -oE 'P[A-Za-z0-9._-]+\.pkg' | head -n1 || true)

if [ -z "$PKG_FILE" ]; then
    echo "✗ No package link in the device response. Common causes:"
    echo "    - The sideloaded channel isn't a dev build, or no signing key on device."
    echo "    - Wrong ROKU_SIGN_PASSWORD."
    echo "  Raw response saved to out/package_response.html"
    printf '%s' "$RESP" > out/package_response.html
    exit 1
fi

OUT="out/ReversionTV-${VER_MAJOR:-1}.${VER_MINOR:-0}.pkg"
echo "==> Downloading signed package ($PKG_FILE) …"
# --globoff so curl doesn't treat any URL chars as glob ranges.
curl -sS --globoff \
    --user "${USER_NAME}:${WEB_PW}" --digest \
    -o "$OUT" \
    "http://${HOST}/pkgs/${PKG_FILE}"

if [ -s "$OUT" ]; then
    SIZE=$(wc -c < "$OUT" | tr -d ' ')
    echo "✓ Signed package: $OUT (${SIZE} bytes)"
    echo "  Upload this .pkg in the Roku Developer Dashboard → Package Upload."
else
    echo "✗ Download failed or empty file."
    exit 1
fi
