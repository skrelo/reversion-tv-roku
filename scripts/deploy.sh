#!/usr/bin/env bash
# Sideload the packaged channel zip to a Roku device in Developer Mode.
#
#   bash scripts/deploy.sh                 # uses .env.roku / env vars
#   ROKU_DEV_HOST=192.168.1.50 ROKU_DEV_PASSWORD=secret bash scripts/deploy.sh
#
# Device config is read from (in order): real env vars, then a gitignored
# .env.roku file at the repo root containing:
#   ROKU_DEV_HOST=192.168.1.50
#   ROKU_DEV_PASSWORD=yourdevpassword
#
# Enable Developer Mode on the Roku first (Home x3, Up x2, Right, Left, Right,
# Left, Right), set the web password, and note the device IP.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# Load .env.roku if present (without clobbering already-set env vars).
if [ -f ".env.roku" ]; then
    # shellcheck disable=SC1091
    set -a; . ./.env.roku; set +a
fi

HOST="${ROKU_DEV_HOST:-}"
PASSWORD="${ROKU_DEV_PASSWORD:-}"
USER_NAME="${ROKU_DEV_USER:-rokudev}"
ZIP="out/reversion-tv-roku.zip"

if [ -z "$HOST" ] || [ -z "$PASSWORD" ]; then
    echo "✗ Roku device not configured. Set ROKU_DEV_HOST + ROKU_DEV_PASSWORD"
    echo "  (env vars or a gitignored .env.roku file). Skipping deploy."
    exit 2
fi

if [ ! -f "$ZIP" ]; then
    echo "✗ $ZIP not found — run scripts/build.sh first."
    exit 1
fi

echo "==> Sideloading $ZIP to $HOST …"
# The dev web installer uses HTTP digest auth (user rokudev). Posting with
# mysubmit=Install + archive=@zip replaces the running dev channel.
HTTP_CODE=$(curl -sS -o /tmp/roku_deploy_resp.html -w '%{http_code}' \
    --connect-timeout 8 \
    --user "${USER_NAME}:${PASSWORD}" --digest \
    -F "mysubmit=Install" \
    -F "archive=@${ZIP}" \
    "http://${HOST}/plugin_install" || true)

if [ "$HTTP_CODE" = "200" ]; then
    if grep -qi "Application Received\|Install Success\|Identical to previous" /tmp/roku_deploy_resp.html 2>/dev/null; then
        echo "✓ Sideloaded to $HOST."
    else
        echo "✓ Upload returned 200 (check the TV for the running channel)."
    fi
elif [ "$HTTP_CODE" = "401" ]; then
    echo "✗ 401 Unauthorized — wrong ROKU_DEV_PASSWORD (user: ${USER_NAME})."
    exit 1
elif [ "$HTTP_CODE" = "000" ] || [ -z "$HTTP_CODE" ]; then
    echo "✗ Could not reach $HOST — check the IP and that the device is in Developer Mode."
    exit 1
else
    echo "✗ Sideload failed (HTTP $HTTP_CODE). See /tmp/roku_deploy_resp.html"
    exit 1
fi
