#!/usr/bin/env python3
"""SwiftBar system monitor — CPU, RAM, disk, maintenance actions, keyboard cleaning mode, logs."""

from __future__ import annotations

import ctypes
import datetime
import os
import re
import shutil
import signal
import subprocess
import sys
import time
from pathlib import Path

HOME = Path.home()
PLUGIN_DIR = Path(__file__).resolve().parent
LOG_DIR = HOME / ".scripts" / "logs"
PID_FILE = HOME / ".config" / "fuck-cleanmymac" / "keyboard-lock.pid"
CACHE_DIR = HOME / ".cache" / "fuck-cleanmymac"
PROCESS_CACHE = CACHE_DIR / "swiftbar-processes.cache"
CPU_TICKS_CACHE = CACHE_DIR / "swiftbar-cpu.ticks"
TEMP_UNAVAILABLE_FLAG = CACHE_DIR / "swiftbar-no-temp"
AX_CACHE = CACHE_DIR / "swiftbar-ax.cache"
CLEANUP_PLAN = CACHE_DIR / "cleanup-plan.tsv"
PROCESS_CACHE_TTL = 15  # seconds
TEMP_RETRY_TTL = 600  # re-probe a sensor that returned nothing useful every 10 min
AX_CACHE_TTL = 30
ACCESSIBILITY_URL = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
LOCK_DURATIONS = ((60, "Lock for 1 minute"), (300, "Lock for 5 minutes"), (0, "Lock until I unlock it"))

GB = 1024**3
_libc = ctypes.CDLL(None)


def run(cmd: list[str], timeout: float = 2.0) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, check=False)


def cache_fresh(path: Path, ttl: float) -> bool:
    try:
        return time.time() - path.stat().st_mtime < ttl
    except OSError:
        return False


def write_cache(path: Path, text: str) -> None:
    try:
        CACHE_DIR.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
    except OSError:
        pass


def quote(value: object) -> str:
    """Quote a SwiftBar parameter value (paths contain spaces: 'Application Support')."""
    return '"' + str(value).replace('"', '\\"') + '"'


def escape_title(value: str) -> str:
    return value.replace("|", "│").replace("\n", " ")


# --- metrics -------------------------------------------------------------------


def _host_statistics(flavor: int, buf: ctypes.Array | ctypes.Structure, count: int, is64: bool) -> bool:
    fn = _libc.host_statistics64 if is64 else _libc.host_statistics
    fn.argtypes = [ctypes.c_uint32, ctypes.c_int, ctypes.c_void_p, ctypes.POINTER(ctypes.c_uint32)]
    fn.restype = ctypes.c_int
    _libc.mach_host_self.restype = ctypes.c_uint32
    n = ctypes.c_uint32(count)
    return fn(_libc.mach_host_self(), flavor, ctypes.byref(buf), ctypes.byref(n)) == 0


def get_cpu_usage() -> float:
    """Exact CPU load since the previous refresh, from host CPU ticks (no subprocess)."""
    ticks = (ctypes.c_uint32 * 4)()  # user, system, idle, nice
    if _host_statistics(3, ticks, 4, is64=False):  # HOST_CPU_LOAD_INFO
        current = list(ticks)
        previous = None
        try:
            previous = [int(x) for x in CPU_TICKS_CACHE.read_text(encoding="utf-8").split()]
        except (OSError, ValueError):
            pass
        write_cache(CPU_TICKS_CACHE, " ".join(map(str, current)))
        if previous and len(previous) == 4:
            delta = [c - p for c, p in zip(current, previous)]
            total = sum(delta)
            if total > 0 and min(delta) >= 0:
                return 100.0 * (total - delta[2]) / total

    # First run (or counters wrapped): average of per-process %CPU
    try:
        out = run(["ps", "-A", "-o", "%cpu="]).stdout
        total = sum(float(x.replace(",", ".")) for x in out.split() if x)
        return min(100.0, total / max(os.cpu_count() or 1, 1))
    except Exception:
        return 0.0


class VMStatistics64(ctypes.Structure):
    _fields_ = [
        ("free_count", ctypes.c_uint32),
        ("active_count", ctypes.c_uint32),
        ("inactive_count", ctypes.c_uint32),
        ("wire_count", ctypes.c_uint32),
        ("zero_fill_count", ctypes.c_uint64),
        ("reactivations", ctypes.c_uint64),
        ("pageins", ctypes.c_uint64),
        ("pageouts", ctypes.c_uint64),
        ("faults", ctypes.c_uint64),
        ("cow_faults", ctypes.c_uint64),
        ("lookups", ctypes.c_uint64),
        ("hits", ctypes.c_uint64),
        ("purges", ctypes.c_uint64),
        ("purgeable_count", ctypes.c_uint32),
        ("speculative_count", ctypes.c_uint32),
        ("decompressions", ctypes.c_uint64),
        ("compressions", ctypes.c_uint64),
        ("swapins", ctypes.c_uint64),
        ("swapouts", ctypes.c_uint64),
        ("compressor_page_count", ctypes.c_uint32),
        ("throttled_count", ctypes.c_uint32),
        ("external_page_count", ctypes.c_uint32),
        ("internal_page_count", ctypes.c_uint32),
        ("total_uncompressed_pages_in_compressor", ctypes.c_uint64),
    ]


def get_memory() -> tuple[float, float]:
    """(used_gb, total_gb); "used" matches Activity Monitor: app + wired + compressed."""
    try:
        page = os.sysconf("SC_PAGE_SIZE")
        total = os.sysconf("SC_PHYS_PAGES") * page
    except (ValueError, OSError):
        return 0.0, 0.0

    vm = VMStatistics64()
    if _host_statistics(4, vm, ctypes.sizeof(vm) // 4, is64=True):  # HOST_VM_INFO64
        app = max(vm.internal_page_count - vm.purgeable_count, 0)
        used = (app + vm.wire_count + vm.compressor_page_count) * page
        return used / GB, total / GB

    try:
        stats = {}
        for row in run(["vm_stat"]).stdout.splitlines()[1:]:
            key, _, value = row.partition(":")
            if value.strip().rstrip(".").isdigit():
                stats[key.strip()] = int(value.strip().rstrip("."))
        used = (
            stats.get("Anonymous pages", 0) - stats.get("Pages purgeable", 0)
            + stats.get("Pages wired down", 0)
            + stats.get("Pages occupied by compressor", 0)
        ) * page
        return used / GB, total / GB
    except Exception:
        return 0.0, total / GB


def get_disk() -> tuple[float, float]:
    """(free_gb, total_gb) of the data volume."""
    for mount in ("/System/Volumes/Data", "/"):
        try:
            usage = shutil.disk_usage(mount)
            return usage.free / GB, usage.total / GB
        except OSError:
            continue
    return 0.0, 0.0


def get_cpu_temp() -> float | None:
    # osx-cpu-temp prints 0.0 on Apple Silicon: remember that and stop spawning it every 5 s.
    if cache_fresh(TEMP_UNAVAILABLE_FLAG, TEMP_RETRY_TTL):
        return None
    for cmd in (["osx-cpu-temp"], ["istats", "cpu", "temp", "--value-only"]):
        if not shutil.which(cmd[0]):
            continue
        try:
            result = run(cmd, timeout=1.5)
        except Exception:
            continue
        if result.returncode != 0 or "error" in (result.stdout + result.stderr).lower():
            continue
        match = re.search(r"\d+(?:\.\d+)?", result.stdout)
        if match and 20.0 <= float(match.group()) <= 120.0:
            return float(match.group())
    write_cache(TEMP_UNAVAILABLE_FLAG, "")
    return None


Process = tuple[str, str, float, float, bool]  # name, pid, cpu %, rss MB, owned by me


def get_processes() -> list[Process]:
    """Snapshot of all processes, cached briefly to keep the menu snappy."""
    if cache_fresh(PROCESS_CACHE, PROCESS_CACHE_TTL):
        try:
            result = []
            for line in PROCESS_CACHE.read_text(encoding="utf-8").splitlines():
                n, p, c, m, o = line.split("\t")
                result.append((n, p, float(c), float(m), o == "1"))
            return result
        except (OSError, ValueError):
            pass

    me = os.getuid()
    own_pid = os.getpid()
    result: list[Process] = []
    try:
        out = run(["ps", "-Ao", "pid=,uid=,%cpu=,rss=,comm="]).stdout
    except Exception:
        return result
    for line in out.splitlines():
        parts = line.split(None, 4)
        if len(parts) < 5 or not parts[0].isdigit():
            continue
        pid, uid, cpu, rss, comm = parts
        name = Path(comm).name
        if int(pid) == own_pid or name in ("kernel_task", "ps"):
            continue
        try:
            result.append((name, pid, float(cpu.replace(",", ".")), int(rss) / 1024, uid == str(me)))
        except ValueError:
            continue
    write_cache(
        PROCESS_CACHE,
        "\n".join(f"{n}\t{p}\t{c}\t{m:.0f}\t{int(o)}" for n, p, c, m, o in result),
    )
    return result


def top(processes: list[Process], key: int, limit: int = 8) -> list[Process]:
    return sorted(processes, key=lambda proc: proc[key], reverse=True)[:limit]


def fmt_mb(mb: float) -> str:
    return f"{mb / 1024:.1f} GB" if mb >= 1024 else f"{mb:.0f} MB"


def last_cleanup_summary(log_path: Path | None) -> str | None:
    """'freed 5.4 GB' from the summary of a cleaner log."""
    if not log_path:
        return None
    try:
        match = re.search(r"Freed: (\d+) MB", log_path.read_text(encoding="utf-8", errors="replace"))
    except OSError:
        return None
    return f"freed {fmt_mb(int(match.group(1)))}" if match else None


# --- keyboard cleaning mode ------------------------------------------------------


def get_keyboard_lock_state() -> tuple[bool, int | None]:
    """(locked, seconds_left) from keyboard-lock.py's PID file; None = until unlocked manually."""
    try:
        parts = PID_FILE.read_text(encoding="utf-8").split()
        pid = int(parts[0])
        deadline = float(parts[1]) if len(parts) > 1 else 0.0
        os.kill(pid, 0)
    except (OSError, ValueError, IndexError):
        return False, None
    if not deadline:
        return True, None
    return True, max(0, int(deadline - time.time()))


def is_accessibility_trusted() -> bool:
    """SwiftBar's Accessibility permission (inherited by this child process); cached."""
    if cache_fresh(AX_CACHE, AX_CACHE_TTL):
        try:
            return AX_CACHE.read_text(encoding="utf-8") == "1"
        except OSError:
            pass
    try:
        ax = ctypes.CDLL("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices")
        ax.AXIsProcessTrusted.restype = ctypes.c_bool
        trusted = bool(ax.AXIsProcessTrusted())
    except OSError:
        trusted = True  # unknown: do not nag
    write_cache(AX_CACHE, "1" if trusted else "0")
    return trusted


def fmt_countdown(seconds: int) -> str:
    return f"{seconds // 60}:{seconds % 60:02d}"


# --- misc --------------------------------------------------------------------------


def handle_kill(pid_arg: str) -> None:
    if not pid_arg.isdigit():
        sys.exit(1)
    pid = int(pid_arg)
    try:
        os.kill(pid, signal.SIGTERM)  # let the app shut down cleanly first
        for _ in range(15):
            time.sleep(0.1)
            os.kill(pid, 0)
        os.kill(pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    except PermissionError:
        sys.exit(1)
    PROCESS_CACHE.unlink(missing_ok=True)
    sys.exit(0)


def format_age(seconds: float) -> str:
    minutes = int(seconds // 60)
    if minutes < 60:
        return f"{max(minutes, 1)} min"
    if minutes < 48 * 60:
        return f"{minutes // 60} h"
    return f"{minutes // 1440} days"


def format_log_time(mtime: float) -> str:
    dt = datetime.datetime.fromtimestamp(mtime)
    days = (datetime.date.today() - dt.date()).days
    if days == 0:
        return dt.strftime("today %H:%M")
    if days == 1:
        return dt.strftime("yesterday %H:%M")
    return dt.strftime("%d.%m.%Y")


def latest(paths: list[Path]) -> tuple[Path | None, float | None]:
    best, best_mtime = None, None
    for path in paths:
        try:
            mtime = path.stat().st_mtime
        except OSError:
            continue
        if best_mtime is None or mtime > best_mtime:
            best, best_mtime = path, mtime
    return best, best_mtime


def resolve_scripts_dir(plugin_dir: Path) -> Path:
    for candidate in (plugin_dir.parent, HOME / ".scripts" / "fuck-cleanmymac", HOME / ".scripts"):
        if (candidate / "cleaner.sh").is_file():
            return candidate
    return HOME / ".scripts"


def first_existing(*paths: Path) -> Path | None:
    for path in paths:
        if path.is_file():
            return path
    return None


def fmt_gb(value: float) -> str:
    return f"{value / 1024:.1f} TB" if value >= 1024 else f"{value:.0f} GB"


# --- render --------------------------------------------------------------------


def print_process_menu(title: str, processes: list[Process], script_path: Path, by_memory: bool) -> None:
    print(title)
    print("--Click a process to quit it (SIGTERM, then SIGKILL after 1.5 s) | color=gray size=11")
    for name, pid, cpu_pct, rss_mb, mine in processes:
        value = fmt_mb(rss_mb) if by_memory else f"{cpu_pct:.0f}%"
        label = escape_title(f"{value:>7}  {name}")
        if mine:
            print(
                f"--{label} | font=Menlo size=12 bash={quote(script_path)} "
                f"param1=kill param2={pid} terminal=false refresh=true tooltip=PID {pid}"
            )
        else:
            print(f"--{label} | font=Menlo size=12 color=gray tooltip=System process, PID {pid}")


def main() -> None:
    if len(sys.argv) > 2 and sys.argv[1] == "kill":
        handle_kill(sys.argv[2])

    scripts_dir = resolve_scripts_dir(PLUGIN_DIR)
    lock_script = first_existing(
        scripts_dir / "swiftbar" / "keyboard-lock.py",
        PLUGIN_DIR / "keyboard-lock.py",
        HOME / ".scripts" / "fuck-cleanmymac" / "swiftbar" / "keyboard-lock.py",
    )
    keyboard_locked, lock_left = get_keyboard_lock_state()

    cpu = get_cpu_usage()
    used_gb, total_gb = get_memory()
    free_disk, _ = get_disk()
    temp = get_cpu_temp()

    parts: list[str] = []
    if keyboard_locked:
        parts.append("⌨️🔒" + (f" {fmt_countdown(lock_left)}" if lock_left is not None else ""))
    parts.append(f"{cpu:.0f}%")
    if temp is not None:
        parts.append(f"{temp:.0f}°")
    parts.append(f"{used_gb:.1f}/{total_gb:.0f} GB")
    parts.append(fmt_gb(free_disk))
    print(" • ".join(parts) + " | size=11")
    print("---")

    # While locked the mouse is the only way out, so the unlock action goes first.
    if keyboard_locked and lock_script:
        auto = f" — auto in {fmt_countdown(lock_left)}" if lock_left is not None else ""
        print(
            f"🔓 Unlock Keyboard{auto} | bash={quote(lock_script)} "
            "param1=unlock terminal=false refresh=true color=orange"
        )
        print("or press ⌘⌃⌥K on the keyboard | color=gray size=11")
        print("---")

    cleaner = scripts_dir / "cleaner.sh"
    cleaner_log, cleaner_mtime = latest(list(LOG_DIR.glob("cleaner_*.log")) if LOG_DIR.is_dir() else [])
    print("🧹 Clean Up")
    print(f"--Clean Now | bash={quote(cleaner)} terminal=true")
    print(f"--Scan — sizes and paths, deletes nothing | bash={quote(cleaner)} param1=--scan terminal=true")
    print(f"--Create Cleanup Plan… | bash={quote(cleaner)} param1=--plan terminal=true refresh=true")
    if CLEANUP_PLAN.is_file():
        age = format_age(time.time() - CLEANUP_PLAN.stat().st_mtime)
        print(f"--Review Plan ({age} old) | bash=/usr/bin/open param1=-t param2={quote(CLEANUP_PLAN)} terminal=false")
        print(f"--Apply Plan | bash={quote(cleaner)} param1=--apply terminal=true refresh=true")
    print("-----")
    if cleaner_log and cleaner_mtime is not None:
        freed = last_cleanup_summary(cleaner_log)
        summary = f"Last run {format_log_time(cleaner_mtime)}" + (f" • {freed}" if freed else "")
        print(f"--{summary} | color=gray size=11")
        print(f"--Open Last Report | bash=/usr/bin/open param1={quote(cleaner_log)} terminal=false")
    else:
        print("--Never run yet | color=gray size=11")
    config_file = HOME / ".config" / "fuck-cleanmymac" / "cleaner.conf"
    if config_file.is_file():
        print(f"--Settings… (what to clean) | bash=/usr/bin/open param1=-t param2={quote(config_file)} terminal=false")

    print(f"🚀 Update Apps & Packages | bash={quote(scripts_dir / 'update.sh')} terminal=true")
    print(f"🩺 Health Report | bash={quote(scripts_dir / 'health.sh')} terminal=true")
    print("---")

    print('💽 Disk Utility | bash=/usr/bin/open param1=-a param2="Disk Utility" terminal=false')
    if lock_script and not keyboard_locked:
        print("⌨️ Keyboard Cleaning Mode")
        print("--Blocks all keys so you can wipe the keyboard | color=gray size=11")
        print("--Mouse and trackpad keep working, the screen stays on | color=gray size=11")
        print("--Unlock from this menu or with ⌘⌃⌥K | color=gray size=11")
        print("-----")
        for seconds, label in LOCK_DURATIONS:
            print(
                f"--🔒 {label} | bash={quote(lock_script)} param1=lock param2={seconds} "
                "terminal=false refresh=true"
            )
        if not is_accessibility_trusted():
            print("-----")
            print("--⚠️ SwiftBar needs Accessibility permission | color=orange")
            print(f"--Open Privacy Settings… | bash=/usr/bin/open param1={quote(ACCESSIBILITY_URL)} terminal=false")
    elif not lock_script:
        print("⌨️ Keyboard Cleaning Mode (keyboard-lock.py not found) | color=gray")
    print("---")

    processes = get_processes()
    if processes:
        script_path = Path(sys.argv[0]).resolve()
        print_process_menu("⚔️ Top CPU", top(processes, 2), script_path, by_memory=False)
        print_process_menu("🧠 Top Memory", top(processes, 3), script_path, by_memory=True)

    print("🛠 System Tools")
    print('--Activity Monitor | bash=/usr/bin/open param1=-a param2="Activity Monitor" terminal=false')
    print(
        "--Storage Settings | bash=/usr/bin/open "
        'param1="x-apple.systempreferences:com.apple.settings.Storage" terminal=false'
    )
    print("---")

    installer = first_existing(
        scripts_dir / "scripts" / "install.sh",
        HOME / ".scripts" / "fuck-cleanmymac" / "scripts" / "install.sh",
    )
    if installer:
        print(
            f"🧩 Update fuck-cleanmymac | bash={quote(installer)} param1=--skip-deps "
            "param2=--skip-cron param3=--skip-swiftbar terminal=true refresh=true"
        )
    doctor = scripts_dir / "doctor.sh"
    if doctor.is_file():
        print(f"🩹 Check Setup (doctor) | bash={quote(doctor)} param1=--online terminal=true")

    print("📋 Logs")
    for label, log_path, mtime in (
        ("Cleanup", cleaner_log, cleaner_mtime),
        ("Update", *latest([LOG_DIR / "update.log"])),
        ("Health", *latest([LOG_DIR / "health.log"])),
    ):
        if log_path and mtime is not None:
            print(
                f"--{label} — {format_log_time(mtime)} | bash=/usr/bin/open "
                f"param1={quote(log_path)} terminal=false"
            )
        else:
            print(f"--{label} — no runs yet | color=gray")
    if LOG_DIR.is_dir():
        print("-----")
        print(f"--Open Logs Folder | bash=/usr/bin/open param1={quote(LOG_DIR)} terminal=false")

    print("---")
    version_file = first_existing(scripts_dir / "VERSION", HOME / ".scripts" / "fuck-cleanmymac" / "VERSION")
    version = version_file.read_text(encoding="utf-8").strip() if version_file else "unknown"
    print(f"fuck cleanmymac v{version} | color=gray size=11")


if __name__ == "__main__":
    main()
