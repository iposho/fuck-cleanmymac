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

# ============================================================================
# CONFIGURATION LOADING
# ============================================================================

DRY_RUN=false
VERBOSE_MODE=false
SHOW_NOTIFICATION=true
LOG_DIR="$HOME/.scripts/logs"
LOG_RETENTION_DAYS=90
VALIDATE_PATHS=true
TEMP_FILE_AGE_DAYS=2

CLEAN_SYSTEM_CACHES=true
CLEAN_APP_CACHES=true
CLEAN_PACKAGE_MANAGERS=true
CLEAN_BROWSER_CACHES=true
CLEAN_TRASH=true
CLEAN_TEMP_FILES=true
CLEAN_DOCKER=true

CONFIG_SOURCE=""
CLI_VERBOSE=""
CLI_NOTIFY=""

CLEANED_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0

load_config() {
    local config_paths=(
        "$HOME/.config/fuck-cleanmymac/cleaner.conf"
        "$HOME/.scripts/cleaner.conf"
        "$SCRIPT_DIR/cleaner.conf"
    )
    local config_file

    for config_file in "${config_paths[@]}"; do
        if [ -f "$config_file" ]; then
            # shellcheck source=/dev/null
            source "$config_file"
            CONFIG_SOURCE="$config_file"
            return 0
        fi
    done
    return 0
}

# ============================================================================
# COMMAND-LINE ARGUMENT HANDLING
# ============================================================================

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run|-n)
                DRY_RUN=true
                ;;
            --verbose|-v)
                CLI_VERBOSE=true
                ;;
            --no-notify)
                CLI_NOTIFY=false
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
        shift
    done
}

show_help() {
    cat << EOF
Usage: cleaner.sh [OPTIONS]

Options:
  -n, --dry-run    Show what would be cleaned without actually deleting
  -v, --verbose    Enable verbose logging
      --no-notify  Disable notifications
  -h, --help       Show this help message

Config: ~/.config/fuck-cleanmymac/cleaner.conf

Examples:
  ./cleaner.sh
  ./cleaner.sh --dry-run
  ./cleaner.sh --no-notify
  ./cleaner.sh --dry-run --verbose
EOF
}

# ============================================================================
# TIMING AND LOGGING SETUP
# ============================================================================

START_DATE=$(date "+%Y-%m-%d %H:%M:%S")
START_SEC=$(date +%s)
LOG_SEP="=================================================================================="
LOG_FILE=""

init_logging() {
    # Dry runs get their own prefix so they never show up as the "last cleanup".
    local prefix="cleaner"
    [ "$DRY_RUN" = true ] && prefix="cleaner-dryrun"
    LOG_FILE=$(fc_prepare_log_file "$LOG_DIR" "$prefix")
}

log() {
    fc_log "$LOG_FILE" "$1"
}

log_ok() {
    CLEANED_COUNT=$((CLEANED_COUNT + 1))
    log "✅ $1"
}

log_warn() {
    WARN_COUNT=$((WARN_COUNT + 1))
    log "⚠️  $1"
}

log_fail() {
    FAIL_COUNT=$((FAIL_COUNT + 1))
    log "❌ $1"
}

log_dry() {
    log "🏜  [DRY-RUN] $1"
}

debug_log() {
    if [ "$VERBOSE_MODE" = true ]; then
        log "🔍 DEBUG: $1"
    fi
}

# ============================================================================
# PATH VALIDATION FUNCTIONS
# ============================================================================

expand_path() {
    local raw="$1"
    local expanded="${raw/#\~/$HOME}"
    expanded="${expanded//\$HOME/$HOME}"
    expanded="${expanded//\$\{HOME\}/$HOME}"
    printf '%s' "$expanded"
}

is_temp_path() {
    case "$1" in
        "/tmp"|"/tmp/"*|"/var/tmp"|"/var/tmp/"*|"/private/tmp"|"/private/tmp/"*|"/private/var/tmp"|"/private/var/tmp/"*)
            return 0
            ;;
    esac
    return 1
}

# Allow removals only strictly inside the user home or the temp directories.
validate_path() {
    local raw="$1"
    [ -z "$raw" ] && return 1

    local expanded="${raw/#\~/$HOME}"
    if [ -e "$expanded" ] && fc_has_cmd realpath; then
        expanded=$(realpath "$expanded" 2>/dev/null || printf '%s' "$expanded")
    fi
    expanded="${expanded%/}"

    if is_temp_path "$expanded"; then
        return 0
    fi

    case "$expanded" in
        ""|"/System"*|"/usr"*|"/bin"*|"/sbin"*|"/etc"*|"/private"*|"/Library"*|"/Applications"*)
            debug_log "Path rejected (system path): $expanded"
            return 1
            ;;
    esac

    case "$expanded" in
        "$HOME"|"$HOME/Library"|"$HOME/Library/Application Support"|"$HOME/Documents"|"$HOME/Desktop")
            debug_log "Path rejected (too broad): $expanded"
            return 1
            ;;
        "$HOME/"*)
            return 0
            ;;
    esac

    debug_log "Path rejected (not in safe location): $expanded"
    return 1
}

# ============================================================================
# SAFE REMOVAL AND CLEANING FUNCTIONS
# ============================================================================

# Remove the direct children of a directory. Extra find predicates can narrow the selection.
# Usage: safe_clean <dir> <description> [find predicates...]
# Sets SC_ITEMS / SC_LEFT; with SC_QUIET=1 it does not log (used by clean_group).
SC_ITEMS=0
SC_LEFT=0
SC_QUIET=0
safe_clean() {
    local path="$1"
    local description="$2"
    shift 2
    local expanded
    expanded=$(expand_path "$path")
    SC_ITEMS=0
    SC_LEFT=0

    if [ "$VALIDATE_PATHS" = true ] && ! validate_path "$expanded"; then
        log_fail "Skipped cleaning $description: path not validated or too broad: $expanded"
        return 1
    fi

    if [ ! -d "$expanded" ]; then
        debug_log "$description not found ($expanded)"
        return 0
    fi

    local items=()
    local item
    while IFS= read -r -d '' item; do
        items+=("$item")
    done < <(find "$expanded" -mindepth 1 -maxdepth 1 "$@" -print0 2>/dev/null)

    if [ "${#items[@]}" -eq 0 ]; then
        debug_log "$description: nothing to clean ($expanded)"
        return 0
    fi
    SC_ITEMS=${#items[@]}

    if [ "$DRY_RUN" = true ]; then
        [ "$SC_QUIET" = 1 ] || log_dry "Would clean: $description ($SC_ITEMS items in $expanded)"
        return 0
    fi

    # xargs splits huge lists (e.g. Telegram media) below ARG_MAX
    printf '%s\0' "${items[@]}" | xargs -0 rm -rf 2>/dev/null

    # Count what survived (files in use, root-owned or SIP-protected entries).
    local left=0
    for item in "${items[@]}"; do
        [ -e "$item" ] || [ -L "$item" ] && left=$((left + 1))
    done
    SC_LEFT=$left
    [ "$SC_QUIET" = 1 ] && return 0

    if [ "$left" -eq 0 ]; then
        log_ok "$description cleaned (${#items[@]} items)"
    elif [ "$left" -lt "${#items[@]}" ]; then
        log_warn "$description partially cleaned ($left of ${#items[@]} items locked or protected)"
    else
        log_fail "Failed to clean $description ($expanded)"
    fi
}

# Temp dirs are shared with running processes (ssh-agent/launchd sockets, tmux, IDE helpers):
# only remove our own entries that have not been touched for TEMP_FILE_AGE_DAYS.
clean_temp_dir() {
    local dir="$1"
    local description="$2"
    local user
    user=$(id -un)

    safe_clean "$dir" "$description" \
        -user "$user" \
        -mtime +"$TEMP_FILE_AGE_DAYS" \
        ! -type s \
        ! -name 'com.apple.*' \
        ! -name 'tmux-*' \
        ! -name '.X*' \
        ! -name 'claude-*'
}

# Clean via package-manager CLI when available; fall back to directory wipe.
clean_via_cli_or_dir() {
    local description="$1"
    local dir="$2"
    shift 2

    if [ ! -d "$dir" ] && [ $# -eq 0 ]; then
        return 0
    fi

    if [ "$DRY_RUN" = true ]; then
        log_dry "Would clean $description"
        return 0
    fi

    if [ $# -gt 0 ]; then
        if "$@" >/dev/null 2>&1; then
            log_ok "$description cleaned (via CLI)"
            return 0
        fi
        debug_log "$description CLI clean failed, falling back to directory wipe"
    fi

    safe_clean "$dir" "$description"
}

# Run a cleanup command, honouring dry-run.
run_cleanup_cmd() {
    local description="$1"
    shift

    if [ "$DRY_RUN" = true ]; then
        log_dry "Would run: $description"
        return 0
    fi
    if "$@" >/dev/null 2>&1; then
        log_ok "$description"
    else
        log_warn "$description failed"
    fi
}

# Clean several cache folders of one app and report a single line.
# Usage: clean_group <name> <dir>...
clean_group() {
    local name="$1"
    shift
    local dir folders=0 items=0 left=0

    for dir in "$@"; do
        [ -d "$dir" ] || continue
        SC_QUIET=1 safe_clean "$dir" "$name ($dir)"
        [ "$SC_ITEMS" -gt 0 ] || continue
        folders=$((folders + 1))
        items=$((items + SC_ITEMS))
        left=$((left + SC_LEFT))
        debug_log "$name: $SC_ITEMS items in $dir"
    done

    [ "$items" -eq 0 ] && return 0
    local what="$items item"
    [ "$items" -ne 1 ] && what="${what}s"
    what="$what in $folders folder"
    [ "$folders" -ne 1 ] && what="${what}s"
    if [ "$DRY_RUN" = true ]; then
        log_dry "Would clean: $name ($what)"
    elif [ "$left" -eq 0 ]; then
        log_ok "$name cleaned ($what)"
    elif [ "$left" -lt "$items" ]; then
        log_warn "$name partially cleaned ($left of $items items locked or in use)"
    else
        log_fail "Failed to clean $name"
    fi
}

ELECTRON_CACHE_DIRS=("Cache" "Code Cache" "GPUCache" "CachedData" "DawnCache" "DawnGraphiteCache" "DawnWebGPUCache")

# Electron apps keep their disk caches next to user data.
clean_electron_app() {
    local name="$1"
    local base="$2"
    local sub dirs=()
    [ -d "$base" ] || return 0

    for sub in "${ELECTRON_CACHE_DIRS[@]}"; do
        dirs+=("$base/$sub")
    done
    clean_group "$name cache" "${dirs[@]}"
}

# Chromium browsers: per-profile caches + shared shader caches.
clean_chromium_browser() {
    local name="$1"
    local base="$2"
    local profile sub dirs=()
    [ -d "$base" ] || return 0

    shopt -s nullglob
    for profile in "$base/Default" "$base/Profile "* "$base/Guest Profile"; do
        [ -d "$profile" ] || continue
        for sub in "Cache" "Code Cache" "GPUCache" "DawnCache" "DawnGraphiteCache" "DawnWebGPUCache"; do
            dirs+=("$profile/$sub")
        done
    done
    shopt -u nullglob

    for sub in "GrShaderCache" "ShaderCache" "GraphiteDawnCache" "GPUPersistentCache"; do
        dirs+=("$base/$sub")
    done
    clean_group "$name cache (all profiles)" "${dirs[@]}"
}

# ============================================================================
# CLEANUP SECTIONS
# ============================================================================

clean_docker() {
    log "🐳 Docker cleanup..."
    if ! fc_has_cmd docker; then
        debug_log "Docker not installed"
        return 0
    fi
    if ! fc_run_timeout 5 docker info >/dev/null 2>&1; then
        log "ℹ️  Docker daemon is not running. Skipping."
        return 0
    fi
    # Named volumes are kept: since Docker 23 --volumes prunes anonymous volumes only.
    run_cleanup_cmd "Docker system prune" docker system prune -af --volumes
    run_cleanup_cmd "Docker builder cache prune" docker builder prune -af
}

clean_package_managers() {
    log "📦 Package manager cleanup..."

    if fc_has_cmd npm; then
        clean_via_cli_or_dir "npm cache" "$HOME/.npm/_cacache" npm cache clean --force
    elif [ -d "$HOME/.npm/_cacache" ]; then
        safe_clean "$HOME/.npm/_cacache" "npm cache"
    fi

    if fc_has_cmd yarn; then
        clean_via_cli_or_dir "yarn cache" "$HOME/Library/Caches/Yarn" yarn cache clean
    fi

    if fc_has_cmd pnpm; then
        run_cleanup_cmd "pnpm store prune" pnpm store prune
    fi

    if fc_has_cmd bun; then
        clean_via_cli_or_dir "bun cache" "$HOME/.bun/install/cache" bun pm cache rm
    elif [ -d "$HOME/.bun/install/cache" ]; then
        safe_clean "$HOME/.bun/install/cache" "bun cache"
    fi

    if fc_has_cmd brew; then
        run_cleanup_cmd "Homebrew cleanup" brew cleanup -s --prune=all
    fi

    if fc_has_cmd pip3; then
        clean_via_cli_or_dir "pip cache" "$HOME/Library/Caches/pip" pip3 cache purge
    fi

    if fc_has_cmd uv; then
        run_cleanup_cmd "uv cache prune" uv cache prune
    fi

    clean_group "Cargo registry cache" "$HOME/.cargo/registry/cache"

    # Xcode
    clean_group "Xcode DerivedData" "$HOME/Library/Developer/Xcode/DerivedData"
    clean_group "Simulator caches" "$HOME/Library/Developer/CoreSimulator/Caches"
    # Debug symbols copied from connected iPhones/iPads; Xcode re-creates them on demand.
    clean_group "Xcode device support files" \
        "$HOME/Library/Developer/Xcode/iOS DeviceSupport" \
        "$HOME/Library/Developer/Xcode/watchOS DeviceSupport" \
        "$HOME/Library/Developer/Xcode/tvOS DeviceSupport"
    # Downloaded iOS/iPadOS firmware (.ipsw), re-downloaded by Finder when needed.
    clean_group "Old iPhone/iPad firmware" \
        "$HOME/Library/iTunes/iPhone Software Updates" \
        "$HOME/Library/iTunes/iPad Software Updates"
    if [ -d "$HOME/Library/Developer/CoreSimulator/Devices" ] && fc_has_cmd xcrun; then
        run_cleanup_cmd "Unavailable simulators cleanup" fc_run_timeout 60 xcrun simctl delete unavailable
    fi
}

clean_app_caches() {
    local skip_library_caches="$1"
    local app_support="$HOME/Library/Application Support"
    log "🖥  Application cache cleanup..."

    # Electron-based apps and editors
    clean_electron_app "Cursor" "$app_support/Cursor"
    clean_electron_app "VS Code" "$app_support/Code"
    clean_electron_app "Windsurf" "$app_support/Windsurf"
    clean_electron_app "Antigravity" "$app_support/Antigravity"
    clean_electron_app "Slack" "$app_support/Slack"
    clean_electron_app "Notion" "$app_support/Notion"
    clean_electron_app "Discord" "$app_support/discord"
    clean_electron_app "Figma" "$app_support/Figma"
    clean_electron_app "Obsidian" "$app_support/obsidian"
    clean_electron_app "Postman" "$app_support/Postman"
    clean_group "Slack Service Worker cache" "$app_support/Slack/Service Worker/CacheStorage"
    clean_group "Zed cache" "$app_support/Zed/Cache"
    clean_group "Spotify cache" "$app_support/Spotify/PersistentCache"

    # Telegram media cache: <group container>/{stable,appstore,beta}/account-*/postbox/media
    shopt -s nullglob
    local tg_media=(
        "$HOME/Library/Group Containers/"*.ru.keepcoder.Telegram/*/account-*/postbox/media
        "$HOME/Library/Group Containers/"*.ru.keepcoder.Telegram/account-*/postbox/media
    )
    shopt -u nullglob
    [ "${#tg_media[@]}" -gt 0 ] && clean_group "Telegram media cache" "${tg_media[@]}"

    # Targets under ~/Library/Caches are covered by the system cache wipe.
    if [ "$skip_library_caches" = false ]; then
        clean_group "Spotify HTTP cache" "$HOME/Library/Caches/com.spotify.client"
        clean_group "JetBrains caches" "$HOME/Library/Caches/JetBrains"
    fi
}

clean_browser_caches() {
    local skip_library_caches="$1"
    local app_support="$HOME/Library/Application Support"
    log "🌐 Browser cache cleanup..."

    clean_chromium_browser "Chrome" "$app_support/Google/Chrome"
    clean_chromium_browser "Arc" "$app_support/Arc/User Data"
    clean_chromium_browser "Brave" "$app_support/BraveSoftware/Brave-Browser"
    clean_chromium_browser "Edge" "$app_support/Microsoft Edge"

    if [ "$skip_library_caches" = false ]; then
        # Chromium keeps the main HTTP cache under ~/Library/Caches on macOS
        clean_group "Chrome HTTP cache" "$HOME/Library/Caches/Google/Chrome"
        clean_group "Brave HTTP cache" "$HOME/Library/Caches/BraveSoftware"
        clean_group "Edge HTTP cache" "$HOME/Library/Caches/Microsoft Edge"
        clean_group "Firefox cache" "$HOME/Library/Caches/Firefox"
    fi
}

clean_system() {
    log "🗑  System maintenance..."

    if [ "$CLEAN_SYSTEM_CACHES" = true ]; then
        safe_clean "$HOME/Library/Caches" "User caches"
        safe_clean "$HOME/Library/Logs" "User logs"
    fi

    if [ "$CLEAN_TRASH" = true ]; then
        safe_clean "$HOME/.Trash" "Trash"
    fi

    if [ "$CLEAN_TEMP_FILES" = true ]; then
        clean_temp_dir /private/tmp "Temporary files (/tmp, older than ${TEMP_FILE_AGE_DAYS}d)"
        clean_temp_dir /private/var/tmp "Temporary files (/var/tmp, older than ${TEMP_FILE_AGE_DAYS}d)"
    fi
}

rotate_logs() {
    log "📜 Rotating old cleanup logs..."
    if [ ! -d "$LOG_DIR" ]; then
        debug_log "Log directory missing: $LOG_DIR"
        return 0
    fi

    local old_logs
    old_logs=$(find "$LOG_DIR" -type f \( -name "*.log" -o -name "*.log.1" \) -mtime +"$LOG_RETENTION_DAYS" 2>/dev/null)
    if [ -z "$old_logs" ]; then
        debug_log "No logs older than $LOG_RETENTION_DAYS days"
        return 0
    fi

    local count
    count=$(fc_count_lines "$old_logs")
    if [ "$DRY_RUN" = true ]; then
        log_dry "Would remove $count logs older than $LOG_RETENTION_DAYS days"
        return 0
    fi
    if find "$LOG_DIR" -type f \( -name "*.log" -o -name "*.log.1" \) -mtime +"$LOG_RETENTION_DAYS" -delete 2>/dev/null; then
        log_ok "Removed $count logs older than $LOG_RETENTION_DAYS days"
    else
        log_fail "Failed to rotate old logs"
    fi
}

# ============================================================================
# MAIN CLEANUP ROUTINE
# ============================================================================

main() {
    parse_arguments "$@"
    load_config
    # Command-line flags win over the config file
    [ -n "$CLI_VERBOSE" ] && VERBOSE_MODE="$CLI_VERBOSE"
    [ -n "$CLI_NOTIFY" ] && SHOW_NOTIFICATION="$CLI_NOTIFY"
    [[ "$TEMP_FILE_AGE_DAYS" =~ ^[0-9]+$ ]] || TEMP_FILE_AGE_DAYS=2
    [[ "$LOG_RETENTION_DAYS" =~ ^[0-9]+$ ]] || LOG_RETENTION_DAYS=90

    fc_acquire_lock cleaner || exit 0
    init_logging

    local before after diff end_sec runtime msg
    before=$(fc_disk_free_mb)
    before=${before:-0}

    log "$LOG_SEP"
    [ "$DRY_RUN" = true ] && log "🏜  DRY-RUN MODE - No files will be deleted"
    log "=== CLEANUP REPORT [$START_DATE] ==="
    if [ -n "$CONFIG_SOURCE" ]; then
        log "Config: $CONFIG_SOURCE"
    else
        log "Config: defaults (no cleaner.conf found)"
    fi
    log "$LOG_SEP"

    local skip_library_caches=false
    if [ "$CLEAN_SYSTEM_CACHES" = true ]; then
        skip_library_caches=true
        debug_log "Skipping per-app Library/Caches targets (covered by system caches)"
    fi

    if [ "$CLEAN_DOCKER" = true ]; then
        clean_docker
        log "$LOG_SEP"
    fi

    if [ "$CLEAN_PACKAGE_MANAGERS" = true ]; then
        clean_package_managers
        log "$LOG_SEP"
    fi

    if [ "$CLEAN_APP_CACHES" = true ]; then
        clean_app_caches "$skip_library_caches"
        log "$LOG_SEP"
    fi

    if [ "$CLEAN_BROWSER_CACHES" = true ]; then
        clean_browser_caches "$skip_library_caches"
        log "$LOG_SEP"
    fi

    if [ "$CLEAN_SYSTEM_CACHES" = true ] || [ "$CLEAN_TRASH" = true ] || [ "$CLEAN_TEMP_FILES" = true ]; then
        clean_system
        log "$LOG_SEP"
    fi

    rotate_logs
    log "$LOG_SEP"

    after=$(fc_disk_free_mb)
    after=${after:-0}
    diff=$((after - before))
    [ "$diff" -lt 0 ] && diff=0

    end_sec=$(date +%s)
    runtime=$((end_sec - START_SEC))

    log "📊 SUMMARY:"
    if [ "$DRY_RUN" = true ]; then
        log "🏜  DRY-RUN: No files were actually deleted"
        log "⏱️  Scan time: $runtime seconds"
    else
        log "✅ Freed: $diff MB"
        log "🧾 Cleaned: $CLEANED_COUNT | Partial: $WARN_COUNT | Failed: $FAIL_COUNT"
        log "⏱️  Runtime: $runtime seconds"
    fi
    log "=== COMPLETED [$(date "+%H:%M:%S")] ==="
    log "$LOG_SEP"

    if [ "$SHOW_NOTIFICATION" = true ] && [ "$DRY_RUN" = false ]; then
        if [ "$diff" -gt 0 ]; then
            msg="Freed $diff MB in $runtime seconds"
        else
            msg="System already clean! (Took $runtime seconds)"
        fi
        [ "$FAIL_COUNT" -gt 0 ] && msg="$msg, $FAIL_COUNT failed (see log)"
        fc_notify "fuck cleanmymac" "$msg" "Cleanup completed"
    fi

    return 0
}

main "$@"
