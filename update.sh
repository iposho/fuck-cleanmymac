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

fc_acquire_lock update || exit 0

LOG_DIR="$HOME/.scripts/logs"
fc_init_run_log "$LOG_DIR/update.log"

# We run `brew update` ourselves; keep brew quiet and non-interactive.
export HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ENV_HINTS=1 HOMEBREW_NO_INSTALL_CLEANUP=1

START_DATE=$(date "+%Y-%m-%d %H:%M:%S")
START_SEC=$(date +%s)
LOG_SEP="════════════════════════════════════════════════════════════════"

echo ""
echo "$LOG_SEP"
echo "=== UPDATE REPORT [$START_DATE] ==="
echo "$LOG_SEP"
echo ""

UPDATES_INSTALLED=0
UPDATES_FAILED=0
SYSTEM_UPDATES=0
NPM_USE_SUDO="${NPM_USE_SUDO:-false}"

indent() {
    sed 's/^/   /'
}

print_list() {
    local text="$1"
    local line
    while IFS= read -r line; do
        [ -n "$line" ] && echo "   • $line"
    done <<< "$text"
}

# Record the outcome of an upgrade step by re-checking what is still outdated.
record_result() {
    local label="$1"
    local before="$2"
    local after="$3"
    local done_count=$((before - after))
    [ "$done_count" -lt 0 ] && done_count=0

    UPDATES_INSTALLED=$((UPDATES_INSTALLED + done_count))
    if [ "$after" -eq 0 ]; then
        echo "✅ $label: $done_count updated"
    else
        UPDATES_FAILED=$((UPDATES_FAILED + after))
        echo "⚠️  $label: $done_count updated, $after still outdated (see output above)"
    fi
}

# 1. HOMEBREW
brew_outdated() {
    { brew outdated -q 2>/dev/null || true; } | grep '[^[:space:]]' || true
}

if fc_has_cmd brew; then
    echo "🍺 Checking Homebrew..."
    brew update 2>&1 | grep -v '^$' | indent || true
    OUTDATED_BREW=$(brew_outdated)

    if [ -n "$OUTDATED_BREW" ]; then
        BREW_COUNT=$(fc_count_lines "$OUTDATED_BREW")
        echo "   Updates available: $BREW_COUNT"
        print_list "$OUTDATED_BREW"
        echo "   Upgrading..."
        brew upgrade 2>&1 | indent || true
        brew cleanup -s --prune=all >/dev/null 2>&1 || true
        record_result "Homebrew" "$BREW_COUNT" "$(fc_count_lines "$(brew_outdated)")"
    else
        echo "✅ All Homebrew packages are up to date"
    fi
else
    echo "⚠️  Homebrew not found"
fi

echo ""

# 2. APP STORE
if fc_has_cmd mas; then
    echo "📱 Checking App Store updates..."
    MAS_OUTDATED=$({ fc_run_timeout 60 mas outdated 2>/dev/null || true; } | grep '[^[:space:]]' || true)

    if [ -n "$MAS_OUTDATED" ]; then
        MAS_COUNT=$(fc_count_lines "$MAS_OUTDATED")
        echo "   Updates available: $MAS_COUNT"
        print_list "$MAS_OUTDATED"
        echo "   Upgrading..."
        mas upgrade 2>&1 | indent || true
        MAS_LEFT=$({ mas outdated 2>/dev/null || true; } | grep '[^[:space:]]' || true)
        record_result "App Store" "$MAS_COUNT" "$(fc_count_lines "$MAS_LEFT")"
    else
        echo "✅ All App Store apps are up to date"
    fi
else
    echo "ℹ️  Install 'mas' for App Store updates: brew install mas"
fi

echo ""

# 3. NPM GLOBAL PACKAGES (every npm we can find: nvm default + Homebrew node)
npm_outdated() {
    { "$1" outdated -g --parseable 2>/dev/null || true; } | grep '[^[:space:]]' || true
}

update_npm_globals() {
    local npm_bin="$1"
    local prefix outdated count line pkg current latest
    prefix=$("$npm_bin" prefix -g 2>/dev/null) || return 0

    echo "📦 Checking npm global packages ($prefix)..."
    outdated=$(npm_outdated "$npm_bin")
    if [ -z "$outdated" ]; then
        echo "✅ All npm global packages are up to date"
        return 0
    fi

    count=$(fc_count_lines "$outdated")
    echo "   Updates available: $count"
    # parseable: <path>:<name>@<wanted>:<name>@<current>:<name>@<latest>:<location>
    while IFS=: read -r _ wanted current latest _; do
        pkg="${wanted%@*}"
        [ -n "$pkg" ] && echo "   • $pkg: ${current##*@} → ${latest##*@}"
    done <<< "$outdated"

    if [ ! -w "$prefix/lib/node_modules" ] && [ "$NPM_USE_SUDO" != true ]; then
        echo "⚠️  $prefix is not writable; skipping (set NPM_USE_SUDO=true to use sudo -n)"
        UPDATES_FAILED=$((UPDATES_FAILED + count))
        return 0
    fi

    echo "   Updating..."
    local cmd=("$npm_bin" update -g)
    [ "$NPM_USE_SUDO" = true ] && [ ! -w "$prefix/lib/node_modules" ] && cmd=(sudo -n "${cmd[@]}")
    "${cmd[@]}" 2>&1 | grep -v 'npm WARN EBADENGINE' | indent || true
    record_result "npm ($prefix)" "$count" "$(fc_count_lines "$(npm_outdated "$npm_bin")")"
}

NPM_SEEN=""
for npm_candidate in "$(command -v npm 2>/dev/null)" /opt/homebrew/bin/npm /usr/local/bin/npm; do
    [ -n "$npm_candidate" ] && [ -x "$npm_candidate" ] || continue
    npm_prefix=$("$npm_candidate" prefix -g 2>/dev/null) || continue
    case " $NPM_SEEN " in *" $npm_prefix "*) continue ;; esac
    NPM_SEEN="$NPM_SEEN $npm_prefix"
    update_npm_globals "$npm_candidate"
    echo ""
done

# 4. PNPM GLOBAL PACKAGES
if fc_has_cmd pnpm; then
    echo "📦 Checking pnpm global packages..."
    # JSON is stable across pnpm versions (the table output is not parseable).
    PNPM_OUTDATED=$({ pnpm outdated -g --format json 2>/dev/null || true; } | awk '
        /^  "[^"]+": \{/ { name = $1; gsub(/[":]/, "", name) }
        /"current":/ { cur = $2; gsub(/[",]/, "", cur) }
        /"latest":/ { lat = $2; gsub(/[",]/, "", lat) }
        /^  \}/ && name != "" { print name ": " cur " → " lat; name = "" }
    ')

    if [ -n "$PNPM_OUTDATED" ]; then
        PNPM_COUNT=$(fc_count_lines "$PNPM_OUTDATED")
        echo "   Updates available: $PNPM_COUNT"
        print_list "$PNPM_OUTDATED"
        echo "   Updating..."
        if pnpm update -g --latest 2>&1 | indent; then
            UPDATES_INSTALLED=$((UPDATES_INSTALLED + PNPM_COUNT))
            echo "✅ pnpm global packages updated"
        else
            UPDATES_FAILED=$((UPDATES_FAILED + PNPM_COUNT))
            echo "❌ Failed to update pnpm packages"
        fi
    else
        echo "✅ All pnpm global packages are up to date"
    fi
    echo ""
fi

# 5. MACOS SYSTEM UPDATES (check only — install needs sudo)
echo "🍎 Checking macOS system updates..."
SYSTEM_UPDATES_RAW=$({ fc_run_timeout 120 softwareupdate -l 2>/dev/null || true; } | { grep -E '^[[:space:]]*\*' || true; })

if [ -n "$SYSTEM_UPDATES_RAW" ]; then
    SYSTEM_UPDATES=$(fc_count_lines "$SYSTEM_UPDATES_RAW")
    echo "   Updates available: $SYSTEM_UPDATES"
    while IFS= read -r line; do
        echo "   •${line#*\*}"
    done <<< "$SYSTEM_UPDATES_RAW"
    echo "   Install via System Settings → General → Software Update (or: sudo softwareupdate -ia)"
else
    echo "✅ macOS is up to date"
fi

echo ""
echo "$LOG_SEP"

RUNTIME=$(( $(date +%s) - START_SEC ))

echo "📊 SUMMARY:"
echo "✅ Packages updated: $UPDATES_INSTALLED"
[ "$UPDATES_FAILED" -gt 0 ] && echo "⚠️  Not updated: $UPDATES_FAILED"
echo "🍎 System updates available: $SYSTEM_UPDATES"
echo "⏱️  Runtime: $RUNTIME seconds"
echo "=== COMPLETED [$(date "+%H:%M:%S")] ==="
echo "$LOG_SEP"
echo ""

if [ "$UPDATES_INSTALLED" -gt 0 ]; then
    MSG="Installed $UPDATES_INSTALLED updates"
    SUBTITLE="System is more up-to-date"
elif [ "$UPDATES_FAILED" -gt 0 ]; then
    MSG="$UPDATES_FAILED updates could not be installed"
    SUBTITLE="See update.log for details"
elif [ "$SYSTEM_UPDATES" -gt 0 ]; then
    MSG="$SYSTEM_UPDATES macOS updates available"
    SUBTITLE="Install them in System Settings"
else
    MSG="All packages are up to date"
    SUBTITLE="System is fully updated"
fi
[ "$UPDATES_FAILED" -gt 0 ] && [ "$UPDATES_INSTALLED" -gt 0 ] && SUBTITLE="$UPDATES_FAILED could not be installed, see update.log"

fc_notify "fuck cleanmymac" "$MSG" "$SUBTITLE"
