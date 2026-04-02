#!/bin/bash
set -uo pipefail

# Configure PATH for cron jobs
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$PATH"

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

# 1. HOMEBREW UPDATES
if command -v brew &> /dev/null; then
    echo "🍺 Checking Homebrew..."
    brew update > /dev/null 2>&1
    OUTDATED_BREW=$(brew outdated -q 2>/dev/null || true)
    BREW_COUNT=$(echo "$OUTDATED_BREW" | grep -v '^$' | wc -l | xargs)

    if [ "$BREW_COUNT" -gt 0 ]; then
        echo "   Updates available: $BREW_COUNT"
        echo "   Packages: $(echo "$OUTDATED_BREW" | tr '\n' ' ')"

        if brew upgrade > /dev/null 2>&1; then
            brew cleanup -s > /dev/null 2>&1
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
if command -v mas &> /dev/null; then
    echo "📱 Checking App Store updates..."
    APP_STORE_UPDATES=$(mas outdated 2>/dev/null | wc -l | xargs || echo "0")

    if [ "$APP_STORE_UPDATES" -gt 0 ]; then
        echo "   Updates available: $APP_STORE_UPDATES"

        if mas upgrade > /dev/null 2>&1; then
            echo "✅ App Store apps updated"
            UPDATES_INSTALLED=$((UPDATES_INSTALLED + APP_STORE_UPDATES))
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
if command -v npm &> /dev/null; then
    echo "📦 Checking npm global packages..."
    NPM_OUTDATED=$({ npm outdated -g 2>/dev/null || true; } | tail -n +2 | wc -l | tr -d '[:space:]')

    if [ "$NPM_OUTDATED" -gt 0 ]; then
        echo "   Updates available: $NPM_OUTDATED"

        if npm upgrade -g 2>/dev/null; then
            echo "✅ npm global packages updated"
            UPDATES_INSTALLED=$((UPDATES_INSTALLED + NPM_OUTDATED))
        else
            echo "❌ Failed to upgrade npm packages"
        fi
    else
        echo "✅ All npm global packages are up to date"
    fi
fi

echo ""

# 4. PNPM GLOBAL PACKAGES (if installed)
if command -v pnpm &> /dev/null; then
    echo "📦 Checking pnpm global packages..."
    PNPM_OUTDATED=$({ pnpm outdated -g 2>/dev/null || true; } | tail -n +2 | wc -l | tr -d '[:space:]')

    if [ "$PNPM_OUTDATED" -gt 0 ]; then
        echo "   Updates available: $PNPM_OUTDATED"

        if pnpm upgrade -g 2>/dev/null; then
            echo "✅ pnpm global packages updated"
            UPDATES_INSTALLED=$((UPDATES_INSTALLED + PNPM_OUTDATED))
        else
            echo "❌ Failed to upgrade pnpm packages"
        fi
    else
        echo "✅ All pnpm global packages are up to date"
    fi
fi

echo ""

# 5. MACOS SYSTEM UPDATES
echo "🍎 Checking macOS system updates..."
SYSTEM_UPDATES=$({ softwareupdate -l 2>/dev/null || true; } | { grep "^   \*" || true; } | wc -l | tr -d '[:space:]')

if [ "$SYSTEM_UPDATES" -gt 0 ]; then
    echo "   Updates available: $SYSTEM_UPDATES"
    echo "   Run: sudo softwareupdate -ia"
    UPDATES_AVAILABLE=$((UPDATES_AVAILABLE + SYSTEM_UPDATES))
else
    echo "✅ macOS is up to date"
fi

echo ""
echo "$LOG_SEP"

# SUMMARY
END_SEC=$(date +%s)
RUNTIME=$((END_SEC - START_SEC))

echo "📊 SUMMARY"
echo "   Updates installed: $UPDATES_INSTALLED"
echo "   System updates available: $SYSTEM_UPDATES"
echo "   Runtime: $RUNTIME seconds"
echo "=== COMPLETED [$(date "+%H:%M:%S")] ==="
echo "$LOG_SEP"
echo ""

# NOTIFICATION
if command -v osascript &> /dev/null; then
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

    # Escape special characters for AppleScript
    MSG="${MSG//\\/\\\\}"
    MSG="${MSG//\"/\\\"}"
    SUBTITLE="${SUBTITLE//\\/\\\\}"
    SUBTITLE="${SUBTITLE//\"/\\\"}"

    osascript -e "display notification \"$MSG\" with title \"fuck cleanmymac\" subtitle \"$SUBTITLE\"" 2>/dev/null || true
fi
