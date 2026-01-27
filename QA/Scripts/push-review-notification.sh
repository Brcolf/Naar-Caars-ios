#!/bin/bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  bash QA/Scripts/push-review-notification.sh [options]

Options:
  --type             review_request | review_reminder (default: review_request)
  --request          ride | favor (default: ride)
  --id               UUID for ride/favor (default: generated)
  --notification-id  UUID for notification_id (default: generated)
  --bundle           App bundle id (default: com.NaarsCars)
  --device           Simulator device (default: booted)
  --title            Notification title (default based on type)
  --body             Notification body (default based on request)
  -h, --help         Show this help

Examples:
  bash QA/Scripts/push-review-notification.sh --type review_request --request ride
  bash QA/Scripts/push-review-notification.sh --type review_reminder --request favor --id 9C0A7F52-2E8B-4E6B-93F5-36D9C2B5D6D1
  bash QA/Scripts/push-review-notification.sh --bundle com.NaarsCars --device booted
EOF
}

TYPE="review_request"
REQUEST="ride"
REQUEST_ID=""
NOTIFICATION_ID=""
BUNDLE_ID="com.NaarsCars"
DEVICE="booted"
TITLE=""
BODY=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --type)
      TYPE="$2"
      shift 2
      ;;
    --request)
      REQUEST="$2"
      shift 2
      ;;
    --id)
      REQUEST_ID="$2"
      shift 2
      ;;
    --notification-id)
      NOTIFICATION_ID="$2"
      shift 2
      ;;
    --bundle)
      BUNDLE_ID="$2"
      shift 2
      ;;
    --device)
      DEVICE="$2"
      shift 2
      ;;
    --title)
      TITLE="$2"
      shift 2
      ;;
    --body)
      BODY="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      usage
      exit 1
      ;;
  esac
done

if [[ "$TYPE" != "review_request" && "$TYPE" != "review_reminder" ]]; then
  echo "Invalid --type: $TYPE (expected review_request or review_reminder)"
  exit 1
fi

if [[ "$REQUEST" != "ride" && "$REQUEST" != "favor" ]]; then
  echo "Invalid --request: $REQUEST (expected ride or favor)"
  exit 1
fi

if ! command -v xcrun >/dev/null 2>&1; then
  echo "xcrun not found. Install Xcode command line tools."
  exit 1
fi

if [[ "$DEVICE" == "booted" ]]; then
  if ! xcrun simctl list devices booted | grep -q "(Booted)"; then
    echo "No booted simulator found."
    echo "Boot one with: xcrun simctl boot \"iPhone 15\""
    exit 1
  fi
fi

if [[ -z "$REQUEST_ID" ]]; then
  REQUEST_ID="$(uuidgen)"
fi

if [[ -z "$NOTIFICATION_ID" ]]; then
  NOTIFICATION_ID="$(uuidgen)"
fi

if [[ -z "$TITLE" ]]; then
  if [[ "$TYPE" == "review_request" ]]; then
    TITLE="Review requested"
  else
    TITLE="Review reminder"
  fi
fi

if [[ -z "$BODY" ]]; then
  if [[ "$REQUEST" == "ride" ]]; then
    BODY="Please leave a review for your ride."
  else
    BODY="Please leave a review for your favor."
  fi
fi

TMP_PAYLOAD="$(mktemp "/tmp/naarscars-push-XXXX.json")"
trap 'rm -f "$TMP_PAYLOAD"' EXIT

export TMP_PAYLOAD TYPE REQUEST REQUEST_ID NOTIFICATION_ID TITLE BODY
python3 - <<'PY'
import json
import os

payload_path = os.environ["TMP_PAYLOAD"]
notif_type = os.environ["TYPE"]
request_kind = os.environ["REQUEST"]
request_id = os.environ["REQUEST_ID"]
notification_id = os.environ["NOTIFICATION_ID"]
title = os.environ["TITLE"]
body = os.environ["BODY"]

request_key = "ride_id" if request_kind == "ride" else "favor_id"
payload = {
    "aps": {
        "alert": {
            "title": title,
            "body": body,
        },
        "sound": "default",
    },
    "type": notif_type,
    "notification_id": notification_id,
    request_key: request_id,
}

with open(payload_path, "w", encoding="utf-8") as handle:
    json.dump(payload, handle)
PY

echo "Sending $TYPE ($REQUEST) push to $BUNDLE_ID on device: $DEVICE"
echo "Payload: $TMP_PAYLOAD"
xcrun simctl push "$DEVICE" "$BUNDLE_ID" "$TMP_PAYLOAD"
echo "Done. Tap the notification on the simulator to verify the review modal."
