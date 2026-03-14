#!/bin/bash
# Pre-commit hook: warn when localization keys are deleted from Localizable.xcstrings.
# Xcode's String Catalog auto-management can silently remove keys that use
# custom extensions like "key".localized, which the extractor doesn't detect.
#
# Install: sourced by .git/hooks/pre-commit (or run standalone)

XCSTRINGS="NaarsCars/Resources/Localizable.xcstrings"

# Only check when the xcstrings file is staged
if ! git diff --cached --name-only | grep -q "$XCSTRINGS"; then
    exit 0
fi

# Extract deleted keys: lines like -    "some_key" : {
deleted_keys=$(git diff --cached -- "$XCSTRINGS" \
    | grep '^-' \
    | grep -v '^---' \
    | grep -oE '"[a-z][a-z0-9_]+" :' \
    | sed 's/ :$//' \
    | tr -d '"' \
    | sort -u)

# Remove any that were also added (i.e. just moved/reformatted)
added_keys=$(git diff --cached -- "$XCSTRINGS" \
    | grep '^+' \
    | grep -v '^+++' \
    | grep -oE '"[a-z][a-z0-9_]+" :' \
    | sed 's/ :$//' \
    | tr -d '"' \
    | sort -u)

truly_deleted=$(comm -23 <(echo "$deleted_keys") <(echo "$added_keys"))

if [ -z "$truly_deleted" ]; then
    exit 0
fi

count=$(echo "$truly_deleted" | wc -l | tr -d ' ')

echo ""
echo "WARNING: $count localization key(s) removed from Localizable.xcstrings:"
echo "$truly_deleted" | while read -r key; do
    echo "  - $key"
done
echo ""
echo "Xcode may have auto-pruned keys using the .localized extension."
echo "If this is intentional, commit with: git commit --no-verify"
exit 1
