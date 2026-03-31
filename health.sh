#!/bin/bash
set -uo pipefail

# Configure PATH for cron jobs
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$PATH"

# Initialization
START_DATE=$(date "+%Y-%m-%d %H:%M:%S")
SUB_SEP="═══════════════════════════════════════════════════════════"

# Initialize optional metrics to prevent nounset errors
PERCENT_USED=""
DATA_WRITTEN=""
DATA_READ=""
MAX_CAPACITY=""
MESSAGE=""
TITLE="System Health Report"

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║       fuck cleanmymac: SYSTEM STATUS REPORT                  ║"
echo "║       $START_DATE                                   ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# ═════════════════════════════════════════════════════════════
# 1. SYSTEM INFORMATION
# ═════════════════════════════════════════════════════════════

echo "🖥️  SYSTEM INFORMATION"
echo "$SUB_SEP"

# Mac Model
MODEL=$(sysctl -n hw.model 2>/dev/null)
MARKETING_NAME=$(system_profiler SPHardwareDataType 2>/dev/null | grep "Model Name" | awk -F': ' '{print $2}')
echo "Hardware:       $MODEL ($MARKETING_NAME)"

# CPU
CPU_COUNT=$(sysctl -n hw.ncpu 2>/dev/null)
CPU_MODEL=$(sysctl -n machdep.cpu.brand_string 2>/dev/null)
echo "CPU:            $CPU_COUNT cores - $CPU_MODEL"

# Memory
MEMORY=$(sysctl -n hw.memsize 2>/dev/null)
MEMORY_GB=$((MEMORY / 1073741824))
echo "Memory:         ${MEMORY_GB} GB"

# macOS Version
OS_VERSION=$(sw_vers -productVersion)
OS_BUILD=$(sw_vers -buildVersion)
OS_NAME=$(sw_vers -productName)
echo "System:         $OS_NAME $OS_VERSION ($OS_BUILD)"

# Uptime details
BOOT_TIME=$(sysctl -n kern.boottime 2>/dev/null | awk -F'sec = ' '{print $2}' | awk -F',' '{print $1}')
CURRENT_TIME=$(date +%s)
UPTIME_SECONDS=$((CURRENT_TIME - BOOT_TIME))
UPTIME_DAYS=$((UPTIME_SECONDS / 86400))
UPTIME_HOURS=$(((UPTIME_SECONDS % 86400) / 3600))
UPTIME_MINS=$(((UPTIME_SECONDS % 3600) / 60))
echo "Uptime:         ${UPTIME_DAYS}d ${UPTIME_HOURS}h ${UPTIME_MINS}m"

echo ""

# ═════════════════════════════════════════════════════════════
# 2. STORAGE INFORMATION
# ═════════════════════════════════════════════════════════════

echo "💾 STORAGE INFORMATION"
echo "$SUB_SEP"

# SSD/HDD Info via smartctl (if available)
if command -v smartctl &> /dev/null; then
    DISK_INFO=$(smartctl -i /dev/disk0 2>/dev/null)
    if echo "$DISK_INFO" | grep -q "SMART support"; then
        SMART_STATUS=$(echo "$DISK_INFO" | grep "SMART overall" | head -1 | awk -F': ' '{print $2}')
        PERCENT_USED=$(echo "$DISK_INFO" | grep -i "Percentage Used" | awk '{print $NF}' | tr -d '%')
        DATA_WRITTEN=$(echo "$DISK_INFO" | grep -i "Data Units Written" | awk '{print $(NF-1) " " $NF}')
        DATA_READ=$(echo "$DISK_INFO" | grep -i "Data Units Read" | awk '{print $(NF-1) " " $NF}')

        echo "SMART Status:   $SMART_STATUS"
        echo "Data Written:   ${DATA_WRITTEN:-N/A}"
        echo "Data Read:      ${DATA_READ:-N/A}"
        [ -n "$PERCENT_USED" ] && echo "Wear Level:     ${PERCENT_USED}%"
    fi
fi

# Disk usage
echo ""
echo "Disk Space Usage:"
df -H / | awk 'NR==2 {printf "  Total: %s | Used: %s (%s) | Available: %s\n", $2, $3, $5, $4}'
echo ""

# ═════════════════════════════════════════════════════════════
# 3. BATTERY INFORMATION (if available)
# ═════════════════════════════════════════════════════════════

echo "🔋 BATTERY INFORMATION"
echo "$SUB_SEP"

BATT_INFO=$(pmset -g batt 2>/dev/null)

if echo "$BATT_INFO" | grep -q "Battery Information"; then
    CYCLES=$(echo "$BATT_INFO" | grep "Cycle Count" | awk '{print $3}')
    MAX_CAPACITY=$(echo "$BATT_INFO" | grep "Maximum Capacity" | awk '{print $3}' | tr -cd '0-9')
    CHARGE=$(echo "$BATT_INFO" | grep "State of Charge" | awk '{print $4}')
    CHARGING=$(echo "$BATT_INFO" | grep "Charging" | head -1 | awk '{print $2}')
    FULLY_CHARGED=$(echo "$BATT_INFO" | grep "Fully Charged" | awk '{print $3}')
    CONDITION=$(echo "$BATT_INFO" | grep "Condition" | awk '{print $2}')

    # Get charging information
    POWER_SOURCE=$(pmset -g batt | head -1 | grep -o "'.*'" | tr -d "'")
    TIME_REMAINING=$(pmset -g batt | grep -o '[0-9]*:[0-9]*' | head -1)

    echo "Power Source:   $POWER_SOURCE"
    [ -n "$CHARGE" ] && echo "Current Charge: $CHARGE"
    [ -n "$TIME_REMAINING" ] && echo "Time Remaining: $TIME_REMAINING"
    echo ""

    # Assess battery health
    if [[ $MAX_CAPACITY -ge 90 ]]; then
        BAT_ICON="🟢"
        BAT_STATUS="Excellent"
    elif [[ $MAX_CAPACITY -ge 80 ]]; then
        BAT_ICON="🟢"
        BAT_STATUS="Good"
    elif [[ $MAX_CAPACITY -ge 70 ]]; then
        BAT_ICON="🟡"
        BAT_STATUS="Fair"
    else
        BAT_ICON="🔴"
        BAT_STATUS="Replace Soon"
    fi

    echo "$BAT_ICON Assessment:         $BAT_STATUS"

    # Cycle forecast (Apple specifies ~1000 cycles for modern Macs)
    CYCLES_REMAINING=$((1000 - CYCLES))
    if [[ $CYCLES_REMAINING -gt 0 ]]; then
        ESTIMATED_YEARS=$((CYCLES_REMAINING / 300))
        echo "   Cycles Used:         $CYCLES / 1000"
        echo "   Estimated Remaining: ~${ESTIMATED_YEARS} years"
    else
        echo "   Cycles Used:         $CYCLES (Battery may need replacement)"
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

# Total memory
TOTAL_MEM=$(sysctl -n hw.memsize)
TOTAL_MEM_GB=$((TOTAL_MEM / 1073741824))

# Memory statistics via vm_stat
VM_STAT=$(vm_stat)
PAGE_SIZE=$(vm_stat 2>/dev/null | head -1 | grep -o '[0-9]*' | tail -1)

# Extract memory pages (values in thousands)
PAGES_WIRED=$(echo "$VM_STAT" | grep "Pages wired down" | awk '{print $4}' | tr -d '.')
PAGES_ACTIVE=$(echo "$VM_STAT" | grep "Pages active" | awk '{print $3}' | tr -d '.')
PAGES_INACTIVE=$(echo "$VM_STAT" | grep "Pages inactive" | awk '{print $3}' | tr -d '.')
PAGES_FREE=$(echo "$VM_STAT" | grep "Pages free" | awk '{print $3}' | tr -d '.')

# Convert to MB (pages * 4096 bytes / 1024 / 1024)
WIRED_MB=$((PAGES_WIRED * 4096 / 1048576))
ACTIVE_MB=$((PAGES_ACTIVE * 4096 / 1048576))
INACTIVE_MB=$((PAGES_INACTIVE * 4096 / 1048576))
FREE_MB=$((PAGES_FREE * 4096 / 1048576))

USED_MB=$((WIRED_MB + ACTIVE_MB))
USED_PERCENT=$((USED_MB * 100 / (TOTAL_MEM_GB * 1024)))

echo "Total:              ${TOTAL_MEM_GB} GB"
echo ""
echo "📊 Distribution:"
echo "  Wired:            ${WIRED_MB} MB"
echo "  Active:           ${ACTIVE_MB} MB"
echo "  Inactive:         ${INACTIVE_MB} MB"
echo "  Free:             ${FREE_MB} MB"
echo ""

# Memory health assessment
if [[ $USED_PERCENT -le 50 ]]; then
    MEM_ICON="🟢"
    MEM_STATUS="Healthy"
elif [[ $USED_PERCENT -le 80 ]]; then
    MEM_ICON="🟡"
    MEM_STATUS="Moderate"
else
    MEM_ICON="🔴"
    MEM_STATUS="High"
fi

echo "$MEM_ICON Used:               ${USED_MB} MB (~${USED_PERCENT}%)"
echo ""

# ═════════════════════════════════════════════════════════════
# 5. CPU LOAD
# ═════════════════════════════════════════════════════════════

echo "⚡ CPU LOAD"
echo "$SUB_SEP"

# Core count
CORES_PERF=$(sysctl -n hw.perflevel0.logicalcpu 2>/dev/null || echo "N/A")
CORES_EFF=$(sysctl -n hw.perflevel1.logicalcpu 2>/dev/null || echo "N/A")
CORES_TOTAL=$(sysctl -n hw.logicalcpu)

echo "Total Cores:        $CORES_TOTAL"
[[ "$CORES_PERF" != "N/A" ]] && echo "  Performance:      $CORES_PERF"
[[ "$CORES_EFF" != "N/A" ]] && echo "  Efficiency:       $CORES_EFF"

# Load average
read LOAD_1 LOAD_5 LOAD_15 < <(uptime | grep -oE 'load average[s]?: [0-9.,]+, [0-9.,]+, [0-9.,]+' | awk -F': ' '{print $2}' | tr ',' ' ')

echo ""
echo "Load Average:"
echo "  1 minute:         $LOAD_1"
echo "  5 minutes:        $LOAD_5"
echo "  15 minutes:       $LOAD_15"
echo ""

# Load assessment (take integer part)
LOAD_INT=$(echo "$LOAD_1" | awk -F'[.,]' '{print $1}')
if [[ $LOAD_INT -le $((CORES_TOTAL / 2)) ]]; then
    LOAD_ICON="🟢"
    LOAD_STATUS="Low"
elif [[ $LOAD_INT -le $CORES_TOTAL ]]; then
    LOAD_ICON="🟡"
    LOAD_STATUS="Moderate"
else
    LOAD_ICON="🔴"
    LOAD_STATUS="High"
fi

echo "$LOAD_ICON Load Status:       $LOAD_STATUS"

# Top 5 processes by CPU
echo ""
echo "📊 Top 5 Processes by CPU:"
ps aux | sort -nrk 3,3 | head -6 | tail -5 | awk '{printf "  %-6s %5.1f%%  %s\n", $2, $3, $11}'
echo ""

# ═════════════════════════════════════════════════════════════
# 6. TEMPERATURE (if available)
# ═════════════════════════════════════════════════════════════

echo "🌡️  TEMPERATURE"
echo "$SUB_SEP"

if command -v osx-cpu-temp &> /dev/null; then
    TEMP=$(osx-cpu-temp 2>/dev/null)
    echo "CPU Temperature:    $TEMP"
elif command -v istats &> /dev/null; then
    istats cpu temp 2>/dev/null
else
    echo "ℹ️  To monitor temperature install:"
    echo "   brew install osx-cpu-temp"
fi

echo ""

# ═════════════════════════════════════════════════════════════
# 7. NETWORK
# ═════════════════════════════════════════════════════════════

echo "🌐 NETWORK"
echo "$SUB_SEP"

# Active interface
ACTIVE_IF=$(route get default 2>/dev/null | grep interface | awk '{print $2}')
if [[ -n "$ACTIVE_IF" ]]; then
    IP_LOCAL=$(ipconfig getifaddr $ACTIVE_IF 2>/dev/null)
    echo "Interface:          $ACTIVE_IF"
    echo "Local IP:           $IP_LOCAL"
fi

# External IP (fast request with timeout)
EXTERNAL_IP=$(curl -s --max-time 3 ifconfig.me 2>/dev/null || echo "N/A")
echo "External IP:        $EXTERNAL_IP"
echo ""

# ═════════════════════════════════════════════════════════════
# 8. SECURITY STATUS
# ═════════════════════════════════════════════════════════════

echo "🔒 SECURITY STATUS"
echo "$SUB_SEP"

# Firewall status
FIREWALL_STATUS=$(defaults read /Library/Preferences/com.apple.alf globalstate 2>/dev/null)
case "$FIREWALL_STATUS" in
    0)
        FIREWALL_ICON="🔴"
        FIREWALL_TEXT="Disabled"
        ;;
    1)
        FIREWALL_ICON="🟢"
        FIREWALL_TEXT="Enabled (specific apps)"
        ;;
    2)
        FIREWALL_ICON="🟢"
        FIREWALL_TEXT="Enabled (all apps blocked)"
        ;;
    *)
        FIREWALL_ICON="⚪"
        FIREWALL_TEXT="Unknown"
        ;;
esac
echo "$FIREWALL_ICON Firewall:         $FIREWALL_TEXT"

# FileVault status
FILEVAULT_STATUS=$(fdesetup status 2>/dev/null | grep -o "On\|Off")
if [ "$FILEVAULT_STATUS" = "On" ]; then
    FILEVAULT_ICON="🟢"
else
    FILEVAULT_ICON="🔴"
fi
echo "$FILEVAULT_ICON FileVault:        $FILEVAULT_STATUS"

# System Integrity Protection (SIP)
SIP_STATUS=$(csrutil status | grep -o "enabled\|disabled")
if [ "$SIP_STATUS" = "enabled" ]; then
    SIP_ICON="🟢"
else
    SIP_ICON="🔴"
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

# Prepare notification message
if [ -z "$MESSAGE" ]; then
    MESSAGE="SSD: ${PERCENT_USED:-N/A}% | Battery: ${MAX_CAPACITY:-N/A}% | RAM: ${USED_PERCENT}% | CPU: $LOAD_STATUS"
fi

# Show notification if osascript is available
if command -v osascript &> /dev/null; then
    # Escape special characters for AppleScript
    MESSAGE=$(printf '%s\n' "$MESSAGE" | sed 's/"/\\"/g; s/\\/\\\\/g')
    TITLE=$(printf '%s\n' "$TITLE" | sed 's/"/\\"/g; s/\\/\\\\/g')

    osascript -e "display notification \"$MESSAGE\" with title \"$TITLE\"" 2>/dev/null || true
fi
