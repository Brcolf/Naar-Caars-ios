#!/bin/bash
#
# verify-xcode-file-sync.sh
# NaarsCars
#
# Claude Code PostToolUse hook for Write/Edit. Warns when a .swift file will not
# be compiled by Xcode:
#   - Only two folders are PBXFileSystemSynchronizedRootGroups and therefore
#     auto-discovered: NaarsCars/NaarsCars/ (app target) and NaarsCars/NaarsCarsUITests/.
#   - Everything else (NaarsCars/App, Core, Features, UI, NaarsCarsTests) uses explicit
#     file references in project.pbxproj. A new file there is invisible to the build
#     until it is added to the project in Xcode.
#
# Receives JSON on stdin with tool_input.file_path. Exit 0 = fine, exit 2 = warn
# (Claude Code shows stderr to the model).

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

# Not part of the iOS project at all (scripts, supabase functions, etc.)
[[ "$FILE_PATH" != "$PROJECT_ROOT/NaarsCars/"* ]] && exit 0
# Scripts/ holds helper scripts, not app sources
[[ "$FILE_PATH" == "$PROJECT_ROOT/NaarsCars/Scripts/"* ]] && exit 0

SYNCED_APP="$PROJECT_ROOT/NaarsCars/NaarsCars"
SYNCED_UITESTS="$PROJECT_ROOT/NaarsCars/NaarsCarsUITests"

if [[ "$FILE_PATH" == "$SYNCED_APP"/* ]] || [[ "$FILE_PATH" == "$SYNCED_UITESTS"/* ]]; then
  exit 0   # synchronized folder: Xcode discovers it automatically
fi

BASENAME="$(basename "$FILE_PATH")"
if [ -f "$PBXPROJ" ] && grep -Fq "/* $BASENAME */" "$PBXPROJ"; then
  exit 0   # explicitly referenced already
fi

cat >&2 <<MSG
WARNING: $FILE_PATH is not referenced by project.pbxproj and is not inside a synchronized folder,
so Xcode will NOT compile it. Only these folders are auto-discovered:
  - NaarsCars/NaarsCars/        (app target)
  - NaarsCars/NaarsCarsUITests/ (UI tests)
NaarsCars/App, Core, Features, UI and NaarsCarsTests use explicit references.
Add the file to the project in Xcode (do not hand-edit project.pbxproj), then confirm it
compiles with BuildProject / xcodebuild and, for tests, appears in GetTestList.
MSG
exit 2
