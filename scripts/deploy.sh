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

# Ensure scripts are executable (git reset can lose +x on some setups)
chmod +x "$INSTALL_DIR"/*.sh "$INSTALL_DIR"/swiftbar/*.py 2>/dev/null

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
LOCK_SRC="$INSTALL_DIR/swiftbar/keyboard-lock.py"

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
        chmod +x "$SWIFTBAR_PLUGIN"
        echo "   ✅ SwiftBar plugin updated"
    fi
    rm -rf "$SWIFTBAR_DIR/README.md"
    defaults write com.ameba.SwiftBar PluginDirectory "$SWIFTBAR_DIR" 2>/dev/null || true
    if [ -f "$LOCK_SRC" ]; then
        cp "$LOCK_SRC" "$SWIFTBAR_DIR/keyboard-lock.py"
        chmod +x "$SWIFTBAR_DIR/keyboard-lock.py"
        echo "   ✅ keyboard-lock.py updated"
    fi
elif [ -f "$PLUGIN_SRC" ]; then
    mkdir -p "$SWIFTBAR_DIR"
    cp "$PLUGIN_SRC" "$SWIFTBAR_DIR/$PLUGIN_NAME"
    chmod +x "$SWIFTBAR_DIR/$PLUGIN_NAME"
    rm -rf "$SWIFTBAR_DIR/README.md"
    defaults write com.ameba.SwiftBar PluginDirectory "$SWIFTBAR_DIR" 2>/dev/null || true
    if [ -f "$LOCK_SRC" ]; then
        cp "$LOCK_SRC" "$SWIFTBAR_DIR/keyboard-lock.py"
        chmod +x "$SWIFTBAR_DIR/keyboard-lock.py"
    fi
    echo "   ✅ SwiftBar plugin installed"
else
    echo "   ℹ️  SwiftBar plugin not installed"
fi

echo ""
echo "🎉 Done!"
