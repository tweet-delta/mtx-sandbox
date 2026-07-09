#!/usr/bin/env bash
#
# Installs the repo's git hooks. Run once per clone:
#     bash scripts/install-hooks.sh
#
# Git hooks live in .git/hooks/ which is NOT committed, so each machine that
# clones this repo must install them once. This copies the tracked hook script
# into place and makes it executable.

set -eu
repo_root="$(git rev-parse --show-toplevel)"
src="$repo_root/scripts/pre-commit-secret-guard.sh"
dest="$repo_root/.git/hooks/pre-commit"

cp "$src" "$dest"
chmod +x "$dest"
echo "Installed pre-commit secret guard -> $dest"
