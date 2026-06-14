#!/usr/bin/env bash
# Install git hooks for this repo.
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
HOOKS_DIR="$REPO_ROOT/.git/hooks"

ln -sf "$REPO_ROOT/scripts/hooks/pre-commit.sh" "$HOOKS_DIR/pre-commit"
chmod +x "$HOOKS_DIR/pre-commit"

echo "Installed: .git/hooks/pre-commit -> scripts/hooks/pre-commit.sh"
