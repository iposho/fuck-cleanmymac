#!/bin/bash
# Deploy the local repository to the installed copy at ~/.scripts/fuck-cleanmymac
# Usage: ./deploy.sh [--push]
#   (default) deploy the local `main` branch as committed — no network needed
#   --push    push to GitHub first, then deploy
#
# Uncommitted changes are NOT deployed: commit them first.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
INSTALL_DIR="$HOME/.scripts/fuck-cleanmymac"
BRANCH="main"

if [ ! -d "$INSTALL_DIR/.git" ]; then
    echo "❌ Installed repo not found at $INSTALL_DIR — run scripts/install.sh first"
    exit 1
fi

if [ -n "$(git -C "$REPO_DIR" status --porcelain --untracked-files=no)" ]; then
    echo "⚠️  $REPO_DIR has uncommitted changes; they will not be deployed."
fi

if [[ "${1:-}" == "--push" ]]; then
    echo "📤 Pushing to GitHub..."
    git -C "$REPO_DIR" push origin "$BRANCH"
fi

echo "📥 Updating installed copy from $REPO_DIR ($BRANCH)..."
git -C "$INSTALL_DIR" fetch --quiet "$REPO_DIR" "$BRANCH"
git -C "$INSTALL_DIR" reset --hard --quiet FETCH_HEAD
echo "   Installed: $(git -C "$INSTALL_DIR" log --oneline -1)"

# Re-create symlinks and the SwiftBar plugin link without touching the repo again.
"$INSTALL_DIR/scripts/install.sh" --no-pull --skip-deps --skip-cron

echo ""
echo "🎉 Done!"
