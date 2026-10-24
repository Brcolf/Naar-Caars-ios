#!/bin/bash
# Validate that Swift enum, Swift registry, TypeScript notification types and the SQL
# notifications.valid_notification_type CHECK stay in sync.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SWIFT_FILE="${ROOT_DIR}/NaarsCars/Core/Models/AppNotification.swift"
REGISTRY_FILE="${ROOT_DIR}/NaarsCars/Core/Models/NotificationTypeRegistry.swift"
TS_FILE="${ROOT_DIR}/supabase/functions/_shared/notificationTypes.ts"

# The migration that last defines notifications.valid_notification_type. It is named, not found
# by sorting: supabase/migrations mixes YYYYMMDD_XXXX_ and YYYYMMDDHHMMSS_ names, which do not
# sort by date against each other. Whoever next changes the CHECK points this at the new file in
# the same change (CLAUDE.md Notification rule 7). SQL_FILE=<path> overrides it.
SQL_CHECK_FILE="${SQL_FILE:-supabase/migrations/20261019_0001_phase4_registry_and_timezone.sql}"
if [[ "${SQL_CHECK_FILE}" != /* ]]; then
  SQL_CHECK_FILE="${ROOT_DIR}/${SQL_CHECK_FILE}"
fi

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

if [[ ! -f "${SQL_CHECK_FILE}" ]]; then
  echo "No migration defines valid_notification_type: ${SQL_CHECK_FILE}"
  exit 1
fi

# Line of the file's last "add constraint valid_notification_type".
SQL_CHECK_LINE="$(grep -n -i 'add constraint valid_notification_type' "${SQL_CHECK_FILE}" | tail -1 | cut -d: -f1 || true)"
if [[ -z "${SQL_CHECK_LINE}" ]]; then
  echo "${SQL_CHECK_FILE} does not define valid_notification_type"
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

# Every '...' literal from that line to the next ";" (SQL line comments stripped first).
SQL_TYPES="$(
  tail -n +"${SQL_CHECK_LINE}" "${SQL_CHECK_FILE}" \
    | sed 's/--.*$//' \
    | awk '{ print } /;/ { exit }' \
    | grep -o "'[^']*'" \
    | tr -d "'" \
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

SWIFT_SQL_DIFF="$(diff <(echo "${SWIFT_TYPES}") <(echo "${SQL_TYPES}") || true)"

if [[ -n "${SWIFT_SQL_DIFF}" ]]; then
  echo "MISMATCH between Swift enum and the SQL CHECK (${SQL_CHECK_FILE#"${ROOT_DIR}/"}):"
  echo "${SWIFT_SQL_DIFF}"
  exit 1
fi

COUNT="$(echo "${SWIFT_TYPES}" | wc -l | tr -d ' ')"
echo "Notification types validated: ${COUNT} types in sync across Swift enum, NotificationTypeRegistry, TypeScript registry and the SQL CHECK."
