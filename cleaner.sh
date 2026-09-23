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

# How it works
#   1. collect: every cleanup target is turned into plan entries
#        T  a folder whose direct children are removed (+ one I line per child with its mtime)
#        C  a whitelisted cleanup command (npm cache, brew cleanup, ...)
#   2. report (--scan / --plan) and/or apply (default run / --apply)
#   Applying re-validates every folder and removes only children that still exist
#   with the mtime recorded in the plan; anything changed since is kept.

# ============================================================================
# CONFIGURATION
# ============================================================================

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

MODE=run            # run | scan | plan | apply
PLAN_ARG=""
DEFAULT_PLAN_FILE="$FC_STATE_DIR/cleanup-plan.tsv"
PLAN_HEADER="# fuck-cleanmymac cleanup plan v1"
PLAN_MAX_AGE_HOURS=24

CONFIG_SOURCE=""
CLI_VERBOSE=""
CLI_NOTIFY=""

CLEANED_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0

CAT_DOCKER="🐳 Docker"
CAT_DEV="📦 Developer caches"
CAT_APPS="🖥  Applications"
CAT_BROWSERS="🌐 Browsers"
CAT_SYSTEM="🗑  System"

load_config() {
    local config_file
    for config_file in \
        "$HOME/.config/fuck-cleanmymac/cleaner.conf" \
        "$HOME/.scripts/cleaner.conf" \
        "$SCRIPT_DIR/cleaner.conf"
    do
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
# COMMAND-LINE ARGUMENTS
# ============================================================================

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --scan|--dry-run|-n)
                MODE=scan
                ;;
            --plan|--apply)
                MODE="${1#--}"
                if [[ $# -gt 1 && "$2" != -* ]]; then
                    PLAN_ARG="$2"
                    shift
                fi
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
Usage: cleaner.sh [MODE] [OPTIONS]

Modes:
  (none)             Clean now
  -n, --scan         Show what would be cleaned: sizes, paths, reasons and skips.
                     Deletes nothing. (--dry-run is an alias)
      --plan [FILE]  Scan and save a cleanup plan (default: $DEFAULT_PLAN_FILE)
      --apply [FILE] Execute a saved plan. Paths are re-validated; files changed
                     after the plan was made are kept.

Options:
  -v, --verbose      More detail (every folder, skipped targets)
      --no-notify    Disable notifications
  -h, --help         Show this help message

Config: ~/.config/fuck-cleanmymac/cleaner.conf

Examples:
  cleaner.sh --scan
  cleaner.sh --plan && open -t "$DEFAULT_PLAN_FILE" && cleaner.sh --apply
EOF
}

# ============================================================================
# LOGGING
# ============================================================================

START_DATE=$(date "+%Y-%m-%d %H:%M:%S")
START_SEC=$(date +%s)
LOG_SEP="=================================================================================="
LOG_FILE=""

init_logging() {
    # Scans and plans get their own prefix so they never show up as the "last cleanup".
    local prefix="cleaner"
    case "$MODE" in
        scan|plan) prefix="cleaner-dryrun" ;;
    esac
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

debug_log() {
    if [ "$VERBOSE_MODE" = true ]; then
        log "🔍 $1"
    fi
}

# ============================================================================
# FORMATTING
# ============================================================================

fmt_kb() {
    awk -v k="${1:-0}" 'BEGIN {
        if (k >= 1048576) printf "%.1f GB", k / 1048576
        else if (k >= 1024) printf "%.0f MB", k / 1024
        else printf "%d KB", k
    }'
}

# "1.23GB", "345.6 MB", "12kB", "0B" (docker / brew output) → KB
human_to_kb() {
    awk '{
        s = $0; gsub(/[[:space:]]/, "", s)
        if (!match(s, /^[0-9.]+/)) next
        n = substr(s, 1, RLENGTH); u = toupper(substr(s, RLENGTH + 1, 2))
        m = 1 / 1024
        if (u ~ /^K/) m = 1; else if (u ~ /^M/) m = 1024
        else if (u ~ /^G/) m = 1048576; else if (u ~ /^T/) m = 1073741824
        total += n * m
    } END { printf "%d", total }'
}

# $HOME with symlinks resolved (e.g. /var → /private/var); plans store resolved paths.
HOME_REAL=$(cd "$HOME" 2>/dev/null && pwd -P || printf '%s' "$HOME")

tilde() {
    local path="${1/#$HOME_REAL/~}"
    printf '%s' "${path/#$HOME/~}"
}

plural() {
    if [ "$1" -eq 1 ]; then
        printf '%s %s' "$1" "$2"
    else
        printf '%s %ss' "$1" "$2"
    fi
}

du_kb() {
    if [ -e "$1" ]; then
        du -sk "$1" 2>/dev/null | awk '{s += $1} END {printf "%d", s}'
    else
        printf '0'
    fi
}

# ============================================================================
# PATH VALIDATION
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

    # A degenerate HOME ("/" or a top-level folder) would make everything "inside home".
    local home
    for home in "$HOME_REAL" "$HOME"; do
        home="${home%/}"
        case "$home" in
            ""|/*/*) ;;
            *) debug_log "Refusing to clean: HOME ($home) is not a normal user folder"; return 1 ;;
        esac
        [ -n "$home" ] || continue
        case "$expanded" in
            "$home"|"$home/Library"|"$home/Library/Application Support"|"$home/Documents"|"$home/Desktop")
                debug_log "Path rejected (too broad): $expanded"
                return 1
                ;;
            "$home/"*)
                return 0
                ;;
        esac
    done

    debug_log "Path rejected (not inside HOME or temp folders): $expanded"
    return 1
}

# ============================================================================
# COLLECTOR — builds the plan, optionally with size estimates
# ============================================================================

PLAN_FILE=""
TARGET_SEQ=0
ITEM_TOTAL=0
COLLECT_SIZES=false
TOTAL_KB=0
LAST_COUNT=0
SKIPS=""

add_skip() {
    SKIPS="${SKIPS}   • $1"$'\n'
}

# --- report aggregation: consecutive targets with the same label form one line ---
R_CAT=""
R_CAT_KB=0
R_CAT_BUF=""
R_LABEL=""
R_KB=0
R_ITEMS=0
R_FOLDERS=0
R_PATHS=""
R_REASON=""
R_NOTE=""
R_EXCLUDED=false
R_WHERE=""

report_flush_label() {
    [ -z "$R_LABEL" ] && return 0
    local size where line
    size=$(fmt_kb "$R_KB")
    [ "$R_KB" = "-1" ] && size="size unknown"
    [ -n "$R_NOTE" ] && size="$size $R_NOTE"

    if [ "$R_FOLDERS" -gt 1 ]; then
        where="$(plural "$R_FOLDERS" folder), $(plural "$R_ITEMS" item)"
    elif [ -n "$R_PATHS" ]; then
        where=$(tilde "$(printf '%s' "$R_PATHS" | head -1)")
        [ "$R_ITEMS" -gt 0 ] && where="$where ($(plural "$R_ITEMS" item))"
    else
        where="$R_WHERE"
    fi

    line=$(printf '   • %-38s %s' "$R_LABEL" "$size")
    R_CAT_BUF="${R_CAT_BUF}${line}"$'\n'"      ${where} — ${R_REASON}"$'\n'
    if [ "$R_FOLDERS" -gt 1 ]; then
        local shown=3
        [ "$VERBOSE_MODE" = true ] && shown=1000
        while IFS= read -r line; do
            [ -n "$line" ] && R_CAT_BUF="${R_CAT_BUF}        $(tilde "$line")"$'\n'
        done <<< "$(printf '%s' "$R_PATHS" | head -"$shown")"
        [ "$R_FOLDERS" -gt "$shown" ] && R_CAT_BUF="${R_CAT_BUF}        … and $((R_FOLDERS - shown)) more (--verbose lists all)"$'\n'
    fi

    if [ "$R_EXCLUDED" = false ] && [ "$R_KB" -gt 0 ]; then
        R_CAT_KB=$((R_CAT_KB + R_KB))
    fi
    R_LABEL=""
}

report_flush_category() {
    report_flush_label
    if [ -n "$R_CAT" ] && [ -n "$R_CAT_BUF" ]; then
        log ""
        log "$R_CAT — $(fmt_kb "$R_CAT_KB")"
        log "${R_CAT_BUF%$'\n'}"
        TOTAL_KB=$((TOTAL_KB + R_CAT_KB))
    fi
    R_CAT=""
    R_CAT_KB=0
    R_CAT_BUF=""
}

# report_add <category> <label> <kb|-1> <items> <path> <reason> [note] [excluded_from_total] [where]
report_add() {
    [ "$COLLECT_SIZES" = true ] || return 0
    local category="$1" label="$2" kb="$3" items="$4" path="$5" reason="$6"
    local note="${7:-}" excluded="${8:-false}" where="${9:-}"

    [ "$category" != "$R_CAT" ] && { report_flush_category; R_CAT="$category"; }
    if [ "$label" != "$R_LABEL" ]; then
        report_flush_label
        R_LABEL="$label"; R_KB=0; R_ITEMS=0; R_FOLDERS=0; R_PATHS=""
        R_REASON="$reason"; R_NOTE="$note"; R_EXCLUDED="$excluded"; R_WHERE="$where"
    fi
    if [ "$kb" = "-1" ]; then
        R_KB=-1
    elif [ "$R_KB" != "-1" ]; then
        R_KB=$((R_KB + kb))
    fi
    R_ITEMS=$((R_ITEMS + items))
    if [ -n "$path" ]; then
        R_FOLDERS=$((R_FOLDERS + 1))
        R_PATHS="${R_PATHS}${path}"$'\n'
    fi
}

# add_dir_target <category> <label> <dir> <reason> [find predicates...]
# Plans removal of the direct children of <dir> (optionally narrowed by find predicates).
add_dir_target() {
    local category="$1" label="$2" dir="$3" reason="$4"
    shift 4
    local expanded real listing count size_kb=0
    LAST_COUNT=0
    expanded=$(expand_path "$dir")

    [ -e "$expanded" ] || { debug_log "$label: not present ($(tilde "$expanded"))"; return 0; }
    if [ "$VALIDATE_PATHS" = true ] && ! validate_path "$expanded"; then
        add_skip "$label: unsafe path refused ($expanded)"
        return 0
    fi
    if [ -L "$expanded" ] || [ ! -d "$expanded" ]; then
        add_skip "$label: $(tilde "$expanded") is not a regular folder"
        return 0
    fi
    real=$(realpath "$expanded" 2>/dev/null || printf '%s' "$expanded")

    # "mtime<TAB>path" per direct child; names with newlines are dropped (never deleted).
    listing=$(find "$real" -mindepth 1 -maxdepth 1 "$@" -exec stat -f '%m%t%N' {} + 2>/dev/null \
        | awk -F'\t' -v d="$real/" 'NF == 2 && index($2, d) == 1 && substr($2, length(d) + 1) !~ /\//')
    if [ -z "$listing" ]; then
        debug_log "$label: nothing to clean in $(tilde "$real")"
        return 0
    fi
    count=$(printf '%s\n' "$listing" | wc -l | tr -d ' ')
    LAST_COUNT=$count

    if [ "$COLLECT_SIZES" = true ]; then
        size_kb=$(printf '%s\n' "$listing" | cut -f2- | tr '\n' '\0' \
            | xargs -0 du -sk 2>/dev/null | awk '{s += $1} END {printf "%d", s}')
    fi

    TARGET_SEQ=$((TARGET_SEQ + 1))
    ITEM_TOTAL=$((ITEM_TOTAL + count))
    printf 'T\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$TARGET_SEQ" "$category" "$label" "$real" "$size_kb" "$count" "$reason" >> "$PLAN_FILE"
    printf '%s\n' "$listing" | awk -v id="$TARGET_SEQ" '{print "I\t" id "\t" $0}' >> "$PLAN_FILE"

    report_add "$category" "$label" "$size_kb" "$count" "$real" "$reason"
}

# --- whitelisted cleanup commands (plans store only these ids) ---

cmd_available() {
    case "$1" in
        docker_prune) fc_has_cmd docker ;;
        npm_cache) fc_has_cmd npm ;;
        yarn_cache) fc_has_cmd yarn ;;
        pnpm_prune) fc_has_cmd pnpm ;;
        bun_cache) fc_has_cmd bun ;;
        brew_cleanup) fc_has_cmd brew ;;
        pip_cache) fc_has_cmd pip3 ;;
        uv_prune) fc_has_cmd uv ;;
        # xcrun ships with the Command Line Tools, but simctl only comes with Xcode.
        simctl_unavailable) fc_has_cmd xcrun && fc_run_timeout 10 xcrun --find simctl >/dev/null 2>&1 ;;
        *) return 1 ;;
    esac
}

cmd_text() {
    case "$1" in
        docker_prune) echo "docker system prune -af --volumes; docker builder prune -af" ;;
        npm_cache) echo "npm cache clean --force" ;;
        yarn_cache) echo "yarn cache clean" ;;
        pnpm_prune) echo "pnpm store prune" ;;
        bun_cache) echo "bun pm cache rm" ;;
        brew_cleanup) echo "brew cleanup -s --prune=all" ;;
        pip_cache) echo "pip3 cache purge" ;;
        uv_prune) echo "uv cache prune" ;;
        simctl_unavailable) echo "xcrun simctl delete unavailable" ;;
    esac
}

run_cmd_id() {
    case "$1" in
        docker_prune)
            # Named volumes are kept: since Docker 23 --volumes prunes anonymous volumes only.
            docker system prune -af --volumes && docker builder prune -af ;;
        npm_cache) npm cache clean --force ;;
        yarn_cache) yarn cache clean ;;
        pnpm_prune) pnpm store prune ;;
        bun_cache) bun pm cache rm ;;
        brew_cleanup) brew cleanup -s --prune=all ;;
        pip_cache) pip3 cache purge ;;
        uv_prune) uv cache prune ;;
        simctl_unavailable) fc_run_timeout 60 xcrun simctl delete unavailable ;;
        *) return 99 ;;
    esac
}

# Sets EST_KB (-1 = unknown), EST_DIR (cache folder, for overlap detection), EST_NOTE.
estimate_cmd() {
    EST_KB=-1
    EST_DIR=""
    EST_NOTE=""
    case "$1" in
        docker_prune)
            EST_KB=$(fc_run_timeout 20 docker system df --format '{{.Reclaimable}}' 2>/dev/null \
                | sed 's/ *(.*//' | human_to_kb)
            ;;
        npm_cache) EST_DIR="$HOME/.npm/_cacache" ;;
        yarn_cache) EST_DIR=$(fc_run_timeout 10 yarn cache dir 2>/dev/null | tail -1) ;;
        pnpm_prune) EST_DIR=$(fc_run_timeout 10 pnpm store path 2>/dev/null | tail -1); EST_NOTE="(at most)" ;;
        bun_cache) EST_DIR="$HOME/.bun/install/cache" ;;
        brew_cleanup)
            EST_DIR=$(brew --cache 2>/dev/null)
            EST_KB=$(fc_run_timeout 120 brew cleanup -n -s --prune=all 2>/dev/null \
                | sed -n 's/.*free approximately \(.*\) of disk space.*/\1/p' | human_to_kb)
            ;;
        pip_cache) EST_DIR=$(fc_run_timeout 10 pip3 cache dir 2>/dev/null | tail -1) ;;
        uv_prune) EST_DIR=$(fc_run_timeout 10 uv cache dir 2>/dev/null | tail -1); EST_NOTE="(at most)" ;;
    esac
    if [ "$EST_KB" = "-1" ] && [ -n "$EST_DIR" ]; then
        EST_KB=$(du_kb "$EST_DIR")
    fi
    [ -n "$EST_KB" ] || EST_KB=0
}

# add_cmd_target <category> <label> <cmd_id> <reason>
add_cmd_target() {
    local category="$1" label="$2" cmd_id="$3" reason="$4"
    cmd_available "$cmd_id" || return 0

    local kb=-1 excluded=false note=""
    EST_DIR=""
    if [ "$COLLECT_SIZES" = true ]; then
        estimate_cmd "$cmd_id"
        kb="$EST_KB"
        note="$EST_NOTE"
        # Caches living in ~/Library/Caches are already part of the "User caches" total.
        if [ "$CLEAN_SYSTEM_CACHES" = true ] && [[ "$EST_DIR" == "$HOME/Library/Caches/"* ]]; then
            excluded=true
            note="(counted in User caches)"
        fi
    fi

    TARGET_SEQ=$((TARGET_SEQ + 1))
    printf 'C\t%s\t%s\t%s\t%s\t%s\t%s\n' "$TARGET_SEQ" "$category" "$label" "$cmd_id" "$kb" "$reason" >> "$PLAN_FILE"
    local where
    where="runs: $(cmd_text "$cmd_id")"
    [ -n "${EST_DIR:-}" ] && [ "$COLLECT_SIZES" = true ] && where="$(tilde "$EST_DIR"), $where"
    report_add "$category" "$label" "$kb" 0 "" "$reason" "$note" "$excluded" "$where"
}

ELECTRON_CACHE_DIRS=("Cache" "Code Cache" "GPUCache" "CachedData" "DawnCache" "DawnGraphiteCache" "DawnWebGPUCache")

collect_electron_app() {
    local name="$1" base="$2" sub
    [ -d "$base" ] || return 0
    for sub in "${ELECTRON_CACHE_DIRS[@]}"; do
        add_dir_target "$CAT_APPS" "$name cache" "$base/$sub" "app disk cache, rebuilt automatically"
    done
}

collect_chromium_browser() {
    local name="$1" base="$2" profile sub
    [ -d "$base" ] || return 0
    local reason="browser cache; cookies, history and passwords are kept"

    shopt -s nullglob
    for profile in "$base/Default" "$base/Profile "* "$base/Guest Profile"; do
        [ -d "$profile" ] || continue
        for sub in "Cache" "Code Cache" "GPUCache" "DawnCache" "DawnGraphiteCache" "DawnWebGPUCache"; do
            add_dir_target "$CAT_BROWSERS" "$name cache (all profiles)" "$profile/$sub" "$reason"
        done
    done
    shopt -u nullglob
    for sub in "GrShaderCache" "ShaderCache" "GraphiteDawnCache" "GPUPersistentCache"; do
        add_dir_target "$CAT_BROWSERS" "$name cache (all profiles)" "$base/$sub" "$reason"
    done
}

collect_docker() {
    if ! fc_has_cmd docker; then
        debug_log "Docker not installed"
        return 0
    fi
    if ! fc_run_timeout 5 docker info >/dev/null 2>&1; then
        add_skip "Docker: daemon is not running"
        return 0
    fi
    add_cmd_target "$CAT_DOCKER" "Unused images, containers, build cache" docker_prune \
        "not used by any container; pulled/built again when needed. Named volumes are kept"
}

collect_package_managers() {
    local dl="download cache, fetched again when needed"
    if fc_has_cmd npm; then
        add_cmd_target "$CAT_DEV" "npm cache" npm_cache "$dl"
    else
        add_dir_target "$CAT_DEV" "npm cache" "$HOME/.npm/_cacache" "$dl"
    fi
    add_cmd_target "$CAT_DEV" "yarn cache" yarn_cache "$dl"
    add_cmd_target "$CAT_DEV" "pnpm store (unreferenced packages)" pnpm_prune "packages no project uses any more"
    if fc_has_cmd bun; then
        add_cmd_target "$CAT_DEV" "bun cache" bun_cache "$dl"
    else
        add_dir_target "$CAT_DEV" "bun cache" "$HOME/.bun/install/cache" "$dl"
    fi
    add_cmd_target "$CAT_DEV" "Homebrew cleanup" brew_cleanup "old package versions and downloads"
    add_cmd_target "$CAT_DEV" "pip cache" pip_cache "$dl"
    add_cmd_target "$CAT_DEV" "uv cache (unused entries)" uv_prune "$dl"
    add_dir_target "$CAT_DEV" "Cargo registry cache" "$HOME/.cargo/registry/cache" "downloaded crates, fetched again when needed"

    add_dir_target "$CAT_DEV" "Xcode DerivedData" "$HOME/Library/Developer/Xcode/DerivedData" "build products, rebuilt by Xcode"
    add_dir_target "$CAT_DEV" "Simulator caches" "$HOME/Library/Developer/CoreSimulator/Caches" "rebuilt by the simulator"
    local platform
    for platform in iOS watchOS tvOS; do
        add_dir_target "$CAT_DEV" "Xcode device support files" "$HOME/Library/Developer/Xcode/$platform DeviceSupport" \
            "debug symbols, copied again when a device connects"
    done
    add_dir_target "$CAT_DEV" "Old iPhone/iPad firmware" "$HOME/Library/iTunes/iPhone Software Updates" ".ipsw files, downloaded again when needed"
    add_dir_target "$CAT_DEV" "Old iPhone/iPad firmware" "$HOME/Library/iTunes/iPad Software Updates" ".ipsw files, downloaded again when needed"
    if [ -d "$HOME/Library/Developer/CoreSimulator/Devices" ]; then
        if cmd_available simctl_unavailable; then
            add_cmd_target "$CAT_DEV" "Unavailable simulators" simctl_unavailable "simulators whose runtime is no longer installed"
        else
            add_skip "Unavailable simulators: simctl needs Xcode (the Command Line Tools alone do not provide it)"
        fi
    fi
}

collect_app_caches() {
    local skip_library_caches="$1"
    local app_support="$HOME/Library/Application Support"

    collect_electron_app "Cursor" "$app_support/Cursor"
    collect_electron_app "VS Code" "$app_support/Code"
    collect_electron_app "Windsurf" "$app_support/Windsurf"
    collect_electron_app "Antigravity" "$app_support/Antigravity"
    collect_electron_app "Slack" "$app_support/Slack"
    collect_electron_app "Notion" "$app_support/Notion"
    collect_electron_app "Discord" "$app_support/discord"
    collect_electron_app "Figma" "$app_support/Figma"
    collect_electron_app "Obsidian" "$app_support/obsidian"
    collect_electron_app "Postman" "$app_support/Postman"
    add_dir_target "$CAT_APPS" "Slack cache" "$app_support/Slack/Service Worker/CacheStorage" "app disk cache, rebuilt automatically"
    add_dir_target "$CAT_APPS" "Zed cache" "$app_support/Zed/Cache" "app disk cache, rebuilt automatically"
    add_dir_target "$CAT_APPS" "Spotify cache" "$app_support/Spotify/PersistentCache" "streaming cache, downloaded again when played"

    # Telegram media: <group container>/{stable,appstore,beta}/account-*/postbox/media
    local media
    shopt -s nullglob
    for media in "$HOME/Library/Group Containers/"*.ru.keepcoder.Telegram/*/account-*/postbox/media \
                 "$HOME/Library/Group Containers/"*.ru.keepcoder.Telegram/account-*/postbox/media; do
        add_dir_target "$CAT_APPS" "Telegram media cache" "$media" "downloaded media, fetched from Telegram cloud when opened"
    done
    shopt -u nullglob

    if [ "$skip_library_caches" = false ]; then
        add_dir_target "$CAT_APPS" "Spotify cache" "$HOME/Library/Caches/com.spotify.client" "streaming cache, downloaded again when played"
        add_dir_target "$CAT_APPS" "JetBrains caches" "$HOME/Library/Caches/JetBrains" "IDE indexes and caches, rebuilt on start"
    fi
}

collect_browser_caches() {
    local skip_library_caches="$1"
    local app_support="$HOME/Library/Application Support"

    collect_chromium_browser "Chrome" "$app_support/Google/Chrome"
    collect_chromium_browser "Arc" "$app_support/Arc/User Data"
    collect_chromium_browser "Brave" "$app_support/BraveSoftware/Brave-Browser"
    collect_chromium_browser "Edge" "$app_support/Microsoft Edge"

    if [ "$skip_library_caches" = false ]; then
        local reason="browser cache; cookies, history and passwords are kept"
        add_dir_target "$CAT_BROWSERS" "Chrome HTTP cache" "$HOME/Library/Caches/Google/Chrome" "$reason"
        add_dir_target "$CAT_BROWSERS" "Brave HTTP cache" "$HOME/Library/Caches/BraveSoftware" "$reason"
        add_dir_target "$CAT_BROWSERS" "Edge HTTP cache" "$HOME/Library/Caches/Microsoft Edge" "$reason"
        add_dir_target "$CAT_BROWSERS" "Firefox cache" "$HOME/Library/Caches/Firefox" "$reason"
    fi
}

# Temp dirs are shared with running processes (ssh-agent/launchd sockets, tmux, IDE helpers):
# only our own entries untouched for TEMP_FILE_AGE_DAYS are planned.
collect_temp_dir() {
    local dir="$1" label="$2"
    [ -d "$dir" ] || return 0
    local total
    total=$(find "$dir" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l | tr -d ' ')

    add_dir_target "$CAT_SYSTEM" "$label" "$dir" \
        "your temp files untouched for ${TEMP_FILE_AGE_DAYS}+ days" \
        -user "$(id -un)" -mtime +"$TEMP_FILE_AGE_DAYS" ! -type s \
        ! -name 'com.apple.*' ! -name 'tmux-*' ! -name '.X*' ! -name 'claude-*'

    local kept=$((total - LAST_COUNT))
    if [ "$kept" -gt 0 ]; then
        add_skip "$label: $(plural "$kept" entry | sed 's/entrys/entries/') kept (newer than ${TEMP_FILE_AGE_DAYS} days, sockets, system or other users' files)"
    fi
}

collect_system() {
    if [ "$CLEAN_SYSTEM_CACHES" = true ]; then
        add_dir_target "$CAT_SYSTEM" "User caches" "$HOME/Library/Caches" "app caches, rebuilt automatically"
        add_dir_target "$CAT_SYSTEM" "User logs" "$HOME/Library/Logs" "old app logs and crash reports"
    fi
    if [ "$CLEAN_TRASH" = true ]; then
        add_dir_target "$CAT_SYSTEM" "Trash" "$HOME/.Trash" "files you already deleted"
    fi
    if [ "$CLEAN_TEMP_FILES" = true ]; then
        collect_temp_dir /private/tmp "Temporary files (/tmp)"
        collect_temp_dir /private/var/tmp "Temporary files (/var/tmp)"
    fi
}

# Build a plan into $1.
collect_plan() {
    PLAN_FILE="$1"
    mkdir -p "$(dirname "$PLAN_FILE")"
    : > "$PLAN_FILE" || { log_fail "Cannot write plan file $PLAN_FILE"; return 1; }
    chmod 600 "$PLAN_FILE"
    {
        echo "$PLAN_HEADER"
        echo "# created=$(date +%s) date=$START_DATE uid=$(id -u) home=$HOME"
        echo "# Apply with: cleaner.sh --apply $PLAN_FILE — changed or missing items are kept."
        echo "# Lines: T=folder target, I=item (mtime, path) of the preceding target, C=cleanup command id"
    } >> "$PLAN_FILE"

    local skip_library_caches=false
    [ "$CLEAN_SYSTEM_CACHES" = true ] && skip_library_caches=true

    local name flag
    for name in DOCKER PACKAGE_MANAGERS APP_CACHES BROWSER_CACHES; do
        flag="CLEAN_$name"
        [ "${!flag}" = true ] || add_skip "$(printf '%s' "$name" | tr '_' ' ' | tr '[:upper:]' '[:lower:]'): disabled in cleaner.conf ($flag=false)"
    done
    for name in SYSTEM_CACHES TRASH TEMP_FILES; do
        flag="CLEAN_$name"
        [ "${!flag}" = true ] || add_skip "$(printf '%s' "$name" | tr '_' ' ' | tr '[:upper:]' '[:lower:]'): disabled in cleaner.conf ($flag=false)"
    done

    [ "$CLEAN_DOCKER" = true ] && collect_docker
    [ "$CLEAN_PACKAGE_MANAGERS" = true ] && collect_package_managers
    [ "$CLEAN_APP_CACHES" = true ] && collect_app_caches "$skip_library_caches"
    [ "$CLEAN_BROWSER_CACHES" = true ] && collect_browser_caches "$skip_library_caches"
    collect_system
    report_flush_category
    return 0
}

print_scan_summary() {
    if [ -n "$SKIPS" ]; then
        log ""
        log "⏭  Skipped"
        log "${SKIPS%$'\n'}"
    fi
    log ""
    log "$LOG_SEP"
    log "📊 Reclaimable: ~$(fmt_kb "$TOTAL_KB") in $TARGET_SEQ targets ($ITEM_TOTAL files/folders)"
    log "   Estimates: files in use or protected by macOS are only found while cleaning."
}

# ============================================================================
# EXECUTOR — applies a plan
# ============================================================================

A_CAT=""
A_LABEL=""
A_REMOVED=0
A_CHANGED=0
A_LOCKED=0
A_ERR=""

apply_flush() {
    [ -z "$A_LABEL" ] && return 0
    if [ -n "$A_ERR" ]; then
        log_fail "$A_LABEL: $A_ERR"
    elif [ "$A_LOCKED" -gt 0 ]; then
        log_warn "$A_LABEL: removed $A_REMOVED, $A_LOCKED locked or protected by macOS"
    elif [ "$A_REMOVED" -gt 0 ]; then
        local extra=""
        [ "$A_CHANGED" -gt 0 ] && extra=", $A_CHANGED changed since the scan — kept"
        log_ok "$A_LABEL: removed $(plural "$A_REMOVED" item)$extra"
    elif [ "$A_CHANGED" -gt 0 ]; then
        log_warn "$A_LABEL: $A_CHANGED changed since the scan — kept"
    else
        debug_log "$A_LABEL: nothing left to clean"
    fi
    A_LABEL=""; A_REMOVED=0; A_CHANGED=0; A_LOCKED=0; A_ERR=""
}

apply_begin() {
    local category="$1" label="$2"
    if [ "$label" != "$A_LABEL" ]; then
        apply_flush
        A_LABEL="$label"
    fi
    if [ "$category" != "$A_CAT" ]; then
        log ""
        log "$category"
        A_CAT="$category"
    fi
}

# Paths from a newline list → how many still exist
count_existing() {
    [ -z "$1" ] && { printf '0'; return; }
    printf '%s\n' "$1" | tr '\n' '\0' | xargs -0 stat -f x 2>/dev/null | wc -l | tr -d ' '
}

apply_dir_target() {
    local plan="$1" id="$2" dir="$4"
    apply_begin "$3" "$5"

    if [ "$VALIDATE_PATHS" = true ] && ! validate_path "$dir"; then
        A_ERR="path refused by safety checks ($dir)"
        return
    fi
    if [ -L "$dir" ] || [ ! -d "$dir" ]; then
        debug_log "$A_LABEL: $(tilde "$dir") no longer exists"
        return
    fi
    if [ "$(realpath "$dir" 2>/dev/null)" != "$dir" ]; then
        A_ERR="$(tilde "$dir") now resolves elsewhere — skipped"
        return
    fi

    local planned current unchanged n_outside n_present n_unchanged left
    planned=$(awk -F'\t' -v id="$id" '$1 == "I" && $2 == id {print $3 "\t" $4}' "$plan")
    [ -z "$planned" ] && return
    current=$(printf '%s\n' "$planned" | cut -f2- | tr '\n' '\0' | xargs -0 stat -f '%m%t%N' 2>/dev/null)
    # Only direct children of the folder whose mtime still matches the plan.
    unchanged=$(awk -F'\t' -v d="$dir/" '
        NR == FNR { now[$2] = $1; next }
        index($2, d) == 1 && substr($2, length(d) + 1) !~ /\// && ($2 in now) && now[$2] == $1 { print $2 }
    ' <(printf '%s\n' "$current") <(printf '%s\n' "$planned"))

    n_outside=$(printf '%s\n' "$planned" | awk -F'\t' -v d="$dir/" \
        'NF && !(index($2, d) == 1 && substr($2, length(d) + 1) !~ /\//)' | grep -c . || true)
    if [ "$n_outside" -gt 0 ]; then
        A_ERR="$n_outside planned entries are outside $(tilde "$dir") — refused"
    fi
    n_present=$(printf '%s' "$current" | grep -c . || true)
    n_unchanged=$(printf '%s' "$unchanged" | grep -c . || true)
    A_CHANGED=$((A_CHANGED + n_present - n_unchanged - n_outside))
    [ "$A_CHANGED" -lt 0 ] && A_CHANGED=0
    [ "$n_unchanged" -eq 0 ] && return

    # xargs keeps huge lists (e.g. Telegram media) below ARG_MAX
    printf '%s\n' "$unchanged" | tr '\n' '\0' | xargs -0 rm -rf 2>/dev/null
    left=$(count_existing "$unchanged")
    A_REMOVED=$((A_REMOVED + n_unchanged - left))
    A_LOCKED=$((A_LOCKED + left))
}

apply_cmd_target() {
    local cmd_id="$4"
    apply_begin "$3" "$5"

    case "$cmd_id" in
        docker_prune|npm_cache|yarn_cache|pnpm_prune|bun_cache|brew_cleanup|pip_cache|uv_prune|simctl_unavailable) ;;
        *)
            A_ERR="unknown command '$cmd_id' in plan — refused"
            return
            ;;
    esac
    if ! cmd_available "$cmd_id"; then
        # Not an error: the tool was uninstalled (or never fully installed) since the plan.
        log "ℹ️  $A_LABEL: its tool is not available — skipped"
        A_LABEL=""
        return
    fi
    if [ "$cmd_id" = docker_prune ] && ! fc_run_timeout 5 docker info >/dev/null 2>&1; then
        log "ℹ️  $A_LABEL: Docker is not running — skipped"
        A_LABEL=""
        return
    fi
    local out rc
    out=$(run_cmd_id "$cmd_id" 2>&1)
    rc=$?
    if [ "$rc" -eq 0 ]; then
        log_ok "$A_LABEL: done"
        A_LABEL=""
    else
        A_ERR="failed (exit $rc): $(printf '%s' "$out" | grep . | tail -1)"
    fi
}

# Refuse plans that are not ours: wrong header, other owner, writable by others.
check_plan_file() {
    local plan="$1"
    if [ ! -f "$plan" ] || [ -L "$plan" ]; then
        log_fail "Plan not found: $plan (create one with cleaner.sh --plan)"
        return 1
    fi
    if [ "$(stat -f %u "$plan")" != "$(id -u)" ]; then
        log_fail "Plan $plan is not owned by you — refused"
        return 1
    fi
    local perm
    perm=$(stat -f %Lp "$plan")
    if [ $(( 8#$perm & 8#022 )) -ne 0 ]; then
        log_fail "Plan $plan is writable by others (mode $perm) — refused"
        return 1
    fi
    if [ "$(head -1 "$plan")" != "$PLAN_HEADER" ]; then
        log_fail "$plan is not a fuck-cleanmymac plan (or an incompatible version)"
        return 1
    fi
    local created age_h
    created=$(sed -n '2s/.*created=\([0-9]*\).*/\1/p' "$plan")
    if [[ "$created" =~ ^[0-9]+$ ]]; then
        age_h=$(( ($(date +%s) - created) / 3600 ))
        if [ "$age_h" -ge "$PLAN_MAX_AGE_HOURS" ]; then
            log "⚠️  Plan is ${age_h} h old; everything changed since then is kept anyway."
        fi
    fi
    return 0
}

apply_plan() {
    local plan="$1"
    local kind id category label f5 rest
    while IFS=$'\t' read -r kind id category label f5 rest <&3; do
        case "$kind" in
            T) apply_dir_target "$plan" "$id" "$category" "$f5" "$label" ;;
            C) apply_cmd_target "$plan" "$id" "$category" "$f5" "$label" ;;
        esac
    done 3< <(grep -E $'^(T|C)\t' "$plan")
    apply_flush
}

rotate_logs() {
    [ -d "$LOG_DIR" ] || return 0
    local old_logs count
    old_logs=$(find "$LOG_DIR" -type f \( -name "*.log" -o -name "*.log.1" \) -mtime +"$LOG_RETENTION_DAYS" 2>/dev/null)
    [ -z "$old_logs" ] && return 0
    count=$(fc_count_lines "$old_logs")
    if find "$LOG_DIR" -type f \( -name "*.log" -o -name "*.log.1" \) -mtime +"$LOG_RETENTION_DAYS" -delete 2>/dev/null; then
        log_ok "Removed $count logs older than $LOG_RETENTION_DAYS days"
    else
        log_fail "Failed to rotate old logs"
    fi
}

# ============================================================================
# MAIN
# ============================================================================

finish_clean() {
    local before="$1" after diff runtime msg
    after=$(fc_disk_free_mb)
    diff=$(( ${after:-0} - before ))
    [ "$diff" -lt 0 ] && diff=0
    runtime=$(( $(date +%s) - START_SEC ))

    log ""
    log "$LOG_SEP"
    log "📊 SUMMARY:"
    log "✅ Freed: $diff MB"
    log "🧾 Cleaned: $CLEANED_COUNT | Partial: $WARN_COUNT | Failed: $FAIL_COUNT"
    log "⏱️  Runtime: $runtime seconds"
    log "=== COMPLETED [$(date "+%H:%M:%S")] ==="
    log "$LOG_SEP"

    if [ "$SHOW_NOTIFICATION" = true ]; then
        if [ "$diff" -gt 0 ]; then
            msg="Freed $diff MB in $runtime seconds"
        else
            msg="System already clean! (Took $runtime seconds)"
        fi
        [ "$FAIL_COUNT" -gt 0 ] && msg="$msg, $FAIL_COUNT failed (see log)"
        fc_notify "fuck cleanmymac" "$msg" "Cleanup completed"
    fi
}

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

    log "$LOG_SEP"
    case "$MODE" in
        scan) log "🔎 CLEANUP SCAN [$START_DATE] — nothing will be deleted" ;;
        plan) log "📝 CLEANUP PLAN [$START_DATE] — nothing will be deleted" ;;
        apply) log "▶️  APPLYING CLEANUP PLAN [$START_DATE]" ;;
        *) log "=== CLEANUP REPORT [$START_DATE] ===" ;;
    esac
    log "Config: ${CONFIG_SOURCE:-defaults (no cleaner.conf found)}"
    log "$LOG_SEP"

    local before
    case "$MODE" in
        scan)
            COLLECT_SIZES=true
            local tmp_plan
            tmp_plan=$(mktemp "$FC_STATE_DIR/scan.XXXXXX") || exit 1
            collect_plan "$tmp_plan"
            rm -f "$tmp_plan"
            print_scan_summary
            log "   To review exactly what will go: cleaner.sh --plan"
            ;;
        plan)
            COLLECT_SIZES=true
            local plan="${PLAN_ARG:-$DEFAULT_PLAN_FILE}"
            collect_plan "$plan" || exit 1
            print_scan_summary
            log ""
            log "📝 Plan saved: $plan"
            log "   Review it:  open -t \"$plan\""
            log "   Apply it:   cleaner.sh --apply${PLAN_ARG:+ \"$plan\"}"
            ;;
        apply)
            local plan="${PLAN_ARG:-$DEFAULT_PLAN_FILE}"
            check_plan_file "$plan" || exit 1
            before=$(fc_disk_free_mb)
            apply_plan "$plan"
            rotate_logs
            mv -f "$plan" "$plan.applied" 2>/dev/null || true
            finish_clean "${before:-0}"
            ;;
        *)
            local run_plan
            run_plan=$(mktemp "$FC_STATE_DIR/run.XXXXXX") || exit 1
            before=$(fc_disk_free_mb)
            collect_plan "$run_plan"
            if [ -n "$SKIPS" ] && [ "$VERBOSE_MODE" = true ]; then
                log "⏭  Skipped"
                log "${SKIPS%$'\n'}"
            fi
            apply_plan "$run_plan"
            rm -f "$run_plan"
            rotate_logs
            finish_clean "${before:-0}"
            ;;
    esac
    return 0
}

main "$@"
