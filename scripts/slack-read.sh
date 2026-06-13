#!/usr/bin/env bash
# TEMPORARY cert diagnostic. Read the TV-debug beacon timeline from Slack
# (conversations.history) and print it oldest->newest as plain text.
#
#   bash scripts/slack-read.sh            # last 40 messages
#   bash scripts/slack-read.sh 100        # last 100 messages
#   bash scripts/slack-read.sh 40 1700000000   # messages after a unix ts (oldest=)
#
# Reads SLACK_BOT_TOKEN + SLACK_TV_DEBUG_CHANNEL from .env.roku. Requires a bot
# token with channels:history (the bot must be invited to the channel).
# Remove this + the .env.roku Slack vars after cert.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [ -f ".env.roku" ]; then
    set -a; . ./.env.roku; set +a
fi

TOKEN="${SLACK_BOT_TOKEN:-}"
CHANNEL="${SLACK_TV_DEBUG_CHANNEL:-}"
LIMIT="${1:-40}"
OLDEST="${2:-0}"

if [ -z "$TOKEN" ] || [ -z "$CHANNEL" ]; then
    echo "✗ Set SLACK_BOT_TOKEN + SLACK_TV_DEBUG_CHANNEL in .env.roku"
    exit 2
fi

curl -s "https://slack.com/api/conversations.history?channel=${CHANNEL}&limit=${LIMIT}&oldest=${OLDEST}" \
    -H "Authorization: Bearer ${TOKEN}" \
| python3 -c '
import sys, json, datetime
d = json.load(sys.stdin)
if not d.get("ok"):
    print("✗ Slack error:", d.get("error")); sys.exit(1)
msgs = d.get("messages", [])
msgs.sort(key=lambda m: float(m.get("ts", "0")))
for m in msgs:
    ts = float(m.get("ts", "0"))
    local = datetime.datetime.fromtimestamp(ts).strftime("%H:%M:%S")
    text = (m.get("text") or "").replace("`", "").replace("*", "")
    print(local, "|", text)
'
