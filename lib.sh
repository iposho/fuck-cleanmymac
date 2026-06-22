#!/bin/bash

fc_setup_path() {
    export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$PATH"
}

fc_has_cmd() {
    command -v "$1" >/dev/null 2>&1
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

    if ! fc_has_cmd osascript; then
        return 0
    fi

    local esc_title esc_message esc_subtitle
    esc_title=$(fc_escape_applescript "$title")
    esc_message=$(fc_escape_applescript "$message")
    esc_subtitle=$(fc_escape_applescript "$subtitle")

    if [ -n "$esc_subtitle" ]; then
        osascript -e "display notification \"$esc_message\" with title \"$esc_title\" subtitle \"$esc_subtitle\"" 2>/dev/null || true
    else
        osascript -e "display notification \"$esc_message\" with title \"$esc_title\"" 2>/dev/null || true
    fi
}

fc_prepare_log_file() {
    local log_dir="$1"
    local prefix="$2"
    local now

    mkdir -p "$log_dir"
    now=$(date +%Y%m%d_%H%M%S)
    printf '%s/%s_%s.log' "$log_dir" "$prefix" "$now"
}

fc_log() {
    local log_file="$1"
    local message="$2"

    if [ -n "$log_file" ]; then
        echo "$message" | tee -a "$log_file"
    else
        echo "$message"
    fi
}

fc_init_run_log() {
    local log_file="$1"
    local log_dir

    log_dir=$(dirname "$log_file")
    mkdir -p "$log_dir"

    if [ -t 1 ]; then
        exec > >(tee -a "$log_file") 2>&1
    else
        exec >> "$log_file" 2>&1
    fi
}
