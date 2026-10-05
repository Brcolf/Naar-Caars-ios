#!/bin/bash
#
# verify-xcode-file-sync.sh
# NaarsCars
#
# Claude Code PostToolUse hook (Write/Edit). Warns when a .swift file was written
# somewhere Xcode will not compile it.
#
# Project layout (verified 2026-10-05):
#   * NaarsCars/NaarsCarsUITests/  is a PBXFileSystemSynchronizedRootGroup: files there are
#     auto-discovered by Xcode.
#   * NaarsCars/NaarsCars/          is also a synced root, but it only holds the asset catalog
#     and entitlements. Do not put Swift sources there.
#   * Everything else (NaarsCars/App, Core, Features, UI and NaarsCars/NaarsCarsTests) uses
#     classic Xcode groups: a new .swift file must be referenced in project.pbxproj or it is
#     silently ignored by the build. This hook checks for that reference by file name.
#
# Receives JSON on stdin with tool_input.file_path from Write/Edit tools.

set -euo pipefail

if command -v jq &>/dev/null; then
  FILE_PATH=$(cat | jq -r '.tool_input.file_path // empty')
else
  FILE_PATH=$(cat | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
fi

[ -z "${FILE_PATH:-}" ] && exit 0
[[ "$FILE_PATH" != *.swift ]] && exit 0

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PBXPROJ="$PROJECT_ROOT/NaarsCars/NaarsCars.xcodeproj/project.pbxproj"

if [[ "$FILE_PATH" != /* ]]; then
  FILE_PATH="$(cd "$(dirname "$FILE_PATH")" 2>/dev/null && pwd)/$(basename "$FILE_PATH")"
fi

# Only care about files inside the Xcode project directory.
[[ "$FILE_PATH" != "$PROJECT_ROOT/NaarsCars/"* ]] && exit 0

# Synced UI test root: auto-discovered.
[[ "$FILE_PATH" == "$PROJECT_ROOT/NaarsCars/NaarsCarsUITests/"* ]] && exit 0

# Swift sources must not live in the assets-only synced root.
if [[ "$FILE_PATH" == "$PROJECT_ROOT/NaarsCars/NaarsCars/"* ]]; then
  echo "WARNING: $FILE_PATH is inside NaarsCars/NaarsCars/, which holds only assets and entitlements." >&2
  echo "Put Swift sources under NaarsCars/App, Core, Features, UI (app) or NaarsCars/NaarsCarsTests (tests)." >&2
  exit 2
fi

# Classic groups: the file name must appear in project.pbxproj.
BASENAME="$(basename "$FILE_PATH")"
if grep -qF "/* $BASENAME */" "$PBXPROJ"; then
  exit 0
fi

echo "WARNING: $BASENAME is not referenced in project.pbxproj, so Xcode will not compile it." >&2
echo "Add it to the project (drag into the matching group in Xcode, or add a PBXFileReference" >&2
echo "plus PBXBuildFile for the right target). Consider 'Convert to Folder' on the group in" >&2
echo "Xcode 16+ to make the directory filesystem-synced." >&2
exit 2
