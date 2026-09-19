#!/bin/bash
# Shared helpers for fuck-cleanmymac scripts

FC_STATE_DIR="$HOME/.cache/fuck-cleanmymac"
FC_LOG_MAX_BYTES=$((1024 * 1024))

# Latest installed node under nvm matching the default alias (cron/launchd do not load nvm).
fc_nvm_bin() {
    local nvm_dir="${NVM_DIR:-$HOME/.nvm}"
    local alias_ver=""
    [ -d "$nvm_dir/versions/node" ] || return 1

    if [ -f "$nvm_dir/alias/default" ]; then
        alias_ver=$(tr -d '[:space:]' < "$nvm_dir/alias/default")
        alias_ver="${alias_ver#v}"
        # Only numeric aliases (20, 20.1, 20.1.0) map directly to a directory prefix.
        [[ "$alias_ver" =~ ^[0-9.]+$ ]] || alias_ver=""
    fi

    local best
    best=$(find "$nvm_dir/versions/node" -mindepth 1 -maxdepth 1 -type d -name "v${alias_ver}*" 2>/dev/null \
        | sort -V | tail -1)
    [ -n "$best" ] && [ -d "$best/bin" ] || return 1
    printf '%s/bin' "$best"
}

# Make tools reachable from cron/launchd/SwiftBar without overriding the caller's PATH:
# missing directories are appended, nvm's default node before Homebrew's.
fc_setup_path() {
    local dirs=() dir nvm_bin
    if nvm_bin=$(fc_nvm_bin); then
        dirs+=("$nvm_bin")
    fi
    dirs+=(/opt/homebrew/bin /opt/homebrew/sbin /usr/local/bin /usr/bin /bin /usr/sbin /sbin
        "$HOME/.local/bin" "$HOME/.cargo/bin" "$HOME/.bun/bin" "$HOME/Library/pnpm")

    for dir in "${dirs[@]}"; do
        case ":$PATH:" in
            *":$dir:"*) ;;
            *) [ -d "$dir" ] && PATH="${PATH:+$PATH:}$dir" ;;
        esac
    done
    export PATH
    return 0
}

fc_has_cmd() {
    command -v "$1" >/dev/null 2>&1
}

fc_toolkit_version() {
    local root="${1:-}"
    local candidate
    for candidate in \
        "${root:+$root/VERSION}" \
        "$HOME/.scripts/fuck-cleanmymac/VERSION"
    do
        [ -z "$candidate" ] && continue
        if [ -f "$candidate" ]; then
            tr -d '[:space:]' < "$candidate"
            printf '\n'
            return 0
        fi
    done
    printf 'unknown\n'
}

fc_escape_applescript() {
    local value="${1//\\/\\\\}"
    value="${value//\"/\\\"}"
    printf '%s' "$value"
}

fc_notify() {
    local title="${1:-Notification}"
    local message="${2:-}"
    local subtitle="${3:-}"

    fc_has_cmd osascript || return 0

    local script
    script="display notification \"$(fc_escape_applescript "$message")\" with title \"$(fc_escape_applescript "$title")\""
    if [ -n "$subtitle" ]; then
        script="$script subtitle \"$(fc_escape_applescript "$subtitle")\""
    fi
    osascript -e "$script" >/dev/null 2>&1 || true
}

fc_prepare_log_file() {
    local log_dir="$1"
    local prefix="$2"

    mkdir -p "$log_dir"
    printf '%s/%s_%s.log' "$log_dir" "$prefix" "$(date +%Y%m%d_%H%M%S)"
}

# Print to stdout and append to the log file (no tee process per line).
fc_log() {
    local log_file="$1"
    local message="$2"

    printf '%s\n' "$message"
    if [ -n "$log_file" ]; then
        printf '%s\n' "$message" >> "$log_file"
    fi
}

# Keep append-only logs bounded: roll over to <file>.1 once they exceed FC_LOG_MAX_BYTES.
fc_rotate_log() {
    local log_file="$1"
    local size
    [ -f "$log_file" ] || return 0
    size=$(stat -f %z "$log_file" 2>/dev/null || echo 0)
    if [ "${size:-0}" -gt "$FC_LOG_MAX_BYTES" ]; then
        mv -f "$log_file" "$log_file.1" 2>/dev/null || true
    fi
}

fc_init_run_log() {
    local log_file="$1"

    mkdir -p "$(dirname "$log_file")"
    fc_rotate_log "$log_file"

    if [ -t 1 ]; then
        exec > >(tee -a "$log_file") 2>&1
    else
        exec >> "$log_file" 2>&1
    fi
}

# Single-instance guard (cron + SwiftBar can start the same script concurrently).
# Usage: fc_acquire_lock <name> || exit 0 ; lock is released on exit.
fc_acquire_lock() {
    local name="$1"
    local lock_dir="$FC_STATE_DIR/$name.lock"
    local other_pid

    mkdir -p "$FC_STATE_DIR"
    if ! mkdir "$lock_dir" 2>/dev/null; then
        other_pid=$(cat "$lock_dir/pid" 2>/dev/null || true)
        if [[ "$other_pid" =~ ^[0-9]+$ ]] && kill -0 "$other_pid" 2>/dev/null; then
            echo "⚠️  $name is already running (PID $other_pid). Exiting."
            return 1
        fi
        # Stale lock from a crashed run
        rm -rf "$lock_dir"
        mkdir "$lock_dir" 2>/dev/null || return 1
    fi
    echo "$$" > "$lock_dir/pid"
    FC_LOCK_DIR="$lock_dir"
    trap 'rm -rf "$FC_LOCK_DIR"' EXIT
    return 0
}

# Run a command with a soft timeout (seconds). Returns 124 on timeout.
# Prefer GNU/coreutils timeout when available; otherwise poll+kill.
fc_run_timeout() {
    local secs="${1:-5}"
    shift

    if fc_has_cmd timeout; then
        timeout "$secs" "$@"
        return $?
    fi
    if fc_has_cmd gtimeout; then
        gtimeout "$secs" "$@"
        return $?
    fi

    "$@" &
    local pid=$!
    local ticks=0
    local max_ticks=$((secs * 10))
    # Poll every 100 ms so fast commands do not pay a full-second penalty.
    while kill -0 "$pid" 2>/dev/null && [ "$ticks" -lt "$max_ticks" ]; do
        sleep 0.1
        ticks=$((ticks + 1))
    done

    if kill -0 "$pid" 2>/dev/null; then
        kill -TERM "$pid" 2>/dev/null || true
        sleep 0.2
        kill -KILL "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
        return 124
    fi

    wait "$pid" 2>/dev/null
}

# Run a check command keeping its outcome apart from its output.
# Sets CHECK_OUT (stdout), CHECK_ERR (stderr) and CHECK_RC (exit code).
fc_capture() {
    local err_file
    err_file=$(mktemp "${TMPDIR:-/tmp}/fc-capture.XXXXXX") || return 1
    CHECK_OUT=$("$@" 2>"$err_file")
    CHECK_RC=$?
    CHECK_ERR=$(cat "$err_file" 2>/dev/null)
    rm -f "$err_file"
    return 0
}

# Count non-blank lines of a string (pure bash, no subprocess).
fc_count_lines() {
    local text="${1-}"
    local count=0
    local line
    while IFS= read -r line; do
        [[ "$line" =~ [^[:space:]] ]] && count=$((count + 1))
    done <<< "$text"
    printf '%s' "$count"
}

fc_disk_free_mb() {
    df -m / 2>/dev/null | awk 'NR==2 {print $4}'
}
