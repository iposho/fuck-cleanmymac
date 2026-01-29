#!/bin/bash

# Настройка путей для работы внутри cron
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$PATH"

# Тайминги и разделители
START_DATE=$(date "+%Y-%m-%d %H:%M:%S")
START_SEC=$(date +%s)
LOG_SEP="------------------------------------------"

# Считаем место ДО (в мегабайтах)
BEFORE=$(df -m / | awk 'NR==2 {print $4}')

echo "=== ОТЧЕТ ОБ ОЧИСТКЕ [$START_DATE] ==="
echo $LOG_SEP

# 1. Docker
echo "🐳 Проверка Docker..."
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
        echo "⚠️  Docker завис. Пропускаю."
    else
        echo "🧹 Очистка контейнеров, образов и томов..."
        docker system prune -af --volumes > /dev/null
        docker builder prune -af > /dev/null
        echo "✅ Docker очищен."
    fi
else
    echo "⏭  Docker не установлен."
fi

echo $LOG_SEP

# 2. Инструменты разработки
echo "📦 Очистка менеджеров пакетов..."
[ -d ~/.npm ] && (npm cache clean --force > /dev/null 2>&1 && echo "✅ npm cache очищен")
[ -d ~/.cache/yarn ] && (yarn cache clean > /dev/null 2>&1 && echo "✅ yarn cache очищен")
command -v brew &> /dev/null && (brew cleanup -s > /dev/null && echo "✅ Homebrew очищен")
# Python (если используешь)
[ -d ~/.cache/pip ] && rm -rf ~/.cache/pip && echo "✅ pip cache очищен"

if [ -d ~/Library/Developer/Xcode/DerivedData ]; then
    echo "🛠  Удаление Xcode Derived Data..."
    rm -rf ~/Library/Developer/Xcode/DerivedData/*
    echo "✅ Xcode очищен."
fi

echo $LOG_SEP

# 3. Приложения (Cursor, Notion, Chrome, Telegram, JetBrains)
echo "🖥  Точечная очистка приложений..."

# Cursor
[ -d ~/Library/Application\ Support/Cursor ] && rm -rf ~/Library/Application\ Support/Cursor/Cache/* && echo "✅ Cursor Cache удален"

# Notion
[ -d ~/Library/Application\ Support/Notion ] && rm -rf ~/Library/Application\ Support/Notion/Cache/* && echo "✅ Notion Cache удален"

# Chrome (раскомментируй, если нужно)
# [ -d ~/Library/Application\ Support/Google/Chrome ] && rm -rf ~/Library/Application\ Support/Google/Chrome/Default/Service\ Worker/CacheStorage/* && echo "✅ Chrome Cache удален"

# Telegram (только медиа)
if [ -d ~/Library/Group\ Containers/*.ru.keepcoder.Telegram ]; then
    rm -rf ~/Library/Group\ Containers/*.ru.keepcoder.Telegram/account-*/postbox/media/*
    echo "✅ Telegram Media очищен"
fi

# Slack (жрёт много)
[ -d ~/Library/Application\ Support/Slack ] && rm -rf ~/Library/Application\ Support/Slack/Cache/* ~/Library/Application\ Support/Slack/Service\ Worker/CacheStorage/* && echo "✅ Slack Cache очищен"

# JetBrains (WebStorm и др.)
find ~/Library/Caches/JetBrains -name "WebStorm*" -type d -exec rm -rf {}/* + 2>/dev/null && echo "✅ JetBrains Caches очищены"

echo $LOG_SEP

# 4. Система и логи
echo "🗑  Системная гигиена..."
rm -rf ~/Library/Caches/*
rm -rf ~/Library/Logs/*
rm -rf ~/.Trash/*
echo "✅ Кэши, логи и корзина очищены."

# 5. Ротация логов самого скрипта
echo "📜 Ротация логов очистки..."
LOG_DIR="$HOME/.scripts/logs"
mkdir -p "$LOG_DIR"
find "$LOG_DIR" -name "*.log" -type f -mtime +90 -delete && echo "✅ Старые логи удалены."

echo $LOG_SEP

# Итоги
AFTER=$(df -m / | awk 'NR==2 {print $4}')
DIFF=$((AFTER - BEFORE))
[ $DIFF -lt 0 ] && DIFF=0

END_SEC=$(date +%s)
RUNTIME=$((END_SEC - START_SEC))

echo "📊 ИТОГО:"
echo "✅ Освобождено: $DIFF МБ"
echo "✅ Время работы: $RUNTIME сек."
echo "=== ЗАВЕРШЕНО [$(date "+%H:%M:%S")] ==="

# Уведомление
if [ $DIFF -gt 0 ]; then
    MSG="Освобождено $DIFF МБ за $RUNTIME сек."
else
    MSG="Система уже была чиста! (Заняло $RUNTIME сек.)"
fi

osascript -e "display notification \"$MSG\" with title \"fuck cleanmymac\" subtitle \"Генеральная уборка выполнена\""
