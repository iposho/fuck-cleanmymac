#!/bin/bash

# Пути для cron
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$PATH"

START_DATE=$(date "+%Y-%m-%d %H:%M:%S")
LOG_SEP="════════════════════════════════════════════════════════════"
SUB_SEP="────────────────────────────────────────"

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║       fuck cleanmymac: ОТЧЕТ О СОСТОЯНИИ СИСТЕМЫ             ║"
echo "║       $START_DATE                                   ║"
echo "╚══════════════════════════════════════════════════════════════╝"
[... skipping many lines ...]
osascript -e "display notification \"$MESSAGE\" with title \"fuck cleanmymac: Health Check\" subtitle \"Завершено в $END_DATE\"" 2>/dev/null
echo ""

# ═══════════════════════════════════════════════════════════
# 1. ИНФОРМАЦИЯ О СИСТЕМЕ
# ═══════════════════════════════════════════════════════════
echo "🖥️  ИНФОРМАЦИЯ О СИСТЕМЕ"
echo $SUB_SEP

# Модель Mac
MODEL=$(sysctl -n hw.model 2>/dev/null)
MARKETING_NAME=$(system_profiler SPHardwareDataType | grep "Model Name" | awk -F': ' '{print $2}')
CHIP=$(system_profiler SPHardwareDataType | grep "Chip" | awk -F': ' '{print $2}')
SERIAL=$(system_profiler SPHardwareDataType | grep "Serial Number" | awk -F': ' '{print $2}')
MEMORY=$(system_profiler SPHardwareDataType | grep "Memory" | awk -F': ' '{print $2}')

echo "Модель:        $MARKETING_NAME ($MODEL)"
echo "Процессор:     $CHIP"
echo "Серийный №:    $SERIAL"
echo "Память:        $MEMORY"

# Версия macOS
OS_VERSION=$(sw_vers -productVersion)
OS_BUILD=$(sw_vers -buildVersion)
OS_NAME=$(sw_vers -productName)
echo "Система:       $OS_NAME $OS_VERSION ($OS_BUILD)"

# Uptime подробно
BOOT_TIME=$(sysctl -n kern.boottime | awk -F'sec = ' '{print $2}' | awk -F',' '{print $1}')
CURRENT_TIME=$(date +%s)
UPTIME_SEC=$((CURRENT_TIME - BOOT_TIME))
UPTIME_DAYS=$((UPTIME_SEC / 86400))
UPTIME_HOURS=$(( (UPTIME_SEC % 86400) / 3600 ))
UPTIME_MINS=$(( (UPTIME_SEC % 3600) / 60 ))
echo "Аптайм:        ${UPTIME_DAYS}д ${UPTIME_HOURS}ч ${UPTIME_MINS}м"
echo ""

# ═══════════════════════════════════════════════════════════
# 2. СОСТОЯНИЕ ДИСКА (SSD)
# ═══════════════════════════════════════════════════════════
echo "💾 СОСТОЯНИЕ ДИСКА (SSD)"
echo $SUB_SEP

if command -v smartctl &> /dev/null; then
    DISK="disk0"
    SMART_DATA=$(smartctl -a /dev/$DISK 2>/dev/null)

    MODEL=$(echo "$SMART_DATA" | grep "Model Number" | awk -F: '{print $2}' | xargs)
    SERIAL_SSD=$(echo "$SMART_DATA" | grep "Serial Number" | awk -F: '{print $2}' | xargs)
    FIRMWARE=$(echo "$SMART_DATA" | grep "Firmware Version" | awk -F: '{print $2}' | xargs)
    CAPACITY=$(echo "$SMART_DATA" | grep "Total NVM Capacity" | awk -F: '{print $2}' | xargs)
    PERCENT_USED=$(echo "$SMART_DATA" | grep "Percentage Used" | awk -F: '{print $2}' | xargs | tr -d '%')
    DATA_WRITTEN=$(echo "$SMART_DATA" | grep "Data Units Written" | awk -F: '{print $2}' | xargs)
    DATA_READ=$(echo "$SMART_DATA" | grep "Data Units Read" | awk -F: '{print $2}' | xargs)
    POWER_ON=$(echo "$SMART_DATA" | grep "Power On Hours" | awk -F: '{print $2}' | xargs)
    POWER_CYCLES=$(echo "$SMART_DATA" | grep "Power Cycles" | awk -F: '{print $2}' | xargs)
    TEMPERATURE=$(echo "$SMART_DATA" | grep "Temperature:" | head -1 | awk -F: '{print $2}' | xargs)
    STATUS=$(echo "$SMART_DATA" | grep "SMART overall-health" | awk -F: '{print $2}' | xargs)

    echo "Модель:             $MODEL"
    echo "Серийный №:         $SERIAL_SSD"
    echo "Прошивка:           $FIRMWARE"
    echo "Ёмкость:            $CAPACITY"
    echo "Температура:        $TEMPERATURE"
    echo ""
    echo "📊 Статистика использования:"
    echo "  Износ:            ${PERCENT_USED}%"
    echo "  Записано данных:  $DATA_WRITTEN"
    echo "  Прочитано данных: $DATA_READ"
    echo "  Часов работы:     $POWER_ON"
    echo "  Циклов питания:   $POWER_CYCLES"
    echo ""

    # Расчет оставшегося ресурса
    REMAINING=$((100 - PERCENT_USED))
    if [[ $PERCENT_USED -le 10 ]]; then
        HEALTH_ICON="🟢"
        HEALTH_STATUS="Отличное"
    elif [[ $PERCENT_USED -le 50 ]]; then
        HEALTH_ICON="🟢"
        HEALTH_STATUS="Хорошее"
    elif [[ $PERCENT_USED -le 80 ]]; then
        HEALTH_ICON="🟡"
        HEALTH_STATUS="Удовлетворительное"
    else
        HEALTH_ICON="🔴"
        HEALTH_STATUS="Требуется замена!"
    fi

    echo "$HEALTH_ICON Здоровье SSD:     $HEALTH_STATUS (осталось ~${REMAINING}% ресурса)"
    echo "  SMART статус:     $STATUS"

    [[ $PERCENT_USED -gt 80 ]] && echo "⚠️  ВНИМАНИЕ: Высокий износ! Рекомендуется замена диска."
else
    echo "⚠️  smartmontools не установлены"
    echo "   Установка: brew install smartmontools"
fi

# Место на диске
echo ""
echo "📁 Использование дискового пространства:"
df -H / | awk 'NR==2 {printf "  Всего: %s | Использовано: %s (%s) | Свободно: %s\n", $2, $3, $5, $4}'
echo ""

# ═══════════════════════════════════════════════════════════
# 3. СОСТОЯНИЕ БАТАРЕИ
# ═══════════════════════════════════════════════════════════
echo "🔋 СОСТОЯНИЕ БАТАРЕИ"
echo $SUB_SEP

BATT_INFO=$(system_profiler SPPowerDataType 2>/dev/null)

if echo "$BATT_INFO" | grep -q "Battery Information"; then
    CYCLES=$(echo "$BATT_INFO" | grep "Cycle Count" | awk '{print $3}')
    MAX_CAPACITY=$(echo "$BATT_INFO" | grep "Maximum Capacity" | awk '{print $3}' | tr -cd '0-9')
    CHARGE=$(echo "$BATT_INFO" | grep "State of Charge" | awk '{print $4}')
    CHARGING=$(echo "$BATT_INFO" | grep "Charging" | head -1 | awk '{print $2}')
    FULLY_CHARGED=$(echo "$BATT_INFO" | grep "Fully Charged" | awk '{print $3}')
    CONDITION=$(echo "$BATT_INFO" | grep "Condition" | awk '{print $2}')

    # Получаем информацию о зарядке
    POWER_SOURCE=$(pmset -g batt | head -1 | grep -o "'.*'" | tr -d "'")
    TIME_REMAINING=$(pmset -g batt | grep -o '[0-9]*:[0-9]*' | head -1)
    PERCENT_NOW=$(pmset -g batt | grep -o '[0-9]*%' | head -1)

    echo "Текущий заряд:      $PERCENT_NOW"
    echo "Источник питания:   $POWER_SOURCE"
    [[ -n "$TIME_REMAINING" ]] && echo "Осталось времени:   $TIME_REMAINING"
    echo ""
    echo "📊 Здоровье батареи:"
    echo "  Циклов зарядки:   $CYCLES"
    echo "  Макс. ёмкость:    ${MAX_CAPACITY}%"
    echo "  Состояние:        $CONDITION"
    echo ""

    # Оценка здоровья батареи
    if [[ $MAX_CAPACITY -ge 90 ]]; then
        BAT_ICON="🟢"
        BAT_STATUS="Отличное"
    elif [[ $MAX_CAPACITY -ge 80 ]]; then
        BAT_ICON="🟢"
        BAT_STATUS="Хорошее"
    elif [[ $MAX_CAPACITY -ge 70 ]]; then
        BAT_ICON="🟡"
        BAT_STATUS="Удовлетворительное"
    else
        BAT_ICON="🔴"
        BAT_STATUS="Требуется замена"
    fi

    echo "$BAT_ICON Оценка:            $BAT_STATUS"

    # Прогноз по циклам (Apple указывает ~1000 циклов для современных Mac)
    CYCLES_REMAINING=$((1000 - CYCLES))
    if [[ $CYCLES_REMAINING -gt 0 ]]; then
        echo "  Осталось циклов:  ~$CYCLES_REMAINING (из 1000)"
    else
        echo "  ⚠️ Превышен лимит циклов!"
    fi

    [[ $MAX_CAPACITY -lt 80 ]] && echo "⚠️  ВНИМАНИЕ: Ёмкость ниже 80%. Рекомендуется замена батареи."
else
    echo "ℹ️  Батарея не обнаружена (десктоп Mac)"
fi
echo ""

# ═══════════════════════════════════════════════════════════
# 4. ПАМЯТЬ (RAM)
# ═══════════════════════════════════════════════════════════
echo "🧠 ПАМЯТЬ (RAM)"
echo $SUB_SEP

# Общий объем памяти
TOTAL_MEM=$(sysctl -n hw.memsize)
TOTAL_MEM_GB=$((TOTAL_MEM / 1073741824))

# Статистика памяти через vm_stat
VM_STAT=$(vm_stat)
PAGE_SIZE=$(vm_stat | head -1 | grep -o '[0-9]*')

PAGES_FREE=$(echo "$VM_STAT" | grep "Pages free" | awk '{print $3}' | tr -d '.')
PAGES_ACTIVE=$(echo "$VM_STAT" | grep "Pages active" | awk '{print $3}' | tr -d '.')
PAGES_INACTIVE=$(echo "$VM_STAT" | grep "Pages inactive" | awk '{print $3}' | tr -d '.')
PAGES_SPECULATIVE=$(echo "$VM_STAT" | grep "Pages speculative" | awk '{print $3}' | tr -d '.')
PAGES_WIRED=$(echo "$VM_STAT" | grep "Pages wired" | awk '{print $4}' | tr -d '.')
PAGES_COMPRESSED=$(echo "$VM_STAT" | grep "Pages occupied by compressor" | awk '{print $5}' | tr -d '.')
SWAP_USED=$(sysctl -n vm.swapusage | awk '{print $6}')

FREE_MB=$(( (PAGES_FREE * PAGE_SIZE) / 1048576 ))
ACTIVE_MB=$(( (PAGES_ACTIVE * PAGE_SIZE) / 1048576 ))
INACTIVE_MB=$(( (PAGES_INACTIVE * PAGE_SIZE) / 1048576 ))
WIRED_MB=$(( (PAGES_WIRED * PAGE_SIZE) / 1048576 ))
COMPRESSED_MB=$(( (PAGES_COMPRESSED * PAGE_SIZE) / 1048576 ))

USED_MB=$((ACTIVE_MB + WIRED_MB + COMPRESSED_MB))
USED_PERCENT=$((USED_MB * 100 / (TOTAL_MEM_GB * 1024)))

echo "Всего:              ${TOTAL_MEM_GB} GB"
echo ""
echo "📊 Распределение:"
echo "  Активная:         ${ACTIVE_MB} MB"
echo "  Фиксированная:    ${WIRED_MB} MB"
echo "  Сжатая:           ${COMPRESSED_MB} MB"
echo "  Неактивная:       ${INACTIVE_MB} MB"
echo "  Свободная:        ${FREE_MB} MB"
echo "  Swap:             ${SWAP_USED}"
echo ""

if [[ $USED_PERCENT -le 70 ]]; then
    MEM_ICON="🟢"
elif [[ $USED_PERCENT -le 85 ]]; then
    MEM_ICON="🟡"
else
    MEM_ICON="🔴"
fi

echo "$MEM_ICON Использовано:      ${USED_MB} MB (~${USED_PERCENT}%)"
echo ""

# ═══════════════════════════════════════════════════════════
# 5. НАГРУЗКА CPU
# ═══════════════════════════════════════════════════════════
echo "⚡ НАГРУЗКА CPU"
echo $SUB_SEP

# Количество ядер
CORES_PERF=$(sysctl -n hw.perflevel0.logicalcpu 2>/dev/null || echo "N/A")
CORES_EFF=$(sysctl -n hw.perflevel1.logicalcpu 2>/dev/null || echo "N/A")
CORES_TOTAL=$(sysctl -n hw.logicalcpu)

echo "Ядер всего:         $CORES_TOTAL"
[[ "$CORES_PERF" != "N/A" ]] && echo "  Performance:      $CORES_PERF"
[[ "$CORES_EFF" != "N/A" ]] && echo "  Efficiency:       $CORES_EFF"
echo ""

# Load Average
LOAD=$(sysctl -n vm.loadavg | awk '{print $2, $3, $4}')
LOAD_1=$(echo $LOAD | awk '{print $1}' | tr ',' '.')
LOAD_5=$(echo $LOAD | awk '{print $2}' | tr ',' '.')
LOAD_15=$(echo $LOAD | awk '{print $3}' | tr ',' '.')

echo "Load Average:"
echo "  1 мин:            $LOAD_1"
echo "  5 мин:            $LOAD_5"
echo "  15 мин:           $LOAD_15"
echo ""

# Оценка нагрузки (берём целую часть)
LOAD_INT=$(echo "$LOAD_1" | awk -F'[.,]' '{print $1}')
if [[ $LOAD_INT -le $((CORES_TOTAL / 2)) ]]; then
    LOAD_ICON="🟢"
    LOAD_STATUS="Низкая"
elif [[ $LOAD_INT -le $CORES_TOTAL ]]; then
    LOAD_ICON="🟡"
    LOAD_STATUS="Умеренная"
else
    LOAD_ICON="🔴"
    LOAD_STATUS="Высокая"
fi

echo "$LOAD_ICON Нагрузка:          $LOAD_STATUS"

# Топ процессов по CPU
echo ""
echo "📊 Топ-5 процессов по CPU:"
ps aux | sort -nrk 3,3 | head -6 | tail -5 | awk '{printf "  %-6s %5.1f%%  %s\n", $2, $3, $11}'
echo ""

# ═══════════════════════════════════════════════════════════
# 6. ТЕМПЕРАТУРА (если доступно)
# ═══════════════════════════════════════════════════════════
echo "🌡️  ТЕМПЕРАТУРА"
echo $SUB_SEP

if command -v osx-cpu-temp &> /dev/null; then
    CPU_TEMP=$(osx-cpu-temp)
    echo "CPU:                $CPU_TEMP"
elif command -v istats &> /dev/null; then
    istats cpu temp 2>/dev/null
else
    # Пробуем через powermetrics (требует sudo)
    echo "ℹ️  Для мониторинга температуры установите:"
    echo "   brew install osx-cpu-temp"
    echo "   или: gem install iStats"
fi
echo ""

# ═══════════════════════════════════════════════════════════
# 7. СЕТЬ
# ═══════════════════════════════════════════════════════════
echo "🌐 СЕТЬ"
echo $SUB_SEP

# Активный интерфейс
ACTIVE_IF=$(route get default 2>/dev/null | grep interface | awk '{print $2}')
if [[ -n "$ACTIVE_IF" ]]; then
    IP_LOCAL=$(ipconfig getifaddr $ACTIVE_IF 2>/dev/null)
    echo "Интерфейс:          $ACTIVE_IF"
    echo "Локальный IP:       $IP_LOCAL"
fi

# Внешний IP (быстрый запрос)
EXTERNAL_IP=$(curl -s --max-time 3 ifconfig.me 2>/dev/null || echo "N/A")
echo "Внешний IP:         $EXTERNAL_IP"

# DNS
DNS_SERVERS=$(scutil --dns | grep "nameserver\[[0-9]*\]" | head -3 | awk '{print $3}' | tr '\n' ' ')
echo "DNS:                $DNS_SERVERS"
echo ""

# ═══════════════════════════════════════════════════════════
# 8. БЕЗОПАСНОСТЬ
# ═══════════════════════════════════════════════════════════
echo "🔐 БЕЗОПАСНОСТЬ"
echo $SUB_SEP

# FileVault
FV_STATUS=$(fdesetup status 2>/dev/null | head -1)
echo "FileVault:          $FV_STATUS"

# Firewall
FW_STATUS=$(defaults read /Library/Preferences/com.apple.alf globalstate 2>/dev/null)
case $FW_STATUS in
    0) FW_TEXT="Выключен" ;;
    1) FW_TEXT="Включен" ;;
    2) FW_TEXT="Включен (блокировка входящих)" ;;
    *) FW_TEXT="Неизвестно" ;;
esac
echo "Firewall:           $FW_TEXT"

# SIP
SIP_STATUS=$(csrutil status 2>/dev/null | awk -F': ' '{print $2}' | tr -d '.')
echo "SIP:                $SIP_STATUS"

# Gatekeeper
GK_STATUS=$(spctl --status 2>/dev/null)
echo "Gatekeeper:         $GK_STATUS"
echo ""

# ═══════════════════════════════════════════════════════════
# ИТОГОВАЯ СВОДКА
# ═══════════════════════════════════════════════════════════
echo $LOG_SEP
echo "📋 ИТОГОВАЯ СВОДКА"
echo $SUB_SEP

# Формируем краткий отчет
ISSUES=0
WARNINGS=""

# Проверка SSD
if [[ -n "$PERCENT_USED" && $PERCENT_USED -gt 80 ]]; then
    WARNINGS="${WARNINGS}\n  🔴 SSD износ критический: ${PERCENT_USED}%"
    ((ISSUES++))
elif [[ -n "$PERCENT_USED" && $PERCENT_USED -gt 50 ]]; then
    WARNINGS="${WARNINGS}\n  🟡 SSD износ умеренный: ${PERCENT_USED}%"
fi

# Проверка батареи
if [[ -n "$MAX_CAPACITY" && $MAX_CAPACITY -lt 80 ]]; then
    WARNINGS="${WARNINGS}\n  🔴 Батарея требует замены: ${MAX_CAPACITY}%"
    ((ISSUES++))
elif [[ -n "$MAX_CAPACITY" && $MAX_CAPACITY -lt 90 ]]; then
    WARNINGS="${WARNINGS}\n  🟡 Батарея изношена: ${MAX_CAPACITY}%"
fi

# Проверка памяти
if [[ $USED_PERCENT -gt 85 ]]; then
    WARNINGS="${WARNINGS}\n  🔴 Высокое использование RAM: ${USED_PERCENT}%"
    ((ISSUES++))
fi

# Проверка нагрузки
if [[ $LOAD_INT -gt $CORES_TOTAL ]]; then
    WARNINGS="${WARNINGS}\n  🟡 Высокая нагрузка CPU: $LOAD_1"
fi

if [[ $ISSUES -eq 0 ]]; then
    echo "✅ Система в хорошем состоянии"
else
    echo "⚠️  Обнаружены проблемы ($ISSUES):"
    echo -e "$WARNINGS"
fi

echo ""
echo "SSD:     ${PERCENT_USED:-N/A}% износа | Батарея: ${MAX_CAPACITY:-N/A}% ёмкости"
echo "RAM:     ${USED_PERCENT}% использовано | CPU Load: $LOAD_1"
echo ""

# ═══════════════════════════════════════════════════════════
# УВЕДОМЛЕНИЕ
# ═══════════════════════════════════════════════════════════
END_DATE=$(date "+%H:%M:%S")
MESSAGE="SSD: ${PERCENT_USED:-N/A}% | Батарея: ${MAX_CAPACITY:-N/A}% | RAM: ${USED_PERCENT}%"

if [[ $ISSUES -gt 0 ]]; then
    TITLE="⚠️ Health Check - Есть проблемы"
else
    TITLE="✅ Health Check - OK"
fi

osascript -e "display notification \"$MESSAGE\" with title \"fuck cleanmymac: Health Check\" subtitle \"Завершено в $END_DATE\"" 2>/dev/null

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║       ПРОВЕРКА ЗАВЕРШЕНА: $END_DATE                         ║"
echo "╚══════════════════════════════════════════════════════════════╝"
