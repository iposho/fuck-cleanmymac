#!/usr/bin/env python3
import subprocess
import sys
import re
from pathlib import Path

# Handle kill command
if len(sys.argv) > 1 and sys.argv[1] == "kill" and len(sys.argv) > 2:
    pid = sys.argv[2]
    try:
        subprocess.run(["kill", "-9", pid], check=True)
    except subprocess.CalledProcessError:
        sys.exit(1)

# Get CPU usage
try:
    # Use top to get CPU usage on macOS
    top_output = (
        subprocess.Popen(
            ["top", "-l", "1"], stdout=subprocess.PIPE, stderr=subprocess.PIPE
        )
        .communicate()[0]
        .decode("utf-8")
    )

    # Search for CPU usage line (format: "CPU usage: 12.34% user, 5.67% sys, 81.99% idle")
    cpu_match = re.search(
        r"CPU usage:\s+(\d+\.\d+)%\s+user,\s+(\d+\.\d+)%\s+sys", top_output
    )
    if cpu_match:
        user_cpu = float(cpu_match.group(1))
        sys_cpu = float(cpu_match.group(2))
        cpu_usage = user_cpu + sys_cpu
    else:
        # Alternative search (simpler format)
        cpu_match = re.search(r"CPU usage:\s+(\d+\.\d+)%", top_output)
        if cpu_match:
            cpu_usage = float(cpu_match.group(1))
        else:
            cpu_usage = 0.0
except Exception:
    cpu_usage = 0.0

# Determine color for CPU
cpu_color = "green"
if cpu_usage > 80:
    cpu_color = "red"
elif cpu_usage > 50:
    cpu_color = "orange"

# Get total RAM
sysctl = (
    subprocess.Popen(["sysctl", "-n", "hw.memsize"], stdout=subprocess.PIPE)
    .communicate()[0]
    .decode("utf-8")
)
total_mem = int(sysctl.strip()) / 1024 / 1024  # MB

# Get vm_stat
vm = (
    subprocess.Popen(["vm_stat"], stdout=subprocess.PIPE)
    .communicate()[0]
    .decode("utf-8")
)

# Parse vm_stat
vmLines = vm.split("\n")
sep = re.compile(r":\s+")
vmStats = {}

for row in vmLines[1:]:
    rowSplit = sep.split(row, 1)
    if len(rowSplit) == 2:
        rowElements = rowSplit
        vmStats[(rowElements[0])] = int(rowElements[1].strip(".")) * 4096

# Calculate used memory
wired = vmStats.get("Pages wired down", 0) / 1024 / 1024
active = vmStats.get("Pages active", 0) / 1024 / 1024
compressed = vmStats.get("Pages stored in compressor", 0) / 1024 / 1024

used_mem = wired + active + compressed

# Format in GB for readability
used_gb = used_mem / 1024
total_gb = total_mem / 1024

# Get disk information
df_output = (
    subprocess.Popen(["df", "-g", "/"], stdout=subprocess.PIPE)
    .communicate()[0]
    .decode("utf-8")
)

try:
    df_lines = df_output.split("\n")
    disk_parts = df_lines[1].split()
    free_disk_gb = int(disk_parts[3])  # Free space in GB
    total_disk_gb = int(disk_parts[1])  # Total space in GB
except Exception:
    free_disk_gb = 0
    total_disk_gb = 0

# Format free space for display
if free_disk_gb >= 1024:
    free_disk_display = f"{free_disk_gb / 1024:.1f} TB"
else:
    free_disk_display = f"{free_disk_gb} GB"

# Determine color for disk
disk_color = "white"
if free_disk_gb < 10:
    disk_color = "red"
elif free_disk_gb < 50:
    disk_color = "orange"

# Main menu bar line (separated by dot)
print(
    f"{cpu_usage:.1f}% • {used_gb:.1f} / {total_gb:.0f} GB • {free_disk_display} | size=11"
)
print("---")

# Determine script paths relative to current file
PLUGIN_DIR = Path(__file__).parent.absolute()
SCRIPTS_DIR = PLUGIN_DIR.parent

cleaner_path = SCRIPTS_DIR / "cleaner.sh"
update_path = SCRIPTS_DIR / "update.sh"
health_path = SCRIPTS_DIR / "health.sh"

print(f"🧹 Cleanup | shell={cleaner_path} terminal=true")
print(f"🚀 Update | shell={update_path} terminal=true")
print(f"🩺 Health Check | shell={health_path} terminal=true")
print(
    "📂 Disk Utility | shell=bash param1=-c param2='open -a \"Disk Utility\"' terminal=false"
)

print("---")

# Processes section

# Get list of processes with open network connections
try:
    lsof_output = (
        subprocess.Popen(["lsof", "-i"], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        .communicate()[0]
        .decode("utf-8")
    )

    processes = {}
    for line in lsof_output.split("\n")[1:]:  # Skip header
        if line.strip():
            parts = line.split()
            if len(parts) >= 2:
                proc_name = parts[0]
                pid = parts[1]
                processes[pid] = (proc_name, pid)

    if processes:
        print(f"⚔️  Processes ({len(processes)})")
        for proc_name, pid in sorted(processes.values()):
            script_path = sys.argv[0]
            print(
                f"  {proc_name}:{pid} | font=AndaleMono bash={script_path} param1=kill param2={pid} terminal=false refresh=true"
            )
    else:
        print("⚔️  Processes: none active")

except Exception:
    print("Error retrieving process list | color=red size=10")

print("---")

# Logs section
LOG_DIR = Path.home() / ".scripts" / "logs"

def get_last_cleaner_log():
    if not LOG_DIR.exists():
        return None, None
    logs = sorted(LOG_DIR.glob("cleaner_*.log"), reverse=True)
    if not logs:
        # Fallback to cleaner.log
        fallback = LOG_DIR / "cleaner.log"
        if fallback.exists():
            return fallback, fallback.stat().st_mtime
        return None, None
    return logs[0], logs[0].stat().st_mtime

def get_update_log():
    log = LOG_DIR / "update.log"
    if log.exists():
        return log, log.stat().st_mtime
    return None, None

def format_log_time(mtime):
    import datetime
    dt = datetime.datetime.fromtimestamp(mtime)
    now = datetime.datetime.now()
    delta = now - dt
    if delta.days == 0:
        return dt.strftime("сегодня %H:%M")
    elif delta.days == 1:
        return "вчера"
    else:
        return dt.strftime("%d.%m.%Y")

def extract_log_summary(log_path, max_lines=6):
    """Extract summary block (ИТОГО section) from a log file."""
    try:
        text = log_path.read_text(errors="replace")
        lines = [l.rstrip() for l in text.splitlines() if l.strip()]
        # Find the ИТОГО block (summary at end of log)
        summary_start = -1
        for i, line in enumerate(lines):
            if "ИТОГО" in line:
                summary_start = i
        if summary_start >= 0:
            return lines[summary_start : summary_start + max_lines]
        # Fallback: last lines
        return lines[-max_lines:]
    except Exception:
        return []

cleaner_log, cleaner_mtime = get_last_cleaner_log()
update_log, update_mtime = get_update_log()

if cleaner_log:
    time_str = format_log_time(cleaner_mtime)
    print(f"📋 Лог очистки ({time_str})")
    for line in extract_log_summary(cleaner_log):
        # Strip emoji for cleaner display in menu
        print(f"  {line} | font=AndaleMono size=10 color=white")
    print(f"  ─── открыть файл | shell=open param1={cleaner_log} terminal=false")
else:
    print("📋 Лог очистки: нет данных | color=gray")

if update_log:
    time_str = format_log_time(update_mtime)
    print(f"🔄 Лог обновлений ({time_str})")
    for line in extract_log_summary(update_log):
        print(f"  {line} | font=AndaleMono size=10 color=white")
    print(f"  ─── открыть файл | shell=open param1={update_log} terminal=false")
else:
    print("🔄 Лог обновлений: нет данных | color=gray")
