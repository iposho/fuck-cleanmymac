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

LOG_DIR="${LOG_DIR:-$HOME/.scripts/logs}"
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
CHECKS_FAILED=0
FAILED_SOURCES=""
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

non_blank() {
    printf '%s\n' "$1" | grep '[^[:space:]]' || true
}

# A check that could not run is never reported as "up to date".
check_failed() {
    local label="$1"
    local reason="exit code $CHECK_RC"
    [ "$CHECK_RC" -eq 124 ] && reason="timed out"
    CHECKS_FAILED=$((CHECKS_FAILED + 1))
    FAILED_SOURCES="${FAILED_SOURCES:+$FAILED_SOURCES, }$label"
    echo "❌ Could not check $label ($reason)"
    if [ -n "$CHECK_ERR" ]; then
        printf '%s\n' "$CHECK_ERR" | grep '[^[:space:]]' | head -8 | sed 's/^/   ! /'
    fi
}

# Record an upgrade by re-checking what is still outdated.
# Usage: record_result <label> <outdated before> <check rc ok?> <outdated after>
record_result() {
    local label="$1"
    local before="$2"
    local verified="$3"
    local after="$4"

    if [ "$verified" != true ]; then
        UPDATES_FAILED=$((UPDATES_FAILED + before))
        check_failed "$label (after upgrade)"
        echo "⚠️  $label: upgrade ran, but the result could not be verified"
        return
    fi

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

# ---------------------------------------------------------------------------
# 1. HOMEBREW
# ---------------------------------------------------------------------------
# brew_outdated: CHECK_RC=0 and CHECK_OUT = list on success
brew_outdated() {
    fc_capture fc_run_timeout 120 brew outdated -q
    CHECK_OUT=$(non_blank "$CHECK_OUT")
}

if fc_has_cmd brew; then
    echo "🍺 Checking Homebrew..."
    fc_capture fc_run_timeout 300 brew update
    if [ "$CHECK_RC" -ne 0 ]; then
        echo "⚠️  brew update failed (exit $CHECK_RC); checking against the current package index"
        printf '%s\n' "$CHECK_ERR" | grep '[^[:space:]]' | head -5 | sed 's/^/   ! /'
    fi

    brew_outdated
    if [ "$CHECK_RC" -ne 0 ]; then
        check_failed "Homebrew"
    elif [ -n "$CHECK_OUT" ]; then
        OUTDATED_BREW="$CHECK_OUT"
        BREW_COUNT=$(fc_count_lines "$OUTDATED_BREW")
        echo "   Updates available: $BREW_COUNT"
        print_list "$OUTDATED_BREW"
        echo "   Upgrading..."
        brew upgrade 2>&1 | indent || true
        brew cleanup -s --prune=all >/dev/null 2>&1 || true
        brew_outdated
        verified=false
        [ "$CHECK_RC" -eq 0 ] && verified=true
        record_result "Homebrew" "$BREW_COUNT" "$verified" "$(fc_count_lines "$CHECK_OUT")"
    else
        echo "✅ All Homebrew packages are up to date"
    fi
else
    echo "⚠️  Homebrew not found"
fi

echo ""

# ---------------------------------------------------------------------------
# 2. APP STORE
# ---------------------------------------------------------------------------
mas_outdated() {
    fc_capture fc_run_timeout 60 mas outdated
    CHECK_OUT=$(non_blank "$CHECK_OUT")
}

if fc_has_cmd mas; then
    echo "📱 Checking App Store updates..."
    mas_outdated
    if [ "$CHECK_RC" -ne 0 ]; then
        check_failed "App Store"
    elif [ -n "$CHECK_OUT" ]; then
        MAS_OUTDATED="$CHECK_OUT"
        MAS_COUNT=$(fc_count_lines "$MAS_OUTDATED")
        echo "   Updates available: $MAS_COUNT"
        print_list "$MAS_OUTDATED"
        echo "   Upgrading..."
        mas upgrade 2>&1 | indent || true
        mas_outdated
        verified=false
        [ "$CHECK_RC" -eq 0 ] && verified=true
        record_result "App Store" "$MAS_COUNT" "$verified" "$(fc_count_lines "$CHECK_OUT")"
    else
        echo "✅ All App Store apps are up to date"
    fi
else
    echo "ℹ️  Install 'mas' for App Store updates: brew install mas"
fi

echo ""

# ---------------------------------------------------------------------------
# 3. NPM GLOBAL PACKAGES (every npm we can find: nvm default + Homebrew node)
# ---------------------------------------------------------------------------
# `npm outdated` exits 1 when something IS outdated; that is a successful check.
npm_outdated() {
    fc_capture fc_run_timeout 120 "$1" outdated -g --parseable
    CHECK_OUT=$(non_blank "$CHECK_OUT")
    if [ "$CHECK_RC" -eq 1 ] && [ -n "$CHECK_OUT" ] && ! printf '%s' "$CHECK_ERR" | grep -q 'ERR!'; then
        CHECK_RC=0
    fi
}

update_npm_globals() {
    local npm_bin="$1"
    local prefix="$2"
    local outdated count pkg current latest

    echo "📦 Checking npm global packages ($prefix)..."
    npm_outdated "$npm_bin"
    if [ "$CHECK_RC" -ne 0 ]; then
        check_failed "npm ($prefix)"
        return 0
    fi
    outdated="$CHECK_OUT"
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

    npm_outdated "$npm_bin"
    local verified=false
    [ "$CHECK_RC" -eq 0 ] && verified=true
    record_result "npm ($prefix)" "$count" "$verified" "$(fc_count_lines "$CHECK_OUT")"
}

# UPDATE_NPM_BINS (space-separated) overrides the npm binaries to check, e.g. for tests.
NPM_SEEN=""
for npm_candidate in ${UPDATE_NPM_BINS:-"$(command -v npm 2>/dev/null)" /opt/homebrew/bin/npm /usr/local/bin/npm}; do
    [ -n "$npm_candidate" ] && [ -x "$npm_candidate" ] || continue
    fc_capture "$npm_candidate" prefix -g
    npm_prefix="$CHECK_OUT"
    if [ "$CHECK_RC" -ne 0 ] || [ -z "$npm_prefix" ]; then
        check_failed "npm at $npm_candidate"
        echo ""
        continue
    fi
    case " $NPM_SEEN " in *" $npm_prefix "*) continue ;; esac
    NPM_SEEN="$NPM_SEEN $npm_prefix"
    update_npm_globals "$npm_candidate" "$npm_prefix"
    echo ""
done

# ---------------------------------------------------------------------------
# 4. PNPM GLOBAL PACKAGES
# ---------------------------------------------------------------------------
if fc_has_cmd pnpm; then
    echo "📦 Checking pnpm global packages..."
    fc_capture fc_run_timeout 120 pnpm outdated -g --format json
    # exit 1 + JSON = something is outdated; "no importer manifest" = no global packages at all
    if printf '%s' "$CHECK_ERR$CHECK_OUT" | grep -q 'ERR_PNPM_NO_IMPORTER_MANIFEST_FOUND'; then
        CHECK_RC=0
        CHECK_OUT=""
    elif [ "$CHECK_RC" -eq 1 ] && printf '%s' "$CHECK_OUT" | grep -q '^{'; then
        CHECK_RC=0
    fi

    if [ "$CHECK_RC" -ne 0 ]; then
        check_failed "pnpm"
    else
        # JSON is stable across pnpm versions (the table output is not parseable).
        PNPM_OUTDATED=$(printf '%s\n' "$CHECK_OUT" | awk '
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
    fi
    echo ""
fi

# ---------------------------------------------------------------------------
# 5. MACOS SYSTEM UPDATES (check only — install needs sudo)
# ---------------------------------------------------------------------------
echo "🍎 Checking macOS system updates..."
fc_capture fc_run_timeout 180 softwareupdate -l
SU_ALL="$CHECK_OUT
$CHECK_ERR"
SYSTEM_UPDATES_RAW=$(printf '%s\n' "$SU_ALL" | grep -E '^[[:space:]]*\*' || true)

if [ -n "$SYSTEM_UPDATES_RAW" ]; then
    SYSTEM_UPDATES=$(fc_count_lines "$SYSTEM_UPDATES_RAW")
    echo "   Updates available: $SYSTEM_UPDATES"
    while IFS= read -r line; do
        echo "   •${line#*\*}"
    done <<< "$SYSTEM_UPDATES_RAW"
    echo "   Install via System Settings → General → Software Update (or: sudo softwareupdate -ia)"
elif [ "$CHECK_RC" -eq 0 ] && ! printf '%s' "$SU_ALL" | grep -qiE 'error|cannot|could not|failed|unable'; then
    echo "✅ macOS is up to date"
else
    check_failed "macOS updates"
fi

echo ""
echo "$LOG_SEP"

RUNTIME=$(( $(date +%s) - START_SEC ))

echo "📊 SUMMARY:"
echo "✅ Packages updated: $UPDATES_INSTALLED"
[ "$UPDATES_FAILED" -gt 0 ] && echo "⚠️  Not updated: $UPDATES_FAILED"
[ "$CHECKS_FAILED" -gt 0 ] && echo "❌ Could not check: $FAILED_SOURCES"
echo "🍎 System updates available: $SYSTEM_UPDATES"
echo "⏱️  Runtime: $RUNTIME seconds"
echo "=== COMPLETED [$(date "+%H:%M:%S")] ==="
echo "$LOG_SEP"
echo ""

if [ "$CHECKS_FAILED" -gt 0 ]; then
    MSG="Could not check: $FAILED_SOURCES"
    SUBTITLE="See update.log for the reason"
    [ "$UPDATES_INSTALLED" -gt 0 ] && MSG="Installed $UPDATES_INSTALLED updates. $MSG"
elif [ "$UPDATES_INSTALLED" -gt 0 ]; then
    MSG="Installed $UPDATES_INSTALLED updates"
    SUBTITLE="System is more up-to-date"
    [ "$UPDATES_FAILED" -gt 0 ] && SUBTITLE="$UPDATES_FAILED could not be installed, see update.log"
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

[ "${FC_NO_NOTIFY:-false}" = true ] || fc_notify "fuck cleanmymac" "$MSG" "$SUBTITLE"

# Non-zero exit when something could not be checked, so cron/CI can notice.
[ "$CHECKS_FAILED" -eq 0 ]
