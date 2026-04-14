#!/bin/bash
# Deploy local changes to the installed copy at ~/.scripts/fuck-cleanmymac
# Usage: ./deploy.sh [--push]
#   --push  also push to GitHub before deploying

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
INSTALL_DIR="$HOME/.scripts/fuck-cleanmymac"

if [ ! -d "$INSTALL_DIR/.git" ]; then
    echo "❌ Installed repo not found at $INSTALL_DIR"
    exit 1
fi

# Optionally push to GitHub first
if [[ "${1:-}" == "--push" ]]; then
    echo "📤 Pushing to GitHub..."
    if ! git -C "$REPO_DIR" push origin main; then
        echo "❌ Push failed"
        exit 1
    fi
fi

# Pull changes in installed copy
echo "📥 Updating installed copy..."
if ! git -C "$INSTALL_DIR" fetch origin; then
    echo "❌ Fetch failed — check network connection"
    exit 1
fi
if ! git -C "$INSTALL_DIR" reset --hard origin/main; then
    echo "❌ Reset failed"
    exit 1
fi

# Verify symlinks
echo ""
echo "✅ Deployed. Symlink status:"
for script in cleaner.sh update.sh health.sh; do
    target="$HOME/.scripts/$script"
    if [ -L "$target" ]; then
        echo "   $script → $(readlink "$target")"
    elif [ -f "$target" ]; then
        echo "   ⚠️  $script is a regular file (not a symlink)"
    else
        echo "   ❌ $script not found"
    fi
done

# Check SwiftBar plugin (may be a file or inside a .py bundle directory)
SWIFTBAR_DIR="$HOME/Library/Application Support/SwiftBar/Plugins"
PLUGIN_NAME="system-monitor.5s.py"
PLUGIN_SRC="$INSTALL_DIR/swiftbar/$PLUGIN_NAME"

if [ -f "$SWIFTBAR_DIR/$PLUGIN_NAME" ]; then
    SWIFTBAR_PLUGIN="$SWIFTBAR_DIR/$PLUGIN_NAME"
elif [ -f "$SWIFTBAR_DIR/$PLUGIN_NAME/$PLUGIN_NAME" ]; then
    SWIFTBAR_PLUGIN="$SWIFTBAR_DIR/$PLUGIN_NAME/$PLUGIN_NAME"
else
    SWIFTBAR_PLUGIN=""
fi

if [ -n "$SWIFTBAR_PLUGIN" ]; then
    if [ -L "$SWIFTBAR_PLUGIN" ]; then
        echo "   $PLUGIN_NAME → $(readlink "$SWIFTBAR_PLUGIN")"
    else
        echo "   ⚠️  SwiftBar plugin is a copy — updating..."
        cp "$PLUGIN_SRC" "$SWIFTBAR_PLUGIN"
        echo "   ✅ SwiftBar plugin updated"
    fi
else
    echo "   ℹ️  SwiftBar plugin not installed"
fi

echo ""
echo "🎉 Done!"
