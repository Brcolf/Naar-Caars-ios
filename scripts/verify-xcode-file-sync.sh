#!/bin/bash
#
# verify-xcode-file-sync.sh
# NaarsCars
#
# Verifies that a newly written .swift file is under a PBXFileSystemSynchronizedRootGroup
# so Xcode will auto-discover it. Run as a Claude Code PostToolUse hook.
#
# Receives JSON on stdin with tool_input.file_path from Write/Edit tools.

set -euo pipefail

# Parse the file path from hook input JSON
if ! command -v jq &>/dev/null; then
  # Fallback: extract file_path with sed if jq isn't installed
  FILE_PATH=$(cat | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
else
  FILE_PATH=$(cat | jq -r '.tool_input.file_path // empty')
fi

# Nothing to check if we couldn't parse a path
[ -z "${FILE_PATH:-}" ] && exit 0

# Only check .swift files
[[ "$FILE_PATH" != *.swift ]] && exit 0

# Resolve project root (where .git lives)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# The two filesystem-synced root groups in the Xcode project
SYNCED_APP="$PROJECT_ROOT/NaarsCars/NaarsCars"
SYNCED_UITESTS="$PROJECT_ROOT/NaarsCars/NaarsCarsUITests"
SYNCED_TESTS="$PROJECT_ROOT/NaarsCars/NaarsCarsTests"

# Normalize to absolute path
if [[ "$FILE_PATH" != /* ]]; then
  FILE_PATH="$(cd "$(dirname "$FILE_PATH")" 2>/dev/null && pwd)/$(basename "$FILE_PATH")"
fi

# Check if file is under a synced root
if [[ "$FILE_PATH" == "$SYNCED_APP"/* ]] || \
   [[ "$FILE_PATH" == "$SYNCED_UITESTS"/* ]] || \
   [[ "$FILE_PATH" == "$SYNCED_TESTS"/* ]]; then
  exit 0
fi

# File is a .swift file outside synced roots — warn
echo "WARNING: $FILE_PATH is a .swift file outside Xcode's filesystem-synced groups." >&2
echo "Xcode will NOT auto-discover this file. Synced roots are:" >&2
echo "  - NaarsCars/NaarsCars/  (app target)" >&2
echo "  - NaarsCars/NaarsCarsTests/  (unit tests)" >&2
echo "  - NaarsCars/NaarsCarsUITests/  (UI tests)" >&2
echo "Move the file or add it to the Xcode project manually." >&2
exit 2
