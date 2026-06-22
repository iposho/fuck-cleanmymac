#!/bin/bash
set -uo pipefail

# Resolve symlinks so SCRIPT_DIR points at the real script location
_src="${BASH_SOURCE[0]}"
while [ -L "$_src" ]; do
    _dir="$(cd -P "$(dirname "$_src")" && pwd)"
    _src="$(readlink "$_src")"
    [[ $_src != /* ]] && _src="$_dir/$_src"
done
SCRIPT_DIR="$(cd -P "$(dirname "$_src")" && pwd)"
unset _src _dir
# shellcheck source=./lib.sh
source "$SCRIPT_DIR/lib.sh"
fc_setup_path

LOG_DIR="$HOME/.scripts/logs"
fc_init_run_log "$LOG_DIR/update.log"

# Timings and separators
START_DATE=$(date "+%Y-%m-%d %H:%M:%S")
START_SEC=$(date +%s)
LOG_SEP="════════════════════════════════════════════════════════════════"

echo ""
echo "$LOG_SEP"
echo "=== UPDATE REPORT [$START_DATE] ==="
echo "$LOG_SEP"
echo ""

UPDATES_AVAILABLE=0
UPDATES_INSTALLED=0
NPM_USE_SUDO="${NPM_USE_SUDO:-false}"

# 1. HOMEBREW UPDATES
if fc_has_cmd brew; then
    echo "🍺 Checking Homebrew..."
    brew update 2>&1 | grep -v '^$' | sed 's/^/   /' || true
    OUTDATED_BREW=$({ brew outdated -q 2>/dev/null || true; } | grep '[^[:space:]]' || true)

    if [ -n "$OUTDATED_BREW" ]; then
        BREW_COUNT=$(echo "$OUTDATED_BREW" | wc -l | tr -d '[:space:]')
        echo "   Updates available: $BREW_COUNT"
        echo "$OUTDATED_BREW" | while IFS= read -r pkg; do
            echo "   • $pkg"
        done
        echo "   Upgrading..."
        if brew upgrade 2>&1 | sed 's/^/   /'; then
            brew cleanup -s > /dev/null 2>&1 || true
            echo "✅ Homebrew packages updated"
            UPDATES_INSTALLED=$((UPDATES_INSTALLED + BREW_COUNT))
        else
            echo "❌ Failed to upgrade Homebrew packages"
        fi
    else
        echo "✅ All Homebrew packages are up to date"
    fi
else
    echo "⚠️  Homebrew not found"
fi

echo ""

# 2. APP STORE UPDATES (if mas is installed)
if fc_has_cmd mas; then
    echo "📱 Checking App Store updates..."
    MAS_OUTDATED=$({ mas outdated 2>/dev/null || true; } | grep '[^[:space:]]' || true)

    if [ -n "$MAS_OUTDATED" ]; then
        MAS_COUNT=$(echo "$MAS_OUTDATED" | wc -l | tr -d '[:space:]')
        echo "   Updates available: $MAS_COUNT"
        echo "$MAS_OUTDATED" | while IFS= read -r line; do
            echo "   • $line"
        done
        echo "   Upgrading..."
        if mas upgrade 2>&1 | sed 's/^/   /'; then
            echo "✅ App Store apps updated"
            UPDATES_INSTALLED=$((UPDATES_INSTALLED + MAS_COUNT))
        else
            echo "❌ Failed to upgrade App Store apps"
        fi
    else
        echo "✅ All App Store apps are up to date"
    fi
else
    echo "ℹ️  Install 'mas' for App Store updates: brew install mas"
fi

echo ""

# 3. NPM GLOBAL PACKAGES
if fc_has_cmd npm; then
    echo "📦 Checking npm global packages..."
    NPM_OUTDATED_RAW=$({ npm outdated -g 2>/dev/null || true; } | tail -n +2 | grep '[^[:space:]]' || true)

    if [ -n "$NPM_OUTDATED_RAW" ]; then
        NPM_OUTDATED=$(echo "$NPM_OUTDATED_RAW" | wc -l | tr -d '[:space:]')
        echo "   Updates available: $NPM_OUTDATED"
        echo "$NPM_OUTDATED_RAW" | while IFS= read -r line; do
            pkg=$(echo "$line" | awk '{print $1}')
            current=$(echo "$line" | awk '{print $2}')
            latest=$(echo "$line" | awk '{print $4}')
            echo "   • $pkg: $current → $latest"
        done
        echo "   Updating..."
        if [ "$NPM_USE_SUDO" = true ]; then
            npm_update_cmd=(sudo -n npm update -g)
        else
            npm_update_cmd=(npm update -g)
        fi

        if "${npm_update_cmd[@]}" 2>&1 | grep -v 'npm WARN EBADENGINE' | sed 's/^/   /'; then
            echo "✅ npm global packages updated"
            UPDATES_INSTALLED=$((UPDATES_INSTALLED + NPM_OUTDATED))
        else
            if [ "$NPM_USE_SUDO" = true ]; then
                echo "❌ Failed to update npm packages with sudo -n (no interactive prompt allowed)"
            else
                echo "❌ Failed to update npm packages (try user-level npm prefix or NPM_USE_SUDO=true)"
            fi
        fi
    else
        echo "✅ All npm global packages are up to date"
    fi
fi

echo ""

# 4. PNPM GLOBAL PACKAGES (if installed)
if fc_has_cmd pnpm; then
    echo "📦 Checking pnpm global packages..."
    PNPM_OUTDATED_RAW=$({ pnpm outdated -g 2>/dev/null || true; } | tail -n +2 | grep '[^[:space:]]' || true)

    if [ -n "$PNPM_OUTDATED_RAW" ]; then
        PNPM_OUTDATED=$(echo "$PNPM_OUTDATED_RAW" | wc -l | tr -d '[:space:]')
        echo "   Updates available: $PNPM_OUTDATED"
        echo "$PNPM_OUTDATED_RAW" | while IFS= read -r line; do
            pkg=$(echo "$line" | awk '{print $1}')
            current=$(echo "$line" | awk '{print $2}')
            latest=$(echo "$line" | awk '{print $4}')
            echo "   • $pkg: $current → $latest"
        done
        echo "   Updating..."
        if pnpm update -g 2>&1 | sed 's/^/   /'; then
            echo "✅ pnpm global packages updated"
            UPDATES_INSTALLED=$((UPDATES_INSTALLED + PNPM_OUTDATED))
        else
            echo "❌ Failed to update pnpm packages"
        fi
    else
        echo "✅ All pnpm global packages are up to date"
    fi
fi

echo ""

# 5. MACOS SYSTEM UPDATES
echo "🍎 Checking macOS system updates..."
SYSTEM_UPDATES_RAW=$({ softwareupdate -l 2>/dev/null || true; } | { grep "^   \*" || true; })

if [ -n "$SYSTEM_UPDATES_RAW" ]; then
    SYSTEM_UPDATES=$(echo "$SYSTEM_UPDATES_RAW" | wc -l | tr -d '[:space:]')
    echo "   Updates available: $SYSTEM_UPDATES"
    echo "$SYSTEM_UPDATES_RAW" | while IFS= read -r line; do
        echo "   •$line"
    done
    echo "   Run: sudo softwareupdate -ia"
    UPDATES_AVAILABLE=$((UPDATES_AVAILABLE + SYSTEM_UPDATES))
else
    SYSTEM_UPDATES=0
    echo "✅ macOS is up to date"
fi

echo ""
echo "$LOG_SEP"

# SUMMARY
END_SEC=$(date +%s)
RUNTIME=$((END_SEC - START_SEC))

echo "📊 SUMMARY:"
echo "✅ Packages updated: $UPDATES_INSTALLED"
echo "✅ System updates available: $SYSTEM_UPDATES"
echo "⏱️  Runtime: $RUNTIME seconds"
echo "=== COMPLETED [$(date "+%H:%M:%S")] ==="
echo "$LOG_SEP"
echo ""

# NOTIFICATION
if [ "$UPDATES_INSTALLED" -gt 0 ]; then
    MSG="Installed $UPDATES_INSTALLED updates"
    SUBTITLE="System is more up-to-date"
elif [ "$SYSTEM_UPDATES" -gt 0 ]; then
    MSG="$SYSTEM_UPDATES system updates available"
    SUBTITLE="macOS updates require sudo to install"
else
    MSG="All packages are up to date"
    SUBTITLE="System is fully updated"
fi

fc_notify "fuck cleanmymac" "$MSG" "$SUBTITLE"
