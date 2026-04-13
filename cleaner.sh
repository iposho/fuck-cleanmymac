#!/bin/bash
set -uo pipefail

# Configure PATH for cron jobs
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$PATH"

# ============================================================================
# CONFIGURATION LOADING
# ============================================================================

# Default configuration values
DRY_RUN=false
VERBOSE_MODE=false
SHOW_NOTIFICATION=true
LOG_DIR="$HOME/.scripts/logs"
LOG_RETENTION_DAYS=90
VALIDATE_PATHS=true

CLEAN_SYSTEM_CACHES=true
CLEAN_APP_CACHES=true
CLEAN_PACKAGE_MANAGERS=true
CLEAN_BROWSER_CACHES=true
CLEAN_TRASH=true
CLEAN_TEMP_FILES=true
CLEAN_DOCKER=true

# Load configuration file from multiple locations
load_config() {
    local config_paths=(
        "$HOME/.config/fuck-cleanmymac/cleaner.conf"
        "$HOME/.scripts/cleaner.conf"
        "$(dirname "$0")/cleaner.conf"
        "./cleaner.conf"
    )

    for config_file in "${config_paths[@]}"; do
        if [ -f "$config_file" ]; then
            # shellcheck source=/dev/null
            source "$config_file"
            echo "Configuration loaded from: $config_file"
            return 0
        fi
    done

    echo "No configuration file found, using defaults"
    return 0
}

# ============================================================================
# COMMAND-LINE ARGUMENT HANDLING
# ============================================================================

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --verbose)
                VERBOSE_MODE=true
                shift
                ;;
            --no-notify)
                SHOW_NOTIFICATION=false
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

show_help() {
    cat << EOF
Usage: cleaner.sh [OPTIONS]

Options:
  --dry-run        Show what would be cleaned without actually deleting
  --verbose        Enable verbose logging
  --no-notify      Disable notifications
  --help           Show this help message

Examples:
  # Standard cleanup
  ./cleaner.sh

  # Preview what would be deleted
  ./cleaner.sh --dry-run

  # Cleanup without notifications
  ./cleaner.sh --no-notify

  # Preview with verbose output
  ./cleaner.sh --dry-run --verbose
EOF
}

# ============================================================================
# TIMING AND LOGGING SETUP
# ============================================================================

START_DATE=$(date "+%Y-%m-%d %H:%M:%S")
START_SEC=$(date +%s)
LOG_SEP="=================================================================================="

# Create log directory
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/cleaner_$(date +%Y%m%d_%H%M%S).log"

# Logging function
log() {
    local message="$1"
    echo "$message" | tee -a "$LOG_FILE"
}

debug_log() {
    if [ "$VERBOSE_MODE" = true ]; then
        log "🔍 DEBUG: $1"
    fi
}

# ============================================================================
# PATH VALIDATION FUNCTIONS
# ============================================================================

# Validate path: allow removals only within safe boundaries (user home or /Users/<user>)
# Returns 0 if path is valid for removal/cleaning, otherwise 1
validate_path() {
    local raw="$1"

    # Empty path is invalid
    if [ -z "$raw" ]; then
        return 1
    fi

    # Expand ~ and variables
    local expanded
    expanded=$(eval echo "$raw")

    # Resolve symlinks and canonicalize the path if possible
    if command -v realpath >/dev/null 2>&1; then
        # On macOS, realpath doesn't support -m. We try without it.
        expanded=$(realpath "$expanded" 2>/dev/null || printf "%s" "$expanded")
    elif command -v readlink >/dev/null 2>&1; then
        expanded=$(readlink -f "$expanded" 2>/dev/null || printf "%s" "$expanded")
    fi

    # Allow system temporary directories explicitly
    case "$expanded" in
        "/tmp"*|"/var/tmp"*|"/private/tmp"*|"/private/var/tmp"* )
            return 0
            ;;
    esac

    # Disallow other dangerous targets
    case "$expanded" in
        "/"|"/System"*|"/usr"*|"/bin"*|"/sbin"*|"/etc"*|"/private"* )
            debug_log "Path rejected (system path): $expanded"
            return 1
            ;;
    esac

    # Allow only subdirectories under the current user's home directory
    if [[ "$expanded" == "$HOME"* ]]; then
        return 0
    fi

    # Allow /Users/<anything> but only if it's not the top-level /Users
    if [[ "$expanded" == /Users/* ]]; then
        if [[ "$expanded" != "/Users" && "$expanded" != "/Users/" ]]; then
            return 0
        fi
    fi

    # Default: invalid
    debug_log "Path rejected (not in safe location): $expanded"
    return 1
}

# ============================================================================
# SAFE REMOVAL AND CLEANING FUNCTIONS
# ============================================================================

# Safe removal function — uses validate_path and logs the expanded path
safe_remove() {
    local path="$1"
    local description="$2"

    # Expand path for validation and logging
    local expanded
    expanded=$(eval echo "$path")

    if [ "$VALIDATE_PATHS" = true ] && ! validate_path "$expanded"; then
        log "❌ Skipped removal of $description: path not validated or too broad: $expanded"
        return 1
    fi

    if [ -e "$expanded" ]; then
        if [ "$DRY_RUN" = true ]; then
            log "🏜  [DRY-RUN] Would remove: $description ($expanded)"
        else
            if rm -rf "$expanded" 2>/dev/null; then
                log "✅ $description removed ($expanded)"
            else
                log "❌ Failed to remove $description ($expanded)"
            fi
        fi
    else
        debug_log "$description not found ($expanded)"
    fi
}

# Safe directory-clean function — cleans directory contents, not the directory itself
safe_clean() {
    local path="$1"
    local description="$2"

    # Expand path for validation and logging
    local expanded
    expanded=$(eval echo "$path")

    if [ "$VALIDATE_PATHS" = true ] && ! validate_path "$expanded"; then
        log "❌ Skipped cleaning $description: path not validated or too broad: $expanded"
        return 1
    fi

    if [ -d "$expanded" ]; then
        # Find at least one entry inside
        local first_entry
        first_entry=$(find "$expanded" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null || true)

        if [ -n "$first_entry" ]; then
            if [ "$DRY_RUN" = true ]; then
                local item_count
                item_count=$(find "$expanded" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l)
                log "🏜  [DRY-RUN] Would clean: $description (~$item_count items in $expanded)"
            else
                if rm -rf "$expanded"/* 2>/dev/null; then
                    log "✅ $description cleaned ($expanded)"
                else
                    # For system temp directories, naturally some files will be unremovable without sudo
                    if [[ "$expanded" == "/tmp"* || "$expanded" == "/var/tmp"* || "$expanded" == "/private/tmp"* || "$expanded" == "/private/var/tmp"* ]]; then
                        log "✅ $description cleaned (best-effort, skipped system-locked files)"
                    else
                        log "❌ Failed to clean $description ($expanded)"
                    fi
                fi
            fi
        else
            debug_log "$description is already empty ($expanded)"
        fi
    else
        debug_log "$description not found ($expanded)"
    fi
}

# ============================================================================
# MAIN CLEANUP ROUTINE
# ============================================================================

main() {
    # Load configuration
    load_config

    # Parse command-line arguments
    parse_arguments "$@"

    # Calculate free space BEFORE (in megabytes)
    BEFORE=$(df -m / | awk 'NR==2 {print $4}')

    log "$LOG_SEP"
    if [ "$DRY_RUN" = true ]; then
        log "🏜  DRY-RUN MODE - No files will be deleted"
    fi
    log "=== CLEANUP REPORT [$START_DATE] ==="
    log "$LOG_SEP"

    # 1. DOCKER CLEANUP
    if [ "$CLEAN_DOCKER" = true ]; then
        log "🐳 Docker cleanup..."
        if command -v docker &> /dev/null; then
            (docker info > /dev/null 2>&1) &
            DOCKER_PID=$!
            counter=0
            while kill -0 $DOCKER_PID 2>/dev/null && [ $counter -lt 5 ]; do
                sleep 1
                ((counter++))
            done

            if kill -0 $DOCKER_PID 2>/dev/null; then
                kill -9 $DOCKER_PID 2>/dev/null
                log "⚠️  Docker daemon unresponsive. Skipping."
            else
                if [ "$DRY_RUN" = true ]; then
                    log "🏜  [DRY-RUN] Would prune Docker images, containers, and volumes"
                else
                    if docker system prune -af --volumes > /dev/null 2>&1; then
                        log "✅ Docker system prune completed"
                    else
                        log "❌ Failed to prune Docker system"
                    fi

                    if docker builder prune -af > /dev/null 2>&1; then
                        log "✅ Docker builder cache pruned"
                    else
                        log "❌ Failed to prune Docker builder"
                    fi
                fi
            fi
        else
            debug_log "Docker not installed"
        fi
    fi

    log "$LOG_SEP"

    # 2. PACKAGE MANAGER CLEANUP
    if [ "$CLEAN_PACKAGE_MANAGERS" = true ]; then
        log "📦 Package manager cleanup..."

        # npm cache
        if [ -d ~/.npm ]; then
            if [ "$DRY_RUN" = true ]; then
                log "🏜  [DRY-RUN] Would clean npm cache"
            else
                if command -v npm &> /dev/null; then
                    if npm cache clean --force > /dev/null 2>&1; then
                        log "✅ npm cache cleaned (via npm CLI)"
                    else
                        log "⚠️  npm cache clean failed, falling back to manual removal"
                        safe_clean ~/.npm "npm cache"
                    fi
                else
                    log "⚠️  npm command not found, performing manual cache removal"
                    safe_clean ~/.npm "npm cache"
                fi
            fi
        fi

        # yarn cache
        if [ -d ~/.cache/yarn ]; then
            if [ "$DRY_RUN" = true ]; then
                log "🏜  [DRY-RUN] Would clean yarn cache"
            else
                if yarn cache clean > /dev/null 2>&1; then
                    log "✅ yarn cache cleaned"
                else
                    log "❌ Failed to clean yarn cache"
                fi
            fi
        fi

        # Homebrew
        if command -v brew &> /dev/null; then
            if [ "$DRY_RUN" = true ]; then
                log "🏜  [DRY-RUN] Would clean Homebrew cache"
            else
                if brew cleanup -s > /dev/null 2>&1; then
                    log "✅ Homebrew cleaned"
                else
                    log "❌ Failed to clean Homebrew"
                fi
            fi
        fi

        # pip cache
        if [ -d ~/.cache/pip ]; then
            if [ "$DRY_RUN" = true ]; then
                log "🏜  [DRY-RUN] Would clean pip cache"
            else
                if rm -rf ~/.cache/pip 2>/dev/null; then
                    log "✅ pip cache cleaned"
                else
                    log "❌ Failed to clean pip cache"
                fi
            fi
        fi

        # Xcode DerivedData
        if [ -d ~/Library/Developer/Xcode/DerivedData ]; then
            if [ "$DRY_RUN" = true ]; then
                log "🏜  [DRY-RUN] Would clean Xcode Derived Data"
            else
                safe_clean ~/Library/Developer/Xcode/DerivedData "Xcode Derived Data"
            fi
        fi
    fi

    log "$LOG_SEP"

    # 3. APPLICATION-SPECIFIC CLEANUP
    if [ "$CLEAN_APP_CACHES" = true ]; then
        log "🖥  Application cache cleanup..."

        # Cursor
        safe_clean ~/Library/Application\ Support/Cursor/Cache "Cursor Cache"

        # Spotify
        safe_clean ~/Library/Caches/com.spotify.client "Spotify Cache"
        safe_clean ~/Library/Application\ Support/Spotify/PersistentCache "Spotify Persistent Cache"

        # Notion
        safe_clean ~/Library/Application\ Support/Notion/Cache "Notion Cache"

        # Slack
        if [ -d ~/Library/Application\ Support/Slack ]; then
            safe_clean ~/Library/Application\ Support/Slack/Cache "Slack Cache"
            safe_clean ~/Library/Application\ Support/Slack/Service\ Worker/CacheStorage "Slack Service Worker Cache"
        fi

        # Telegram media cache
        for tg_dir in ~/Library/Group\ Containers/*.ru.keepcoder.Telegram; do
            if [ -d "$tg_dir" ]; then
                for account_dir in "$tg_dir"/account-*; do
                    if [ -d "$account_dir/postbox/media" ]; then
                        safe_clean "$account_dir/postbox/media" "Telegram Media Cache"
                    fi
                done
                break
            fi
        done

        # JetBrains IDEs
        if [ -d ~/Library/Caches/JetBrains ]; then
            if [ "$DRY_RUN" = true ]; then
                log "🏜  [DRY-RUN] Would clean JetBrains caches"
            else
                find ~/Library/Caches/JetBrains -name "*WebStorm*" -type d -exec rm -rf {}/* + 2>/dev/null && \
                    log "✅ JetBrains caches cleaned" || \
                    log "❌ Failed to clean JetBrains caches"
            fi
        fi
    fi

    # Browser caches (optional)
    if [ "$CLEAN_BROWSER_CACHES" = true ]; then
        safe_clean ~/Library/Application\ Support/Google/Chrome/Default/Cache "Chrome Cache"
        # safe_clean ~/Library/Safari/History.db-wal "Safari History Cache"
    fi

    log "$LOG_SEP"

    # 4. SYSTEM CLEANUP
    if [ "$CLEAN_SYSTEM_CACHES" = true ] || [ "$CLEAN_TRASH" = true ] || [ "$CLEAN_TEMP_FILES" = true ]; then
        log "🗑  System maintenance..."

        # System caches
        if [ "$CLEAN_SYSTEM_CACHES" = true ]; then
            safe_clean ~/Library/Caches "User caches"
            safe_clean ~/Library/Logs "User logs"
        fi

        # Trash
        if [ "$CLEAN_TRASH" = true ]; then
            safe_clean ~/.Trash "Trash"
        fi

        # Temp files
        if [ "$CLEAN_TEMP_FILES" = true ]; then
            safe_clean /tmp/ "Temporary files (/tmp)"
            safe_clean /var/tmp/ "Temporary files (/var/tmp)"
        fi
    fi

    log "$LOG_SEP"

    # 5. LOG ROTATION
    log "📜 Rotating old cleanup logs..."
    if find "$LOG_DIR" -name "*.log" -type f -mtime +$LOG_RETENTION_DAYS -delete 2>/dev/null; then
        log "✅ Old logs removed (older than $LOG_RETENTION_DAYS days)"
    else
        log "❌ Failed to rotate old logs"
    fi

    log "$LOG_SEP"

    # SUMMARY
    AFTER=$(df -m / | awk 'NR==2 {print $4}')
    DIFF=$((AFTER - BEFORE))
    [ $DIFF -lt 0 ] && DIFF=0

    END_SEC=$(date +%s)
    RUNTIME=$((END_SEC - START_SEC))

    log "📊 SUMMARY:"
    if [ "$DRY_RUN" = true ]; then
        log "🏜  DRY-RUN: No files were actually deleted"
        log "⏱️  Scan time: $RUNTIME seconds"
    else
        log "✅ Freed: $DIFF MB"
        log "⏱️  Runtime: $RUNTIME seconds"
    fi
    log "=== COMPLETED [$(date "+%H:%M:%S")] ==="
    log "$LOG_SEP"

    # NOTIFICATION
    if [ "$SHOW_NOTIFICATION" = true ] && [ "$DRY_RUN" = false ]; then
        if command -v osascript >/dev/null 2>&1; then
            if [ $DIFF -gt 0 ]; then
                MSG="Freed $DIFF MB in $RUNTIME seconds"
            else
                MSG="System already clean! (Took $RUNTIME seconds)"
            fi

            # Escape quotes and backslashes for AppleScript
            MSG="${MSG//\\/\\\\}"
            MSG="${MSG//\"/\\\"}"

            osascript -e "display notification \"$MSG\" with title \"fuck cleanmymac\" subtitle \"Cleanup completed\"" \
                2>/dev/null || true
        fi
    fi

    return 0
}

# Run main function with all arguments
main "$@"
