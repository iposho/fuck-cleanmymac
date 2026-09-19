#!/usr/bin/env python3
"""Keyboard cleaning mode: block every key for a short time so the keyboard can be wiped.

Mouse and trackpad keep working, the display is kept awake.
Unlock any time from the SwiftBar menu or with ⌘⌃⌥K; timed locks also end by themselves.

Needs Accessibility permission for the app that launches it (SwiftBar or your terminal):
System Settings → Privacy & Security → Accessibility.

Usage: keyboard-lock.py [lock [SECONDS] | unlock | toggle [SECONDS] | status | check]
       SECONDS=0 locks until you unlock it manually.
"""

from __future__ import annotations

import ctypes
import ctypes.util
import os
import select
import signal
import subprocess
import sys
import time
from pathlib import Path

CONFIG_DIR = Path.home() / ".config" / "fuck-cleanmymac"
PID_FILE = CONFIG_DIR / "keyboard-lock.pid"
SCRIPT_MARKER = "keyboard-lock"

DEFAULT_SECONDS = 60
MAX_SECONDS = 3600
START_TIMEOUT = 5.0
ACCESSIBILITY_URL = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
SWIFTBAR_REFRESH_URL = "swiftbar://refreshplugin?name=system-monitor"

kCGHIDEventTap = 0
kCGSessionEventTap = 1
kCGHeadInsertEventTap = 0
kCGEventTapOptionDefault = 0
kCGEventKeyDown = 10
kCGEventKeyUp = 11
kCGEventFlagsChanged = 12
kCGEventSystemDefined = 14  # media / brightness / volume keys
kCGEventTapDisabledByTimeout = 0xFFFFFFFE
kCGEventTapDisabledByUserInput = 0xFFFFFFFF
kCGKeyboardEventKeycode = 9

CMD_MASK = 0x100000
CTRL_MASK = 0x40000
OPT_MASK = 0x80000
UNLOCK_MODS = CMD_MASK | CTRL_MASK | OPT_MASK
UNLOCK_KEYCODE = 40  # K


# --- helpers -----------------------------------------------------------------


def _escape_as(value: str) -> str:
    return value.replace("\\", "\\\\").replace('"', '\\"')


def notify(message: str, title: str = "Keyboard cleaning mode") -> None:
    script = f'display notification "{_escape_as(message)}" with title "{_escape_as(title)}"'
    try:
        subprocess.run(["osascript", "-e", script], capture_output=True, timeout=3, check=False)
    except Exception:
        pass


def open_url(url: str) -> None:
    try:
        subprocess.run(["/usr/bin/open", "-g", url], capture_output=True, timeout=3, check=False)
    except Exception:
        pass


def _pid_is_lock_daemon(pid: int) -> bool:
    """Alive and really ours (guards against PID reuse)."""
    try:
        os.kill(pid, 0)
    except OSError:
        return False
    try:
        out = subprocess.run(
            ["ps", "-p", str(pid), "-o", "command="],
            capture_output=True, text=True, timeout=2, check=False,
        ).stdout
    except Exception:
        return True
    return SCRIPT_MARKER in out


def read_state() -> tuple[int, float] | None:
    """Return (pid, deadline_epoch) of the running lock, or None. Removes stale PID files."""
    try:
        parts = PID_FILE.read_text(encoding="utf-8").split()
        pid = int(parts[0])
        deadline = float(parts[1]) if len(parts) > 1 else 0.0
    except (OSError, ValueError, IndexError):
        if PID_FILE.exists():
            PID_FILE.unlink(missing_ok=True)
        return None
    if not _pid_is_lock_daemon(pid):
        PID_FILE.unlink(missing_ok=True)
        return None
    return pid, deadline


def clamp_seconds(raw: str | None) -> int:
    """Lock duration in seconds; 0 means "until unlocked manually"."""
    try:
        value = int(raw) if raw else DEFAULT_SECONDS
    except ValueError:
        value = DEFAULT_SECONDS
    if value <= 0:
        return 0
    return max(5, min(value, MAX_SECONDS))


def describe(seconds: int) -> str:
    if seconds == 0:
        return "until you unlock it"
    if seconds % 60 == 0:
        minutes = seconds // 60
        return f"for {minutes} minute{'s' if minutes != 1 else ''}"
    return f"for {seconds} seconds"


# --- Accessibility -------------------------------------------------------------


def ax_trusted(prompt: bool = False) -> bool:
    """AXIsProcessTrusted[WithOptions]; with prompt=True macOS offers to open Settings."""
    try:
        ax = ctypes.CDLL(ctypes.util.find_library("ApplicationServices"))
        if not prompt:
            ax.AXIsProcessTrusted.restype = ctypes.c_bool
            return bool(ax.AXIsProcessTrusted())

        cf = ctypes.CDLL(ctypes.util.find_library("CoreFoundation"))
        cf.CFDictionaryCreate.restype = ctypes.c_void_p
        cf.CFDictionaryCreate.argtypes = [
            ctypes.c_void_p,
            ctypes.POINTER(ctypes.c_void_p),
            ctypes.POINTER(ctypes.c_void_p),
            ctypes.c_long,
            ctypes.c_void_p,
            ctypes.c_void_p,
        ]
        cf.CFRelease.argtypes = [ctypes.c_void_p]
        ax.AXIsProcessTrustedWithOptions.restype = ctypes.c_bool
        ax.AXIsProcessTrustedWithOptions.argtypes = [ctypes.c_void_p]

        keys = (ctypes.c_void_p * 1)(ctypes.c_void_p.in_dll(ax, "kAXTrustedCheckOptionPrompt").value)
        values = (ctypes.c_void_p * 1)(ctypes.c_void_p.in_dll(cf, "kCFBooleanTrue").value)
        options = cf.CFDictionaryCreate(
            None,
            keys,
            values,
            1,
            ctypes.addressof(ctypes.c_char.in_dll(cf, "kCFTypeDictionaryKeyCallBacks")),
            ctypes.addressof(ctypes.c_char.in_dll(cf, "kCFTypeDictionaryValueCallBacks")),
        )
        try:
            return bool(ax.AXIsProcessTrustedWithOptions(options))
        finally:
            if options:
                cf.CFRelease(options)
    except Exception:
        return False


# --- lock daemon (separate exec'd process: CoreFoundation is not fork-safe) ------------


def run_daemon(seconds: int) -> int:
    cg = ctypes.CDLL(ctypes.util.find_library("CoreGraphics"))
    cf = ctypes.CDLL(ctypes.util.find_library("CoreFoundation"))

    callback_type = ctypes.CFUNCTYPE(
        ctypes.c_void_p, ctypes.c_void_p, ctypes.c_uint32, ctypes.c_void_p, ctypes.c_void_p
    )

    cg.CGEventTapCreate.restype = ctypes.c_void_p
    cg.CGEventTapCreate.argtypes = [
        ctypes.c_uint32, ctypes.c_uint32, ctypes.c_uint32, ctypes.c_uint64,
        callback_type, ctypes.c_void_p,
    ]
    cg.CGEventTapEnable.restype = None
    cg.CGEventTapEnable.argtypes = [ctypes.c_void_p, ctypes.c_bool]
    cg.CGEventGetFlags.restype = ctypes.c_uint64
    cg.CGEventGetFlags.argtypes = [ctypes.c_void_p]
    cg.CGEventGetIntegerValueField.restype = ctypes.c_int64
    cg.CGEventGetIntegerValueField.argtypes = [ctypes.c_void_p, ctypes.c_uint32]
    cf.CFMachPortCreateRunLoopSource.restype = ctypes.c_void_p
    cf.CFMachPortCreateRunLoopSource.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_long]
    cf.CFRunLoopGetCurrent.restype = ctypes.c_void_p
    cf.CFRunLoopAddSource.restype = None
    cf.CFRunLoopAddSource.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p]
    cf.CFRunLoopRunInMode.restype = ctypes.c_int32
    cf.CFRunLoopRunInMode.argtypes = [ctypes.c_void_p, ctypes.c_double, ctypes.c_bool]
    cf.CFRunLoopStop.argtypes = [ctypes.c_void_p]
    default_mode = ctypes.c_void_p.in_dll(cf, "kCFRunLoopDefaultMode")

    state: dict[str, object] = {"stop": None, "tap": None}

    def request_stop(reason: str) -> None:
        if state["stop"] is None:
            state["stop"] = reason

    def tap_callback(_proxy, event_type, event, _refcon):
        if event_type in (kCGEventTapDisabledByTimeout, kCGEventTapDisabledByUserInput):
            # macOS disables slow taps; turn ours back on instead of silently unlocking.
            if state["tap"]:
                cg.CGEventTapEnable(state["tap"], True)
            return event
        if event_type == kCGEventKeyDown:
            mods = cg.CGEventGetFlags(event) & UNLOCK_MODS
            keycode = cg.CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode)
            if mods == UNLOCK_MODS and keycode == UNLOCK_KEYCODE:
                request_stop("hotkey")
                cf.CFRunLoopStop(cf.CFRunLoopGetCurrent())
        return None  # swallow every keyboard event

    callback = callback_type(tap_callback)
    mask = (
        (1 << kCGEventKeyDown)
        | (1 << kCGEventKeyUp)
        | (1 << kCGEventFlagsChanged)
        | (1 << kCGEventSystemDefined)
    )

    tap = None
    for location in (kCGHIDEventTap, kCGSessionEventTap):
        tap = cg.CGEventTapCreate(location, kCGHeadInsertEventTap, kCGEventTapOptionDefault, mask, callback, None)
        if tap:
            break

    def report(line: str) -> None:
        try:
            sys.stdout.write(line + "\n")
            sys.stdout.flush()
        except OSError:
            pass

    if not tap:
        report("error:no-permission")
        return 2

    state["tap"] = tap
    source = cf.CFMachPortCreateRunLoopSource(None, tap, 0)
    if not source:
        report("error:runloop")
        return 3
    cf.CFRunLoopAddSource(cf.CFRunLoopGetCurrent(), source, default_mode)
    cg.CGEventTapEnable(tap, True)

    deadline = time.time() + seconds if seconds else 0.0  # 0 = manual unlock only
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    PID_FILE.write_text(f"{os.getpid()} {deadline:.0f}", encoding="utf-8")

    for sig in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
        signal.signal(sig, lambda *_: request_stop("signal"))

    # Keep the display on while the keyboard is being wiped.
    caffeinate = None
    try:
        caffeinate = subprocess.Popen(
            ["caffeinate", "-d", "-w", str(os.getpid())],
            stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
    except OSError:
        pass

    report("ok")
    devnull = os.open(os.devnull, os.O_RDWR)
    os.dup2(devnull, 1)
    os.dup2(devnull, 2)

    try:
        # Short slices so Python signal handlers (unlock from the menu) run promptly.
        while state["stop"] is None:
            if deadline and time.time() >= deadline:
                request_stop("timeout")
                break
            cf.CFRunLoopRunInMode(default_mode, 0.25, False)
    finally:
        cg.CGEventTapEnable(tap, False)
        try:
            if PID_FILE.read_text(encoding="utf-8").split()[0] == str(os.getpid()):
                PID_FILE.unlink(missing_ok=True)
        except (OSError, IndexError):
            pass
        if caffeinate:
            caffeinate.terminate()

    if state["stop"] == "timeout":
        notify("Time is up — keyboard unlocked")
    elif state["stop"] == "hotkey":
        notify("Keyboard unlocked with ⌘⌃⌥K")
    open_url(SWIFTBAR_REFRESH_URL)
    return 0


# --- commands ----------------------------------------------------------------------


def lock(seconds: int) -> int:
    if read_state():
        notify("Keyboard is already locked")
        return 0

    proc = subprocess.Popen(
        [sys.executable, str(Path(__file__).resolve()), "_daemon", str(seconds)],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
        close_fds=True,
    )
    answer = ""
    assert proc.stdout is not None
    ready, _, _ = select.select([proc.stdout], [], [], START_TIMEOUT)
    if ready:
        answer = proc.stdout.readline().decode("utf-8", "replace").strip()
    proc.stdout.close()

    if answer == "ok":
        notify(f"Keyboard locked {describe(seconds)}. Unlock: SwiftBar menu or ⌘⌃⌥K")
        return 0

    if proc.poll() is None:
        proc.kill()
    if answer == "error:no-permission" or not ax_trusted():
        # Registers the launching app in the Accessibility list and shows the system prompt.
        ax_trusted(prompt=True)
        open_url(ACCESSIBILITY_URL)
        notify(
            "Allow SwiftBar in Privacy & Security → Accessibility, then try again",
            title="Keyboard lock needs permission",
        )
        print("Keyboard lock needs Accessibility permission for the launching app.", file=sys.stderr)
        return 1

    notify(f"Could not lock the keyboard ({answer or 'no response'})", title="Keyboard lock failed")
    print(f"Keyboard lock failed: {answer or 'no response'}", file=sys.stderr)
    return 1


def unlock() -> int:
    state = read_state()
    if not state:
        return 0
    pid, _ = state
    try:
        os.kill(pid, signal.SIGTERM)
    except OSError:
        pass
    for _ in range(20):
        if not _pid_is_lock_daemon(pid):
            break
        time.sleep(0.1)
    PID_FILE.unlink(missing_ok=True)
    notify("Keyboard unlocked")
    return 0


def status() -> int:
    state = read_state()
    if state:
        if state[1]:
            print(f"locked {max(0, int(state[1] - time.time()))}")
        else:
            print("locked manual")
    else:
        print("unlocked")
    return 0


def main() -> int:
    args = sys.argv[1:]
    command = args[0] if args else "status"
    arg = args[1] if len(args) > 1 else None

    if command == "_daemon":
        return run_daemon(clamp_seconds(arg))
    if command == "lock":
        return lock(clamp_seconds(arg))
    if command == "unlock":
        return unlock()
    if command == "toggle":
        return unlock() if read_state() else lock(clamp_seconds(arg))
    if command == "status":
        return status()
    if command == "check":
        print("trusted" if ax_trusted() else "untrusted")
        return 0

    print(__doc__.strip(), file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
