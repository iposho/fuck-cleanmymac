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
fc_init_run_log "$LOG_DIR/health.log"

# Set HEALTH_EXTERNAL_IP=false to skip the external IP lookup (contacts ifconfig.me).
HEALTH_EXTERNAL_IP="${HEALTH_EXTERNAL_IP:-true}"

START_DATE=$(date "+%Y-%m-%d %H:%M:%S")
SUB_SEP="═══════════════════════════════════════════════════════════"

PERCENT_USED=""
DATA_WRITTEN=""
DATA_READ=""
MAX_CAPACITY=""
TEMP=""
SSD_TEMP=""
MESSAGE=""
TITLE="System Health Report"
USED_PERCENT=0
LOAD_STATUS="Unknown"

# Safe integer coercion for arithmetic under set -u
fc_int() {
    local v="${1:-0}"
    if [[ "$v" =~ ^[0-9]+$ ]]; then
        printf '%s' "$v"
    else
        printf '0'
    fi
}

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║       fuck cleanmymac: SYSTEM STATUS REPORT                  ║"
printf '║       %-55s║\n' "$START_DATE"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# ═════════════════════════════════════════════════════════════
# 1. SYSTEM INFORMATION
# ═════════════════════════════════════════════════════════════

echo "🖥️  SYSTEM INFORMATION"
echo "$SUB_SEP"

MODEL=$(sysctl -n hw.model 2>/dev/null || echo "Unknown")
# Prefer a fast marketing-name lookup; avoid full system_profiler (multi-second).
MARKETING_NAME=""
if [ -f /System/Library/PrivateFrameworks/ServerInformation.framework/Versions/A/Resources/English.lproj/SIMachineAttributes.plist ]; then
    MARKETING_NAME=$(/usr/libexec/PlistBuddy -c "Print :$MODEL:_LOCALIZABLE_:marketingModel" \
        /System/Library/PrivateFrameworks/ServerInformation.framework/Versions/A/Resources/English.lproj/SIMachineAttributes.plist 2>/dev/null || true)
fi
if [ -z "$MARKETING_NAME" ]; then
    MARKETING_NAME=$(ioreg -c IOPlatformExpertDevice -d 2 2>/dev/null \
        | awk -F'"' '/"product-name"/ {print $4; exit}')
fi
if [ -n "$MARKETING_NAME" ]; then
    echo "Hardware:       $MODEL ($MARKETING_NAME)"
else
    echo "Hardware:       $MODEL"
fi

CPU_COUNT=$(sysctl -n hw.ncpu 2>/dev/null || echo "?")
CPU_MODEL=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || true)
CPU_MODEL=${CPU_MODEL:-Unknown}
echo "CPU:            $CPU_COUNT cores - $CPU_MODEL"

MEMORY=$(sysctl -n hw.memsize 2>/dev/null || echo 0)
MEMORY_GB=$(( $(fc_int "$MEMORY") / 1073741824 ))
echo "Memory:         ${MEMORY_GB} GB"

OS_VERSION=$(sw_vers -productVersion 2>/dev/null || echo "?")
OS_BUILD=$(sw_vers -buildVersion 2>/dev/null || echo "?")
OS_NAME=$(sw_vers -productName 2>/dev/null || echo "macOS")
echo "System:         $OS_NAME $OS_VERSION ($OS_BUILD)"

BOOT_TIME=$(sysctl -n kern.boottime 2>/dev/null | awk -F'sec = ' '{print $2}' | awk -F',' '{print $1}')
CURRENT_TIME=$(date +%s)
if [[ "$BOOT_TIME" =~ ^[0-9]+$ ]]; then
    UPTIME_SECONDS=$((CURRENT_TIME - BOOT_TIME))
    UPTIME_DAYS=$((UPTIME_SECONDS / 86400))
    UPTIME_HOURS=$(((UPTIME_SECONDS % 86400) / 3600))
    UPTIME_MINS=$(((UPTIME_SECONDS % 3600) / 60))
    echo "Uptime:         ${UPTIME_DAYS}d ${UPTIME_HOURS}h ${UPTIME_MINS}m"
else
    echo "Uptime:         unknown"
fi

echo ""

# ═════════════════════════════════════════════════════════════
# 2. STORAGE INFORMATION
# ═════════════════════════════════════════════════════════════

echo "💾 STORAGE INFORMATION"
echo "$SUB_SEP"

if fc_has_cmd smartctl; then
    # -a is needed: -i has no health data, and NVMe drives never print "SMART support".
    DISK_INFO=$(fc_run_timeout 5 smartctl -a disk0 2>/dev/null || true)
    smart_field() {
        printf '%s\n' "$DISK_INFO" | awk -F': *' -v key="$1" '$1 ~ key {print $2; exit}'
    }
    SMART_STATUS=$(smart_field "SMART overall-health")
    if [ -n "$SMART_STATUS" ]; then
        SSD_MODEL=$(smart_field "^Model Number")
        PERCENT_USED=$(smart_field "^Percentage Used" | tr -dc '0-9')
        DATA_WRITTEN=$(smart_field "^Data Units Written" | sed -n 's/.*\[\(.*\)\].*/\1/p')
        DATA_READ=$(smart_field "^Data Units Read" | sed -n 's/.*\[\(.*\)\].*/\1/p')
        POWER_ON=$(smart_field "^Power On Hours" | tr -dc '0-9')
        MEDIA_ERRORS=$(smart_field "^Media and Data Integrity Errors" | tr -dc '0-9')
        SSD_TEMP=$(smart_field "^Temperature" | tr -dc '0-9')

        if [ "$SMART_STATUS" = "PASSED" ]; then
            echo "🟢 SMART Status:  $SMART_STATUS"
        else
            echo "🔴 SMART Status:  $SMART_STATUS"
        fi
        [ -n "$SSD_MODEL" ] && echo "Model:           $SSD_MODEL"
        if [ -n "$PERCENT_USED" ]; then
            if [ "$PERCENT_USED" -ge 80 ]; then WEAR_ICON="🔴"
            elif [ "$PERCENT_USED" -ge 50 ]; then WEAR_ICON="🟡"
            else WEAR_ICON="🟢"; fi
            echo "$WEAR_ICON Wear Level:    ${PERCENT_USED}% of rated endurance used"
        fi
        echo "Data Written:    ${DATA_WRITTEN:-N/A}"
        echo "Data Read:       ${DATA_READ:-N/A}"
        [ -n "$POWER_ON" ] && echo "Power On:        ${POWER_ON} h (~$((POWER_ON / 24)) days)"
        [ -n "$MEDIA_ERRORS" ] && [ "$MEDIA_ERRORS" -gt 0 ] && echo "🔴 Media errors:  $MEDIA_ERRORS"
        [ -n "$SSD_TEMP" ] && echo "SSD Temperature: ${SSD_TEMP}°C"
    else
        echo "ℹ️  SMART data unavailable for disk0"
    fi
else
    echo "ℹ️  Install smartmontools for SSD health: brew install smartmontools"
fi

echo ""
echo "Disk Space Usage:"
df -H / 2>/dev/null | awk 'NR==2 {printf "  Total: %s | Used: %s (%s) | Available: %s\n", $2, $3, $5, $4}'
echo ""

# ═════════════════════════════════════════════════════════════
# 3. BATTERY INFORMATION
# ═════════════════════════════════════════════════════════════

echo "🔋 BATTERY INFORMATION"
echo "$SUB_SEP"

BATT_INFO=$(pmset -g batt 2>/dev/null || true)

if echo "$BATT_INFO" | grep -q "InternalBattery"; then
    POWER_SOURCE=$(echo "$BATT_INFO" | head -1 | sed -n "s/^Now drawing from '\(.*\)'/\1/p")
    BATT_LINE=$(echo "$BATT_INFO" | grep "InternalBattery" | head -1)
    CHARGE=$(echo "$BATT_LINE" | grep -o '[0-9]\+%' | head -1)
    TIME_REMAINING=$(echo "$BATT_LINE" | grep -o '[0-9]\+:[0-9]\+' | head -1)
    CHARGE_STATE=$(echo "$BATT_LINE" | awk -F';' '{gsub(/^ +| +$/, "", $2); print $2}')

    BATT_IOREG=$(ioreg -rc AppleSmartBattery -l 2>/dev/null || true)
    CYCLES=$(echo "$BATT_IOREG" | awk -F'= ' '/^[[:space:]]+"CycleCount"[[:space:]]*=/ {gsub(/[^0-9]/, "", $2); print $2; exit}')
    RAW_MAX_CAPACITY=$(echo "$BATT_IOREG" | awk -F'= ' '/^[[:space:]]+"AppleRawMaxCapacity"[[:space:]]*=/ {gsub(/[^0-9]/, "", $2); print $2; exit}')
    DESIGN_CAPACITY=$(echo "$BATT_IOREG" | awk -F'= ' '/^[[:space:]]+"DesignCapacity"[[:space:]]*=/ {gsub(/[^0-9]/, "", $2); print $2; exit}')
    CONDITION=$(echo "$BATT_IOREG" | awk -F'= ' '/^[[:space:]]+"BatteryHealth"[[:space:]]*=/ {gsub(/"/, "", $2); gsub(/^ +| +$/, "", $2); print $2; exit}')

    if [ -z "$RAW_MAX_CAPACITY" ]; then
        RAW_MAX_CAPACITY=$(echo "$BATT_IOREG" | awk -F'= ' '/^[[:space:]]+"NominalChargeCapacity"[[:space:]]*=/ {gsub(/[^0-9]/, "", $2); print $2; exit}')
    fi

    if [[ "$RAW_MAX_CAPACITY" =~ ^[0-9]+$ && "$DESIGN_CAPACITY" =~ ^[0-9]+$ && "$DESIGN_CAPACITY" -gt 0 ]]; then
        MAX_CAPACITY=$((RAW_MAX_CAPACITY * 100 / DESIGN_CAPACITY))
    else
        MAX_CAPACITY=""
    fi

    [ -n "$POWER_SOURCE" ] && echo "Power Source:   $POWER_SOURCE"
    [ -n "$CHARGE" ] && echo "Current Charge: $CHARGE ($CHARGE_STATE)"
    if [ -n "$TIME_REMAINING" ] && [ "$TIME_REMAINING" != "0:00" ]; then
        echo "Time Remaining: $TIME_REMAINING"
    fi
    [ -n "$CONDITION" ] && echo "Condition:      $CONDITION"
    echo ""

    if [[ "$MAX_CAPACITY" =~ ^[0-9]+$ ]]; then
        if [[ "$MAX_CAPACITY" -ge 90 ]]; then
            BAT_ICON="🟢"; BAT_STATUS="Excellent"
        elif [[ "$MAX_CAPACITY" -ge 80 ]]; then
            BAT_ICON="🟢"; BAT_STATUS="Good"
        elif [[ "$MAX_CAPACITY" -ge 70 ]]; then
            BAT_ICON="🟡"; BAT_STATUS="Fair"
        else
            BAT_ICON="🔴"; BAT_STATUS="Replace Soon"
        fi
        echo "$BAT_ICON Assessment:         $BAT_STATUS (${MAX_CAPACITY}%)"
    else
        BAT_ICON="⚪"; BAT_STATUS="Unknown"
        echo "$BAT_ICON Assessment:         $BAT_STATUS"
    fi

    if [[ "$CYCLES" =~ ^[0-9]+$ ]]; then
        # Apple rates modern MacBook batteries for 1000 cycles.
        CYCLES_REMAINING=$((1000 - CYCLES))
        if [[ "$CYCLES_REMAINING" -gt 0 ]]; then
            echo "   Cycles Used:         $CYCLES / 1000 ($CYCLES_REMAINING left in Apple's rating)"
        else
            echo "   Cycles Used:         $CYCLES (past Apple's 1000-cycle rating)"
        fi
    fi
else
    echo "ℹ️  No battery detected (desktop Mac or battery unavailable)"
fi

echo ""

# ═════════════════════════════════════════════════════════════
# 4. MEMORY USAGE
# ═════════════════════════════════════════════════════════════

echo "🧠 MEMORY USAGE"
echo "$SUB_SEP"

TOTAL_MEM=$(sysctl -n hw.memsize 2>/dev/null || echo 0)
TOTAL_MEM_GB=$(( $(fc_int "$TOTAL_MEM") / 1073741824 ))
[ "$TOTAL_MEM_GB" -eq 0 ] && TOTAL_MEM_GB=1

VM_STAT=$(vm_stat 2>/dev/null || true)
PAGE_SIZE=$(echo "$VM_STAT" | head -1 | awk -F'page size of ' '{print $2}' | awk '{print $1}')
PAGE_SIZE=$(fc_int "${PAGE_SIZE:-4096}")
[ "$PAGE_SIZE" -eq 0 ] && PAGE_SIZE=4096

vm_pages() {
    printf '%s\n' "$VM_STAT" | awk -F': *' -v key="$1" '$1 == key {gsub(/\./, "", $2); print $2; exit}'
}

PAGES_WIRED=$(fc_int "$(vm_pages "Pages wired down")")
PAGES_ACTIVE=$(fc_int "$(vm_pages "Pages active")")
PAGES_INACTIVE=$(fc_int "$(vm_pages "Pages inactive")")
PAGES_FREE=$(fc_int "$(vm_pages "Pages free")")
PAGES_ANON=$(fc_int "$(vm_pages "Anonymous pages")")
PAGES_PURGEABLE=$(fc_int "$(vm_pages "Pages purgeable")")
# Physical RAM held by the compressor (not the larger uncompressed "stored" size)
PAGES_COMPRESSED=$(fc_int "$(vm_pages "Pages occupied by compressor")")

page_mb() { echo $(( $1 * PAGE_SIZE / 1048576 )); }
WIRED_MB=$(page_mb "$PAGES_WIRED")
ACTIVE_MB=$(page_mb "$PAGES_ACTIVE")
INACTIVE_MB=$(page_mb "$PAGES_INACTIVE")
FREE_MB=$(page_mb "$PAGES_FREE")
COMPRESSED_MB=$(page_mb "$PAGES_COMPRESSED")
APP_PAGES=$((PAGES_ANON - PAGES_PURGEABLE))
[ "$APP_PAGES" -lt 0 ] && APP_PAGES=0
APP_MB=$(page_mb "$APP_PAGES")

# Same formula as Activity Monitor's "Memory Used": app + wired + compressed
USED_MB=$((APP_MB + WIRED_MB + COMPRESSED_MB))
TOTAL_MEM_MB=$(( $(fc_int "$TOTAL_MEM") / 1048576 ))
[ "$TOTAL_MEM_MB" -eq 0 ] && TOTAL_MEM_MB=1
USED_PERCENT=$((USED_MB * 100 / TOTAL_MEM_MB))
[ "$USED_PERCENT" -gt 100 ] && USED_PERCENT=100

PRESSURE_LEVEL=$(sysctl -n kern.memorystatus_vm_pressure_level 2>/dev/null || echo 0)
case "$PRESSURE_LEVEL" in
    1) PRESSURE_TEXT="Normal" ;;
    2) PRESSURE_TEXT="Warning" ;;
    4) PRESSURE_TEXT="Critical" ;;
    *) PRESSURE_TEXT="Unknown" ;;
esac

echo "Total:              ${TOTAL_MEM_GB} GB"
echo ""
echo "📊 Distribution:"
echo "  App:              ${APP_MB} MB"
echo "  Wired:            ${WIRED_MB} MB"
echo "  Active:           ${ACTIVE_MB} MB"
echo "  Inactive:         ${INACTIVE_MB} MB"
echo "  Compressed:       ${COMPRESSED_MB} MB"
echo "  Free:             ${FREE_MB} MB"
echo ""

# macOS keeps RAM full on purpose; memory pressure is the meaningful signal.
case "$PRESSURE_LEVEL" in
    1) MEM_ICON="🟢" ;;
    2) MEM_ICON="🟡" ;;
    4) MEM_ICON="🔴" ;;
    *) MEM_ICON="⚪" ;;
esac

echo "Used:               ${USED_MB} MB (~${USED_PERCENT}%)"
echo "$MEM_ICON Memory Pressure:  $PRESSURE_TEXT"
echo ""

# ═════════════════════════════════════════════════════════════
# 5. CPU LOAD
# ═════════════════════════════════════════════════════════════

echo "⚡ CPU LOAD"
echo "$SUB_SEP"

CORES_PERF=$(sysctl -n hw.perflevel0.logicalcpu 2>/dev/null || echo "N/A")
CORES_EFF=$(sysctl -n hw.perflevel1.logicalcpu 2>/dev/null || echo "N/A")
CORES_TOTAL=$(sysctl -n hw.logicalcpu 2>/dev/null || echo 1)
CORES_TOTAL=$(fc_int "$CORES_TOTAL")
[ "$CORES_TOTAL" -eq 0 ] && CORES_TOTAL=1

echo "Total Cores:        $CORES_TOTAL"
[[ "$CORES_PERF" != "N/A" ]] && echo "  Performance:      $CORES_PERF"
[[ "$CORES_EFF" != "N/A" ]] && echo "  Efficiency:       $CORES_EFF"

LOAD_AVG=$(uptime 2>/dev/null | awk -F'load averages?: ' '{print $2}' | tr ',' ' ')
read -r LOAD_1 LOAD_5 LOAD_15 _ <<< "$LOAD_AVG"
LOAD_1=${LOAD_1:-0}
LOAD_5=${LOAD_5:-0}
LOAD_15=${LOAD_15:-0}

echo ""
echo "Load Average:"
echo "  1 minute:         $LOAD_1"
echo "  5 minutes:        $LOAD_5"
echo "  15 minutes:       $LOAD_15"
echo ""

LOAD_INT=$(echo "$LOAD_1" | awk -F'[.,]' '{print $1+0}')
LOAD_INT=$(fc_int "$LOAD_INT")
if [[ $LOAD_INT -le $((CORES_TOTAL / 2)) ]]; then
    LOAD_ICON="🟢"; LOAD_STATUS="Low"
elif [[ $LOAD_INT -le $CORES_TOTAL ]]; then
    LOAD_ICON="🟡"; LOAD_STATUS="Moderate"
else
    LOAD_ICON="🔴"; LOAD_STATUS="High"
fi

echo "$LOAD_ICON Load Status:       $LOAD_STATUS"

echo ""
echo "📊 Top 5 Processes by CPU:"
ps -Ao pid=,%cpu=,comm= -r 2>/dev/null | head -5 | while read -r pid cpu comm; do
    printf '  %-6s %6s%%  %s\n' "$pid" "$cpu" "${comm##*/}"
done
echo ""

# ═════════════════════════════════════════════════════════════
# 6. TEMPERATURE
# ═════════════════════════════════════════════════════════════

echo "🌡️  TEMPERATURE"
echo "$SUB_SEP"

if fc_has_cmd osx-cpu-temp; then
    TEMP_RAW=$(fc_run_timeout 2 osx-cpu-temp 2>/dev/null || true)
    if [[ "$TEMP_RAW" =~ ^[0-9]+([.][0-9]+)?°?C?$ ]] || [[ "$TEMP_RAW" =~ ^[0-9]+([.][0-9]+)? ]]; then
        TEMP_NUM=$(echo "$TEMP_RAW" | grep -oE '[0-9]+\.?[0-9]*' | head -1)
        if [[ "$TEMP_NUM" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
            # Reject nonsense readings (sensor errors often print hex / 0°C)
            TEMP_INT=${TEMP_NUM%%.*}
            if [ "$TEMP_INT" -ge 20 ] && [ "$TEMP_INT" -le 120 ]; then
                TEMP="${TEMP_NUM}°C"
            fi
        fi
    fi
    echo "CPU Temperature:    ${TEMP:-N/A}"
elif fc_has_cmd istats; then
    TEMP_NUM=$(fc_run_timeout 2 istats cpu temp 2>/dev/null | grep -oE '[0-9]+\.?[0-9]*' | head -1)
    if [[ "$TEMP_NUM" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
        TEMP_INT=${TEMP_NUM%%.*}
        if [ "$TEMP_INT" -ge 20 ] && [ "$TEMP_INT" -le 120 ]; then
            TEMP="${TEMP_NUM}°C"
        fi
    fi
    echo "CPU Temperature:    ${TEMP:-N/A}"
fi
if [ -z "$TEMP" ] && [ -n "$SSD_TEMP" ]; then
    TEMP="${SSD_TEMP}°C (SSD)"
    echo "SSD Temperature:    $TEMP"
fi
if [ -z "$TEMP" ] && ! fc_has_cmd osx-cpu-temp && ! fc_has_cmd istats; then
    echo "ℹ️  CPU sensors need a helper: brew install osx-cpu-temp (Intel) or smartmontools (SSD)"
fi

echo ""

# ═════════════════════════════════════════════════════════════
# 7. NETWORK
# ═════════════════════════════════════════════════════════════

echo "🌐 NETWORK"
echo "$SUB_SEP"

ACTIVE_IF=$(route get default 2>/dev/null | awk '/interface:/{print $2; exit}')
if [[ -n "$ACTIVE_IF" ]]; then
    IP_LOCAL=$(ipconfig getifaddr "$ACTIVE_IF" 2>/dev/null || echo "N/A")
    echo "Interface:          $ACTIVE_IF"
    echo "Local IP:           $IP_LOCAL"
fi

if [ "$HEALTH_EXTERNAL_IP" = true ]; then
    EXTERNAL_IP=$(fc_run_timeout 4 curl -fsS --max-time 3 https://ifconfig.me 2>/dev/null || true)
    echo "External IP:        ${EXTERNAL_IP:-N/A}"
fi
echo ""

# ═════════════════════════════════════════════════════════════
# 8. SECURITY STATUS
# ═════════════════════════════════════════════════════════════

echo "🔒 SECURITY STATUS"
echo "$SUB_SEP"

# Modern macOS: Application Firewall via socketfilterfw; fall back to defaults.
FIREWALL_STATUS=""
if [ -x /usr/libexec/ApplicationFirewall/socketfilterfw ]; then
    # "Firewall is enabled. (State = 1)" / "Firewall is blocking all ... (State = 2)"
    FIREWALL_STATUS=$(/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null \
        | sed -n 's/.*State = \([0-9]\).*/\1/p')
    if [ -z "$FIREWALL_STATUS" ]; then
        FW_OUT=$(/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null || true)
        case "$FW_OUT" in
            *disabled*) FIREWALL_STATUS=0 ;;
            *enabled*) FIREWALL_STATUS=1 ;;
        esac
    fi
fi
if [ -z "$FIREWALL_STATUS" ]; then
    FIREWALL_STATUS=$(defaults read /Library/Preferences/com.apple.alf globalstate 2>/dev/null || echo "")
fi

case "$FIREWALL_STATUS" in
    0)
        FIREWALL_ICON="🔴"; FIREWALL_TEXT="Disabled"
        ;;
    1)
        FIREWALL_ICON="🟢"; FIREWALL_TEXT="Enabled"
        ;;
    2)
        FIREWALL_ICON="🟢"; FIREWALL_TEXT="Enabled (block all incoming)"
        ;;
    *)
        FIREWALL_ICON="⚪"; FIREWALL_TEXT="Unknown"
        ;;
esac
echo "$FIREWALL_ICON Firewall:         $FIREWALL_TEXT"

FILEVAULT_STATUS=$(fdesetup status 2>/dev/null | grep -o "On\|Off" | head -1)
FILEVAULT_STATUS=${FILEVAULT_STATUS:-Unknown}
if [ "$FILEVAULT_STATUS" = "On" ]; then
    FILEVAULT_ICON="🟢"
elif [ "$FILEVAULT_STATUS" = "Off" ]; then
    FILEVAULT_ICON="🔴"
else
    FILEVAULT_ICON="⚪"
fi
echo "$FILEVAULT_ICON FileVault:        $FILEVAULT_STATUS"

SIP_STATUS=$(csrutil status 2>/dev/null | grep -o "enabled\|disabled" | head -1)
SIP_STATUS=${SIP_STATUS:-unknown}
if [ "$SIP_STATUS" = "enabled" ]; then
    SIP_ICON="🟢"
elif [ "$SIP_STATUS" = "disabled" ]; then
    SIP_ICON="🔴"
else
    SIP_ICON="⚪"
fi
echo "$SIP_ICON System Integrity:   $SIP_STATUS"

echo ""

# ═════════════════════════════════════════════════════════════
# SUMMARY AND NOTIFICATION
# ═════════════════════════════════════════════════════════════

echo "═══════════════════════════════════════════════════════════════"
echo "✅ System health report completed at $(date "+%H:%M:%S")"
echo "═══════════════════════════════════════════════════════════════"
echo ""

if [ -z "$MESSAGE" ]; then
    SSD_MSG="N/A"
    [ -n "$PERCENT_USED" ] && SSD_MSG="${PERCENT_USED}%"
    BATTERY_MSG="N/A"
    [ -n "$MAX_CAPACITY" ] && BATTERY_MSG="${MAX_CAPACITY}%"
    MESSAGE="SSD wear: $SSD_MSG | Battery: $BATTERY_MSG | Memory: $PRESSURE_TEXT | CPU: $LOAD_STATUS"
fi

echo "Summary: $MESSAGE"
[ "${FC_NO_NOTIFY:-false}" = true ] || fc_notify "$TITLE" "$MESSAGE"
