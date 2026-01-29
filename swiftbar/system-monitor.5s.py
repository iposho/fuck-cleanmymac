#!/usr/bin/env python3
# <xbar.title>fuck cleanmymac</xbar.title>
# <xbar.version>v4.0</xbar.version>
# <xbar.desc>Shows CPU load, memory usage, disk space, and allows killing processes</xbar.desc>
# <xbar.dependencies>python</xbar.dependencies>

import re
import subprocess
import sys

# Обработка команды kill
if len(sys.argv) > 1 and sys.argv[1] == "kill" and len(sys.argv) > 2:
    pid = sys.argv[2]
    try:
        subprocess.run(["kill", "-9", pid], check=True)
        sys.exit(0)
    except subprocess.CalledProcessError:
        sys.exit(1)

# Получаем CPU usage
try:
    # Используем top для получения CPU usage на macOS
    top_output = (
        subprocess.Popen(
            ["top", "-l", "1"], stdout=subprocess.PIPE, stderr=subprocess.PIPE
        )
        .communicate()[0]
        .decode("utf-8")
    )

    # Ищем строку с CPU usage (формат: "CPU usage: 12.34% user, 5.67% sys, 81.99% idle")
    cpu_match = re.search(
        r"CPU usage:\s+(\d+\.\d+)%\s+user,\s+(\d+\.\d+)%\s+sys", top_output
    )
    if cpu_match:
        user_percent = float(cpu_match.group(1))
        sys_percent = float(cpu_match.group(2))
        cpu_usage = user_percent + sys_percent
    else:
        # Альтернативный поиск (более простой формат)
        cpu_match = re.search(r"CPU usage:\s+(\d+\.\d+)%", top_output)
        if cpu_match:
            cpu_usage = float(cpu_match.group(1))
        else:
            cpu_usage = 0.0
except:
    cpu_usage = 0.0

# Определяем цвет для CPU
cpu_color = "green"
if cpu_usage > 80:
    cpu_color = "red"
elif cpu_usage > 60:
    cpu_color = "orange"

# Получаем общий объем RAM
sysctl = (
    subprocess.Popen(["sysctl", "-n", "hw.memsize"], stdout=subprocess.PIPE)
    .communicate()[0]
    .decode("utf-8")
)
total_mem = int(sysctl.strip()) / 1024 / 1024  # MB

# Получаем vm_stat
vm = (
    subprocess.Popen(["vm_stat"], stdout=subprocess.PIPE)
    .communicate()[0]
    .decode("utf-8")
)

# Парсим vm_stat
vmLines = vm.split("\n")
sep = re.compile(r":[\s]+")
vmStats = {}
for row in range(1, len(vmLines) - 2):
    rowText = vmLines[row].strip()
    rowElements = sep.split(rowText)
    vmStats[(rowElements[0])] = int(rowElements[1].strip(".")) * 4096

# Считаем использованную память
wired = vmStats.get("Pages wired down", 0) / 1024 / 1024
active = vmStats.get("Pages active", 0) / 1024 / 1024
compressed = vmStats.get("Pages occupied by compressor", 0) / 1024 / 1024

used_mem = wired + active + compressed

# Форматируем в GB для читаемости
used_gb = used_mem / 1024
total_gb = total_mem / 1024

# Получаем информацию о диске
df_output = (
    subprocess.Popen(["df", "-g", "/"], stdout=subprocess.PIPE)
    .communicate()[0]
    .decode("utf-8")
)
df_lines = df_output.strip().split("\n")
if len(df_lines) > 1:
    disk_parts = df_lines[1].split()
    free_disk_gb = int(disk_parts[3])  # Свободное место в GB
    total_disk_gb = int(disk_parts[1])  # Всего места в GB
else:
    free_disk_gb = 0
    total_disk_gb = 0

# Форматируем свободное место для отображения
if free_disk_gb >= 1024:
    free_disk_display = f"{free_disk_gb / 1024:.1f} Тб"
else:
    free_disk_display = f"{free_disk_gb} Гб"

# Определяем цвет для диска
disk_color = "white"
if free_disk_gb < 10:
    disk_color = "red"
elif free_disk_gb < 30:
    disk_color = "orange"

# Основная строка в меню баре (разделяем точкой)
print(
    f"{cpu_usage:.1f}% • {used_gb:.1f} / {total_gb:.0f} • {free_disk_display} | size=11"
)
print("---")

# Раздел CPU
# print(f"⚡ CPU: {cpu_usage:.1f}% | color={cpu_color} size=11")
# print("---")

# # Раздел памяти
# print(f"💾 Память: {used_gb:.1f}/{total_gb:.0f} GB | size=11")
# print("---")

# # Раздел диска
# print(f"💿 Диск: {free_disk_display} / {total_disk_gb} Гб | color={disk_color} size=11")
# print("---")
import os
from pathlib import Path

# Определяем пути к скриптам относительно текущего файла
PLUGIN_DIR = Path(__file__).parent.absolute()
SCRIPTS_DIR = PLUGIN_DIR.parent

cleaner_path = SCRIPTS_DIR / "cleaner.sh"
update_path = SCRIPTS_DIR / "update.sh"
health_path = SCRIPTS_DIR / "health.sh"

print(f"🧹 Очистка | shell={cleaner_path} terminal=true")
print(f"🚀 Обновление | shell={update_path} terminal=true")
print(f"🩺 Проверка здоровья | shell={health_path} terminal=true")
print(
    "📂 Дисковая утилита | shell=bash param1=-c param2='open -a \"Disk Utility\"' terminal=false"
)
print("---")

# Раздел процессов

# Получаем список процессов с открытыми сетевыми соединениями
try:
    lsof_output = (
        subprocess.Popen(["lsof", "-i"], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        .communicate()[0]
        .decode("utf-8")
    )

    processes = {}
    for line in lsof_output.split("\n")[1:]:  # Пропускаем заголовок
        if line.strip():
            parts = line.split()
            if len(parts) >= 2:
                proc_name = parts[0]
                pid = parts[1]
                processes[f"{proc_name},{pid}"] = (proc_name, pid)

    if processes:
        print(f"⚔️ Процессы ({len(processes)})")
        for proc_name, pid in sorted(processes.values()):
            script_path = sys.argv[0]
            print(
                f"  {proc_name}:{pid} | font=AndaleMono bash={script_path} param1=kill param2={pid} terminal=false refresh=true"
            )
    else:
        print("⚔️ Процессы: нет активных")
except Exception:
    print("Ошибка получения списка процессов | color=red size=10")
