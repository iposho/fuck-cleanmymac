#!/bin/bash
# fuck-cleanmymac doctor: checks dependencies, installation, configuration, permissions,
# the SwiftBar plugin, scheduled runs and leftover state. Changes nothing.
#
# Usage: doctor.sh [--online]   (--online also fetches to see if an update is available)
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

# What an interactive shell sees, before we extend PATH like cron runs do.
USER_NPM=$(command -v npm 2>/dev/null || true)
fc_setup_path

ONLINE=false
case "${1:-}" in
    --online) ONLINE=true ;;
    -h|--help)
        sed -n '2,5p' "$0" | sed 's/^# \{0,1\}//'
        exit 0
        ;;
esac

INSTALL_DIR="$HOME/.scripts/fuck-cleanmymac"
BIN_DIR="$HOME/.scripts"
CONFIG_FILE="$HOME/.config/fuck-cleanmymac/cleaner.conf"
PLUGIN_NAME="system-monitor.5s.py"
SCRIPTS=(cleaner health update doctor)

N_OK=0
N_WARN=0
N_FAIL=0

section() { printf '\n%s\n' "$1"; }
pass() { N_OK=$((N_OK + 1)); printf '  ✅ %s\n' "$1"; }
info() { printf '  ℹ️  %s\n' "$1"; }
warn() {
    N_WARN=$((N_WARN + 1))
    printf '  ⚠️  %s\n' "$1"
    [ -n "${2:-}" ] && printf '      → %s\n' "$2"
    return 0
}
fail() {
    N_FAIL=$((N_FAIL + 1))
    printf '  ❌ %s\n' "$1"
    [ -n "${2:-}" ] && printf '      → %s\n' "$2"
    return 0
}

tilde() { printf '%s' "${1/#$HOME/~}"; }

age_text() {  # seconds → "5 min" / "3 h" / "12 days"
    local s="$1"
    if [ "$s" -lt 3600 ]; then echo "$((s / 60 + 1)) min"
    elif [ "$s" -lt 172800 ]; then echo "$((s / 3600)) h"
    else echo "$((s / 86400)) days"; fi
}

mtime_age() {  # seconds since a file changed
    echo $(( $(date +%s) - $(stat -f %m "$1" 2>/dev/null || date +%s) ))
}

echo "🩺 fuck-cleanmymac doctor — $(date '+%Y-%m-%d %H:%M')"
echo "   Running from $(tilde "$SCRIPT_DIR")"

# ---------------------------------------------------------------------------
section "📦 Dependencies"
pass "macOS $(sw_vers -productVersion 2>/dev/null) ($(uname -m))"

if fc_has_cmd git; then
    pass "git $(git --version | awk '{print $3}')"
else
    fail "git is missing (needed to install and update)" "xcode-select --install"
fi

PY=$(command -v python3 || true)
if [ -z "$PY" ]; then
    fail "python3 is missing (SwiftBar plugin, keyboard lock)" "xcode-select --install  or  brew install python"
elif [ "$PY" = /usr/bin/python3 ] && ! xcode-select -p >/dev/null 2>&1; then
    fail "/usr/bin/python3 is only a stub until the Command Line Tools are installed" "xcode-select --install"
elif PY_VER=$("$PY" -c 'import sys, ctypes; assert sys.version_info >= (3, 8); print("%d.%d.%d" % sys.version_info[:3])' 2>/dev/null); then
    pass "Python $PY_VER ($PY)"
else
    fail "$PY is older than 3.8 or lacks ctypes" "brew install python"
fi

if fc_has_cmd brew; then
    pass "Homebrew $(brew --version 2>/dev/null | head -1 | awk '{print $2}')"
else
    warn "Homebrew not found: package updates and Homebrew cleanup are skipped" "https://brew.sh"
fi

if fc_has_cmd smartctl; then pass "smartctl (SSD health)"; else warn "smartctl missing: no SSD health in health.sh" "brew install smartmontools"; fi
if fc_has_cmd mas; then pass "mas (App Store updates)"; else info "mas not installed: App Store apps are not updated (brew install mas)"; fi
if [ "$(uname -m)" = x86_64 ]; then
    if fc_has_cmd osx-cpu-temp; then pass "osx-cpu-temp"; else info "osx-cpu-temp not installed: no CPU temperature (brew install osx-cpu-temp)"; fi
fi

# Scheduled runs do not load your shell profile: make sure they find the same node.
CRON_NPM=$(env -i HOME="$HOME" PATH=/usr/bin:/bin bash -c "source '$SCRIPT_DIR/lib.sh'; fc_setup_path; command -v npm" 2>/dev/null || true)
if [ -n "$USER_NPM$CRON_NPM" ]; then
    if [ "$USER_NPM" = "$CRON_NPM" ] || [ -z "$USER_NPM" ]; then
        pass "npm for scheduled runs: $(tilde "${CRON_NPM:-none}")"
    else
        warn "cron/SwiftBar use $(tilde "$CRON_NPM"), your shell uses $(tilde "$USER_NPM")" \
            "update.sh still checks every npm it finds; set a numeric nvm default (nvm alias default 20) to align them"
    fi
fi

# ---------------------------------------------------------------------------
section "🧩 Installation"
if [ -d "$INSTALL_DIR/.git" ]; then
    INSTALLED_VERSION=$(fc_toolkit_version "$INSTALL_DIR")
    pass "Installed copy: $(tilde "$INSTALL_DIR") (v$INSTALLED_VERSION, $(git -C "$INSTALL_DIR" log -1 --format='%h %cd' --date=short 2>/dev/null))"

    if [ -n "$(git -C "$INSTALL_DIR" status --porcelain --untracked-files=no 2>/dev/null)" ]; then
        warn "Installed copy has local changes: updates will stop (git pull --ff-only fails)" \
            "git -C $(tilde "$INSTALL_DIR") stash   or   reset --hard origin/main"
    fi
    if [ "$ONLINE" = true ]; then
        fc_run_timeout 20 git -C "$INSTALL_DIR" fetch --quiet origin main >/dev/null 2>&1 \
            || warn "Could not reach GitHub to check for updates"
    fi
    if git -C "$INSTALL_DIR" rev-parse --verify --quiet origin/main >/dev/null; then
        BEHIND=$(git -C "$INSTALL_DIR" rev-list --count HEAD..origin/main 2>/dev/null || echo 0)
        AHEAD=$(git -C "$INSTALL_DIR" rev-list --count origin/main..HEAD 2>/dev/null || echo 0)
        when="checked just now"
        if [ "$ONLINE" != true ]; then
            fetch_head="$INSTALL_DIR/.git/FETCH_HEAD"
            when="as of the last fetch"
            [ -f "$fetch_head" ] && when="as of the last fetch, $(age_text "$(mtime_age "$fetch_head")") ago; --online re-checks"
        fi
        if [ "$BEHIND" -gt 0 ]; then
            warn "$BEHIND update(s) available ($when)" "SwiftBar → Update fuck-cleanmymac, or scripts/install.sh --skip-deps --skip-cron"
        else
            pass "Up to date with GitHub ($when)"
        fi
        [ "$AHEAD" -gt 0 ] && info "Installed copy has $AHEAD local commit(s) not on GitHub (deployed from a dev checkout?)"
    fi
    for f in lib.sh VERSION cleaner.sh health.sh update.sh doctor.sh swiftbar/$PLUGIN_NAME swiftbar/keyboard-lock.py; do
        [ -f "$INSTALL_DIR/$f" ] || fail "Installed copy is missing $f" "re-run scripts/install.sh"
    done
else
    fail "Not installed at $(tilde "$INSTALL_DIR")" \
        "curl -sL https://raw.githubusercontent.com/iposho/fuck-cleanmymac/main/scripts/install.sh | bash"
fi

for s in "${SCRIPTS[@]}"; do
    link="$BIN_DIR/$s.sh"
    if [ -L "$link" ]; then
        target=$(readlink "$link")
        if [ ! -e "$link" ]; then
            fail "$(tilde "$link") is a broken link → $(tilde "$target")" "re-run scripts/install.sh"
        elif [ ! -x "$link" ]; then
            fail "$(tilde "$link") is not executable" "chmod +x $(tilde "$target")"
        elif [[ "$target" != "$INSTALL_DIR/"* ]]; then
            warn "$(tilde "$link") points to $(tilde "$target"), not the installed copy"
        else
            pass "$(tilde "$link") → installed copy"
        fi
    elif [ -e "$link" ]; then
        warn "$(tilde "$link") is a standalone file (an old manual copy?) — it will not get updates" \
            "re-run scripts/install.sh (the file is backed up to ~/.scripts/backups)"
    else
        fail "$(tilde "$link") is missing" "re-run scripts/install.sh"
    fi
done

case ":$PATH:" in
    *":$BIN_DIR:"*) pass "~/.scripts is on PATH" ;;
    *) if grep -qs '\.scripts' "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.bash_profile"; then
           info "~/.scripts is in your shell config but not in this shell's PATH (open a new terminal)"
       else
           warn "~/.scripts is not on PATH" "echo 'export PATH=\"\$HOME/.scripts:\$PATH\"' >> ~/.zshrc"
       fi ;;
esac

# ---------------------------------------------------------------------------
section "⚙️  Configuration"
KNOWN_KEYS=" LOG_DIR LOG_RETENTION_DAYS VALIDATE_PATHS TEMP_FILE_AGE_DAYS SHOW_NOTIFICATION VERBOSE_MODE
 CLEAN_SYSTEM_CACHES CLEAN_APP_CACHES CLEAN_PACKAGE_MANAGERS CLEAN_BROWSER_CACHES CLEAN_TRASH CLEAN_TEMP_FILES CLEAN_DOCKER "
CFG=""
for f in "$CONFIG_FILE" "$HOME/.scripts/cleaner.conf"; do
    [ -f "$f" ] && { CFG="$f"; break; }
done
LOG_DIR="$HOME/.scripts/logs"
CLEAN_TRASH=true

if [ -z "$CFG" ]; then
    warn "No cleaner.conf: built-in defaults are used" "cp $(tilde "$INSTALL_DIR")/cleaner.conf ~/.config/fuck-cleanmymac/"
elif ! bash -n "$CFG" 2>/dev/null; then
    fail "$(tilde "$CFG") has a syntax error — cleaner.sh will stop" "bash -n $(tilde "$CFG")"
else
    pass "Config: $(tilde "$CFG")"
    # Typos (CLEAN_TRASHH=false) silently do nothing.
    while IFS= read -r key; do
        case "$KNOWN_KEYS" in
            *" $key "*) ;;
            *) warn "Unknown setting '$key' in $(tilde "$CFG") (typo?)" ;;
        esac
    done < <(sed -n 's/^[[:space:]]*\([A-Za-z_][A-Za-z0-9_]*\)=.*/\1/p' "$CFG" | sort -u)

    CFG_VALUES=$(
        # shellcheck source=/dev/null
        source "$CFG" >/dev/null 2>&1
        for v in $KNOWN_KEYS; do printf '%s=%s\n' "$v" "${!v-}"; done
    )
    cfg() { printf '%s\n' "$CFG_VALUES" | sed -n "s/^$1=//p"; }
    for v in $KNOWN_KEYS; do
        val=$(cfg "$v")
        [ -z "$val" ] && continue
        case "$v" in
            CLEAN_*|SHOW_NOTIFICATION|VERBOSE_MODE|VALIDATE_PATHS)
                [[ "$val" == true || "$val" == false ]] || fail "$v='$val' must be true or false" ;;
            LOG_RETENTION_DAYS|TEMP_FILE_AGE_DAYS)
                [[ "$val" =~ ^[0-9]+$ ]] || fail "$v='$val' must be a number of days" ;;
        esac
    done
    [ "$(cfg VALIDATE_PATHS)" = false ] && fail "VALIDATE_PATHS=false disables the path safety checks" "remove that line"
    [ -n "$(cfg LOG_DIR)" ] && LOG_DIR=$(cfg LOG_DIR)
    [ -n "$(cfg CLEAN_TRASH)" ] && CLEAN_TRASH=$(cfg CLEAN_TRASH)
    disabled=$(printf '%s\n' "$CFG_VALUES" | sed -n 's/^\(CLEAN_[A-Z_]*\)=false$/\1/p' | tr '\n' ' ')
    [ -n "$disabled" ] && info "Disabled cleanup categories: $disabled"
fi

# ---------------------------------------------------------------------------
section "🔐 Permissions"
for d in "$LOG_DIR" "$FC_STATE_DIR"; do
    if mkdir -p "$d" 2>/dev/null && probe=$(mktemp "$d/.doctor.XXXXXX" 2>/dev/null); then
        rm -f "$probe"
        pass "$(tilde "$d") is writable"
    else
        fail "Cannot write to $(tilde "$d")" "check ownership: ls -ld $(tilde "$d")"
    fi
done

if [ "$CLEAN_TRASH" = true ] && [ -d "$HOME/.Trash" ]; then
    if ls "$HOME/.Trash" >/dev/null 2>&1; then
        pass "Trash is accessible from this app"
    else
        warn "This app cannot read the Trash, so emptying it will fail here" \
            "System Settings → Privacy & Security → Full Disk Access → add your terminal (and /usr/sbin/cron for scheduled runs)"
    fi
fi

AX_CACHE="$FC_STATE_DIR/swiftbar-ax.cache"
if [ -f "$AX_CACHE" ]; then
    ax_age=$(age_text "$(mtime_age "$AX_CACHE")")
    if [ "$(cat "$AX_CACHE")" = 1 ]; then
        pass "SwiftBar has Accessibility permission (keyboard lock), checked $ax_age ago"
    else
        warn "SwiftBar has no Accessibility permission: keyboard lock will not work (checked $ax_age ago)" \
            "System Settings → Privacy & Security → Accessibility → enable SwiftBar"
    fi
else
    info "Accessibility for SwiftBar is unknown until the SwiftBar menu has been opened once"
fi

# ---------------------------------------------------------------------------
section "📊 SwiftBar"
if [ -d /Applications/SwiftBar.app ] || [ -d "$HOME/Applications/SwiftBar.app" ]; then
    if pgrep -xq SwiftBar; then pass "SwiftBar is running"; else warn "SwiftBar is installed but not running" "open -a SwiftBar"; fi

    PLUGIN_DIR="${SWIFTBAR_PLUGIN_DIR:-$(defaults read com.ameba.SwiftBar PluginDirectory 2>/dev/null || true)}"
    PLUGIN_DIR="${PLUGIN_DIR/#\~/$HOME}"
    [ -n "$PLUGIN_DIR" ] || PLUGIN_DIR="$HOME/Library/Application Support/SwiftBar/Plugins"
    PLUGIN="$PLUGIN_DIR/$PLUGIN_NAME"

    if [ -L "$PLUGIN" ] && [ -e "$PLUGIN" ]; then
        target=$(readlink "$PLUGIN")
        if [[ "$target" == "$INSTALL_DIR/"* ]]; then
            pass "Plugin linked to the installed copy"
        else
            info "Plugin is linked to $(tilde "$target") (a dev checkout?)"
        fi
    elif [ -L "$PLUGIN" ]; then
        fail "Plugin link is broken → $(readlink "$PLUGIN")" "re-run scripts/install.sh"
    elif [ -d "$PLUGIN" ]; then
        fail "Plugin is an old per-plugin folder (SwiftBar may have disabled it)" "re-run scripts/install.sh"
    elif [ -f "$PLUGIN" ]; then
        warn "Plugin is a plain copy: it will not receive updates" "re-run scripts/install.sh"
    else
        fail "Plugin not found in $(tilde "$PLUGIN_DIR")" "re-run scripts/install.sh"
    fi
    for junk in keyboard-lock.py README.md; do
        if [ -e "$PLUGIN_DIR/$junk" ]; then
            warn "$(tilde "$PLUGIN_DIR/$junk") will be run by SwiftBar as a plugin" "re-run scripts/install.sh (moves it to ~/.scripts/backups)"
        fi
    done

    DISABLED=$(defaults read com.ameba.SwiftBar DisabledPlugins 2>/dev/null || true)
    if printf '%s' "$DISABLED" | grep -q "$PLUGIN_NAME"; then
        fail "SwiftBar has the plugin disabled" "SwiftBar menu → Plugins → enable system-monitor (or re-run the installer)"
    fi

    if [ -e "$PLUGIN" ] && [ -n "$PY" ]; then
        t0=$(python3 -c 'import time; print(int(time.time()*1000))' 2>/dev/null || echo 0)
        if out=$("$PY" "$PLUGIN" 2>&1) && [ -n "$out" ]; then
            t1=$(python3 -c 'import time; print(int(time.time()*1000))' 2>/dev/null || echo 0)
            ms=$((t1 - t0))
            pass "Plugin test run: \"$(printf '%s' "$out" | head -1 | sed 's/ |.*//')\" (${ms} ms)"
            [ "$ms" -gt 1500 ] && warn "Plugin takes ${ms} ms per refresh (runs every 5 s)"
        else
            fail "Plugin test run failed" "$(printf '%s' "$out" | tail -1)"
        fi
    fi

    TICKS="$FC_STATE_DIR/swiftbar-cpu.ticks"
    if pgrep -xq SwiftBar && [ -f "$TICKS" ]; then
        a=$(mtime_age "$TICKS")
        if [ "$a" -lt 60 ]; then pass "SwiftBar refreshed the plugin ${a}s ago"
        else warn "SwiftBar has not run the plugin for $(age_text "$a")" "SwiftBar menu → Refresh All"; fi
    fi
else
    info "SwiftBar not installed (optional): brew install --cask swiftbar"
fi

# ---------------------------------------------------------------------------
section "⏰ Schedule"
CRON=$(crontab -l 2>/dev/null | grep -vE '^[[:space:]]*(#|$)' | grep -E '(cleaner|update|health)\.sh' || true)
LAUNCHD=$(grep -lE 'cleaner\.sh|update\.sh|health\.sh|fuck-cleanmymac' "$HOME/Library/LaunchAgents/"*.plist 2>/dev/null || true)

if [ -z "$CRON$LAUNCHD" ]; then
    info "Nothing scheduled: scripts run only when you start them"
    info "Weekly cleanup: (crontab -l; echo '0 9 * * 1 ~/.scripts/cleaner.sh --no-notify') | crontab -"
fi
while IFS= read -r line; do
    [ -z "$line" ] && continue
    script=$(printf '%s\n' "$line" | grep -oE '[^[:space:]]*(cleaner|update|health)\.sh' | head -1)
    script_path="${script/#\~/$HOME}"
    script_path="${script_path//\$HOME/$HOME}"
    if [ -x "$script_path" ]; then
        pass "cron: $(printf '%s' "$line" | awk '{print $1, $2, $3, $4, $5}')  $(tilde "$script_path")"
    else
        fail "cron runs $script, which does not exist or is not executable" "crontab -e"
    fi
done <<< "$CRON"
while IFS= read -r plist; do
    [ -n "$plist" ] && info "LaunchAgent: $(tilde "$plist")"
done <<< "$LAUNCHD"

# Last runs, and whether they went well
LAST_CLEAN=$(ls -t "$LOG_DIR"/cleaner_*.log 2>/dev/null | head -1)
if [ -n "$LAST_CLEAN" ]; then
    a=$(mtime_age "$LAST_CLEAN")
    fails=$(grep -c '^❌' "$LAST_CLEAN" 2>/dev/null || true)
    if [ "${fails:-0}" -gt 0 ]; then
        warn "Last cleanup $(age_text "$a") ago had $fails failure(s):"
        grep '^❌' "$LAST_CLEAN" | head -3 | sed 's/^/        /'
    else
        pass "Last cleanup $(age_text "$a") ago, no failures"
    fi
    if printf '%s' "$CRON" | grep -q cleaner.sh && [ "$a" -gt $((14 * 86400)) ]; then
        warn "Cleanup is scheduled but has not run for $(age_text "$a")" \
            "cron skips runs while the Mac sleeps; pick a time when it is usually awake"
    fi
else
    info "No cleanup has run yet"
fi
if [ -f "$LOG_DIR/update.log" ]; then
    a=$(mtime_age "$LOG_DIR/update.log")
    last_check=$(grep -E '^❌ Could not check' "$LOG_DIR/update.log" | tail -3)
    last_report_start=$(grep -n '=== UPDATE REPORT' "$LOG_DIR/update.log" | tail -1 | cut -d: -f1)
    recent_fail=$(tail -n +"${last_report_start:-1}" "$LOG_DIR/update.log" | grep -c '^❌ Could not check' || true)
    if [ "${recent_fail:-0}" -gt 0 ]; then
        warn "Last update run $(age_text "$a") ago could not check $recent_fail source(s)" "see $(tilde "$LOG_DIR/update.log")"
    else
        pass "Last update run $(age_text "$a") ago"
    fi
    unset last_check
fi

# ---------------------------------------------------------------------------
section "🧹 State"
STATE_ITEMS=0
shopt -s nullglob
for lock in "$FC_STATE_DIR"/*.lock; do
    pid=$(cat "$lock/pid" 2>/dev/null || true)
    name=$(basename "$lock" .lock)
    STATE_ITEMS=$((STATE_ITEMS + 1))
    if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
        info "$name.sh is running right now (PID $pid)"
    else
        info "Stale $name lock from a crashed run (cleared automatically on the next run)"
    fi
done
shopt -u nullglob
KB_PID="$HOME/.config/fuck-cleanmymac/keyboard-lock.pid"
if [ -f "$KB_PID" ]; then
    STATE_ITEMS=$((STATE_ITEMS + 1))
    pid=$(cut -d' ' -f1 "$KB_PID")
    if kill -0 "$pid" 2>/dev/null; then
        info "Keyboard lock is active (PID $pid) — unlock with ⌘⌃⌥K or the SwiftBar menu"
    else
        info "Stale keyboard-lock PID file (cleared automatically)"
    fi
fi
PLAN="$FC_STATE_DIR/cleanup-plan.tsv"
if [ -f "$PLAN" ]; then
    STATE_ITEMS=$((STATE_ITEMS + 1))
    perm=$(stat -f %Lp "$PLAN")
    if [ $(( 8#$perm & 8#022 )) -ne 0 ]; then
        fail "Saved cleanup plan is writable by others (mode $perm) — it will be refused" "chmod 600 $(tilde "$PLAN")"
    else
        info "Saved cleanup plan from $(age_text "$(mtime_age "$PLAN")") ago: cleaner.sh --apply"
    fi
fi
[ "$STATE_ITEMS" -eq 0 ] && pass "No running jobs, stale locks or saved plans"

# ---------------------------------------------------------------------------
echo ""
echo "════════════════════════════════════════════════════════════"
printf '  %d ok · %d warning(s) · %d problem(s)\n' "$N_OK" "$N_WARN" "$N_FAIL"
echo "════════════════════════════════════════════════════════════"
[ "$N_FAIL" -eq 0 ]
