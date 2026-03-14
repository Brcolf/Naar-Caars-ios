#!/bin/bash
# Pre-commit hook: reject commits containing sensitive files.
# Install: cp scripts/pre-commit-secrets-check.sh .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit

BLOCKED_PATTERNS=("*.p8" "GoogleService-Info.plist" "Secrets.swift" "*.p12" "*.key" ".env" ".env.local")

for pattern in "${BLOCKED_PATTERNS[@]}"; do
    files=$(git diff --cached --name-only --diff-filter=ACR | grep -E "$(echo "$pattern" | sed 's/\./\\./g; s/\*/.*/')" || true)
    if [ -n "$files" ]; then
        echo "ERROR: Commit blocked — sensitive file detected:"
        echo "$files"
        echo ""
        echo "If this is intentional, use: git commit --no-verify"
        exit 1
    fi
done

# Check for accidentally deleted localization keys
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -x "$SCRIPT_DIR/pre-commit-localization-check.sh" ]; then
    "$SCRIPT_DIR/pre-commit-localization-check.sh" || exit 1
fi

exit 0
