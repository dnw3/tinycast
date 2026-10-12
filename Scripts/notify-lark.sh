#!/bin/bash
# Post a Feishu/Lark custom-bot message for the fork's sync workflows: notify-lark.sh <title> <link>,
# body lines on stdin. Skips quietly without LARK_WEBHOOK_URL; signs when LARK_WEBHOOK_SECRET is set.
set -euo pipefail

title=${1:?Usage: notify-lark.sh <title> <link>}
link=${2:-}
[ -n "${LARK_WEBHOOK_URL:-}" ] || { echo "LARK_WEBHOOK_URL is not set; skipping the notification."; exit 0; }

payload=$(jq -Rn --arg title "$title" --arg link "$link" '
    [inputs | select(length > 0) | [{tag: "text", text: .}]] as $lines
    | {msg_type: "post", content: {post: {zh_cn: {title: $title, content: (
        $lines + (if $link == "" then [] else [[{tag: "a", text: "打开", href: $link}]] end)
    )}}}}')

if [ -n "${LARK_WEBHOOK_SECRET:-}" ]; then
    timestamp=$(date +%s)
    # Feishu signs an empty message with "<timestamp>\n<secret>" as the HMAC key.
    sign=$(printf '' | openssl dgst -sha256 -hmac "$(printf '%s\n%s' "$timestamp" "$LARK_WEBHOOK_SECRET")" -binary | base64)
    payload=$(jq --arg timestamp "$timestamp" --arg sign "$sign" '. + {timestamp: $timestamp, sign: $sign}' <<< "$payload")
fi

response=$(curl -sS --max-time 15 -H 'Content-Type: application/json' -d "$payload" "$LARK_WEBHOOK_URL") || {
    echo "::warning::The Lark notification could not be sent."
    exit 0
}
echo "Lark replied: $response"
# A rejected message is a warning, never a failed sync: the PR itself is the record.
if [ "$(jq -r '.code // .StatusCode // 0' <<< "$response")" != "0" ]; then
    echo "::warning::Lark rejected the notification: $response"
fi
