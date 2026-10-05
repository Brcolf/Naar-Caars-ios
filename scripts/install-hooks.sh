#!/bin/bash
#
# install-hooks.sh
# NaarsCars
#
# Installs the repository's git pre-commit hook as a thin wrapper so the checks
# keep running from scripts/ (where they can find each other) rather than being
# copied into .git/hooks, where pre-commit-secrets-check.sh could not locate
# pre-commit-localization-check.sh.
#
# Usage: scripts/install-hooks.sh

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
HOOK_DIR="$(git -C "$REPO_ROOT" rev-parse --git-path hooks)"
mkdir -p "$HOOK_DIR"

cat > "$HOOK_DIR/pre-commit" <<'EOF'
#!/bin/bash
# Installed by scripts/install-hooks.sh. Delegates to the versioned checks.
REPO_ROOT="$(git rev-parse --show-toplevel)"
exec "$REPO_ROOT/scripts/pre-commit-secrets-check.sh"
EOF
chmod +x "$HOOK_DIR/pre-commit"
chmod +x "$REPO_ROOT"/scripts/*.sh

echo "Installed pre-commit hook -> $HOOK_DIR/pre-commit"
