#!/bin/bash

# Настройка путей для cron
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$PATH"

# Тайминги и разделители
START_DATE=$(date "+%Y-%m-%d %H:%M:%S")
START_SEC=$(date +%s)
LOG_SEP="------------------------------------------"

echo "=== ОТЧЕТ ОБ ОБНОВЛЕНИИ [$START_DATE] ==="
echo "$LOG_SEP"

# 1. Homebrew
BREW_UPDATED=0
if command -v brew &> /dev/null; then
    echo "🍺 Анализ Homebrew..."
    brew update > /dev/null
    OUTDATED_BREW=$(brew outdated -q)
    BREW_COUNT=$(echo "$OUTDATED_BREW" | grep -v '^$' | wc -l | xargs)

    if [ "$BREW_COUNT" -gt 0 ]; then
        echo "Найдено обновлений: $BREW_COUNT"
        echo "Список: $(echo "$OUTDATED_BREW" | tr '\n' ' ')"
        brew upgrade && brew cleanup -s > /dev/null
        BREW_UPDATED=$BREW_COUNT
    else
        echo "Все пакеты Brew в актуальном состоянии."
    fi
else
    echo "⚠️ Homebrew не найден."
fi

echo "$LOG_SEP"

# 2. Mac App Store (mas)
MAS_UPDATED=0
if command -v mas &> /dev/null; then
    echo "🍎 Анализ App Store..."
    OUTDATED_MAS=$(mas outdated 2>/dev/null)
    # Исключаем служебные строки вроде "Everything is up to date" (оставляем только строки с id приложения)
    MAS_COUNT=$(echo "$OUTDATED_MAS" | grep -v '^$' | grep -E '^[[:space:]]*[0-9]+' | wc -l | xargs)

    if [ "$MAS_COUNT" -gt 0 ]; then
        echo "Найдено обновлений в App Store: $MAS_COUNT"
        mas upgrade
        MAS_UPDATED=$MAS_COUNT
    else
        echo "Приложения App Store не требуют обновления."
    fi
else
    echo "⚠️ Утилита mas не установлена."
fi

echo "$LOG_SEP"

# 3. Менеджеры пакетов (pnpm/npm)
echo "📦 Обновление глобальных инструментов разработки..."
PNPM_STATUS="Пропущено"
NPM_STATUS="Пропущено"

# Подключаем nvm, чтобы pnpm/npm использовали тот же Node (избегаем ??= на старом Node)
if [ -s "$HOME/.nvm/nvm.sh" ]; then
    export NVM_DIR="$HOME/.nvm"
    # shellcheck source=/dev/null
    . "$HOME/.nvm/nvm.sh"
fi

if command -v pnpm &> /dev/null; then
    pnpm update -g > /dev/null 2>&1 && PNPM_STATUS="Обновлено" || PNPM_STATUS="Ошибка"
fi

if command -v npm &> /dev/null; then
    NODE_VER=$(node -v 2>/dev/null | sed 's/^v//' | cut -d. -f1)
    if [ -z "$NODE_VER" ]; then
        NPM_STATUS="Ошибка (node -v не найден)"
    elif [ "$NODE_VER" -ge 20 ]; then
        npm install -g npm@latest > /dev/null 2>&1 && NPM_STATUS="Обновлено (до $(npm -v))" || NPM_STATUS="Ошибка"
    elif [ "$NODE_VER" -ge 18 ]; then
        npm install -g npm@10 > /dev/null 2>&1 && NPM_STATUS="Обновлено (до $(npm -v), Node $NODE_VER)" || NPM_STATUS="Ошибка"
    elif [ "$NODE_VER" -ge 14 ]; then
        npm install -g npm@9 > /dev/null 2>&1 && NPM_STATUS="Обновлено (до $(npm -v), Node $NODE_VER)" || NPM_STATUS="Ошибка"
    else
        npm install -g npm@8 > /dev/null 2>&1 && NPM_STATUS="Обновлено (до $(npm -v), Node $NODE_VER)" || NPM_STATUS="Ошибка"
    fi
fi
echo "pnpm: $PNPM_STATUS"
echo "npm: $NPM_STATUS"

echo "$LOG_SEP"

# 4. Системные обновления macOS
echo "🖥 Проверка обновлений macOS..."
SYS_UPDATES=$(softwareupdate -l 2>&1 | grep -i "software update found")
if [ -z "$SYS_UPDATES" ]; then
    SYS_STATUS="Система актуальна"
else
    SYS_STATUS="‼️ ЕСТЬ СИСТЕМНЫЕ ОБНОВЛЕНИЯ"
fi
echo "$SYS_STATUS"

# Считаем итоги
END_SEC=$(date +%s)
RUNTIME=$((END_SEC - START_SEC))

echo "$LOG_SEP"
echo "📊 ИТОГО:"
echo "✅ Brew пакетов обновлено: $BREW_UPDATED"
echo "✅ App Store обновлено: $MAS_UPDATED"
echo "✅ Время работы: $RUNTIME сек."
echo "=== ЗАВЕРШЕНО [$(date "+%H:%M:%S")] ==="

# Уведомление (экранируем кавычки и бэкслэши для AppleScript)
NOTIFICATION="Brew: $BREW_UPDATED, App Store: $MAS_UPDATED. Время: $RUNTIME сек."
NOTIFICATION_ESC=$(printf '%s' "$NOTIFICATION" | sed 's/\\/\\\\/g; s/"/\\"/g')
SYS_STATUS_ESC=$(printf '%s' "$SYS_STATUS" | sed 's/\\/\\\\/g; s/"/\\"/g')
osascript -e "display notification \"$NOTIFICATION_ESC\" with title \"Update.sh\" subtitle \"$SYS_STATUS_ESC\""
