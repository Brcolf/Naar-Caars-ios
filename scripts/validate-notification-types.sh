#!/bin/bash
# Validate that Swift enum, Swift registry, and TypeScript notification types stay in sync.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SWIFT_FILE="${ROOT_DIR}/NaarsCars/Core/Models/AppNotification.swift"
REGISTRY_FILE="${ROOT_DIR}/NaarsCars/Core/Models/NotificationTypeRegistry.swift"
TS_FILE="${ROOT_DIR}/supabase/functions/_shared/notificationTypes.ts"

if [[ ! -f "${SWIFT_FILE}" ]]; then
  echo "Missing Swift file: ${SWIFT_FILE}"
  exit 1
fi

if [[ ! -f "${TS_FILE}" ]]; then
  echo "Missing TypeScript file: ${TS_FILE}"
  exit 1
fi

if [[ ! -f "${REGISTRY_FILE}" ]]; then
  echo "Missing registry file: ${REGISTRY_FILE}"
  exit 1
fi

SWIFT_TYPES="$(
  sed -n '/^enum NotificationType:/,/^\/\/\/ In-app notification model/p' "${SWIFT_FILE}" \
    | awk -F'"' '/^[[:space:]]*case [a-zA-Z0-9]+ = "/ { print $2 }' \
    | sort -u
)"

TS_TYPES="$(
  awk -F"'" '/: '\''[a-z0-9_]+/ { print $2 }' "${TS_FILE}" | sort -u
)"

REGISTRY_TYPES="$(
  sed -n '/static let allTypes: Set<String> = \[/,/^[[:space:]]*]/p' "${REGISTRY_FILE}" \
    | awk -F'"' '/^[[:space:]]*"[^"]+"/ { print $2 }' \
    | sort -u
)"

SWIFT_TS_DIFF="$(diff <(echo "${SWIFT_TYPES}") <(echo "${TS_TYPES}") || true)"

if [[ -n "${SWIFT_TS_DIFF}" ]]; then
  echo "MISMATCH between Swift and TypeScript notification types:"
  echo "${SWIFT_TS_DIFF}"
  exit 1
fi

SWIFT_REGISTRY_DIFF="$(diff <(echo "${SWIFT_TYPES}") <(echo "${REGISTRY_TYPES}") || true)"

if [[ -n "${SWIFT_REGISTRY_DIFF}" ]]; then
  echo "MISMATCH between Swift enum and NotificationTypeRegistry:"
  echo "${SWIFT_REGISTRY_DIFF}"
  exit 1
fi

COUNT="$(echo "${SWIFT_TYPES}" | wc -l | tr -d ' ')"
echo "Notification types validated: ${COUNT} types in sync across Swift enum, NotificationTypeRegistry, and TypeScript registry."
