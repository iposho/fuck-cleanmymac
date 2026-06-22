#!/usr/bin/env python3
"""Temporarily block keyboard input for cleaning. Mouse and display stay active."""

from __future__ import annotations

import ctypes
import ctypes.util
import os
import signal
import subprocess
import sys
import time
from pathlib import Path

CONFIG_DIR = Path.home() / ".config" / "fuck-cleanmymac"
PID_FILE = CONFIG_DIR / "keyboard-lock.pid"

kCGHIDEventTap = 0
kCGHeadInsertEventTap = 0
kCGEventTapOptionDefault = 0
kCGEventKeyDown = 10
kCGEventKeyUp = 11
kCGEventFlagsChanged = 12
kCGEventSystemDefined = 14
kCGKeyboardEventKeycode = 9

CMD_MASK = 0x100000
CTRL_MASK = 0x40000
OPT_MASK = 0x80000
UNLOCK_KEYCODE = 40  # K

cg = ctypes.CDLL(ctypes.util.find_library("CoreGraphics"))
cf = ctypes.CDLL(ctypes.util.find_library("CoreFoundation"))

CGEventTapCallBack = ctypes.CFUNCTYPE(
    ctypes.c_void_p,
    ctypes.c_void_p,
    ctypes.c_int,
    ctypes.c_void_p,
    ctypes.c_void_p,
)


def notify(title: str, message: str) -> None:
    try:
        subprocess.run(
            [
                "osascript",
                "-e",
                f'display notification "{message}" with title "{title}"',
            ],
            check=False,
            capture_output=True,
        )
    except Exception:
        pass


def is_locked() -> bool:
    if not PID_FILE.exists():
        return False
    try:
        pid = int(PID_FILE.read_text(encoding="utf-8").strip())
        os.kill(pid, 0)
        return True
    except (OSError, ValueError):
        PID_FILE.unlink(missing_ok=True)
        return False


def write_pid() -> None:
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    PID_FILE.write_text(str(os.getpid()), encoding="utf-8")


def clear_pid() -> None:
    PID_FILE.unlink(missing_ok=True)


def unlock() -> int:
    if not PID_FILE.exists():
        return 0
    try:
        pid = int(PID_FILE.read_text(encoding="utf-8").strip())
        os.kill(pid, signal.SIGTERM)
    except (OSError, ValueError):
        pass
    clear_pid()
    notify("Keyboard", "Keyboard unlocked")
    return 0


def lock() -> int:
    if is_locked():
        notify("Keyboard", "Keyboard is already locked")
        return 0

    pid = os.fork()
    if pid > 0:
        time.sleep(0.15)
        if is_locked():
            notify(
                "Keyboard",
                "Keyboard locked. Unlock via SwiftBar or press ⌘⌃⌥K",
            )
            return 0
        print(
            "Failed to lock keyboard. Grant Accessibility access to SwiftBar or Terminal.",
            file=sys.stderr,
        )
        return 1

    os.setsid()
    write_pid()

    locked = {"active": True}

    def shutdown(*_args):
        locked["active"] = False
        clear_pid()
        sys.exit(0)

    signal.signal(signal.SIGTERM, shutdown)
    signal.signal(signal.SIGINT, shutdown)

    def tap_callback(proxy, event_type, event, _refcon):
        if not locked["active"]:
            return event

        if event_type == kCGEventKeyDown:
            flags = cg.CGEventGetFlags(event)
            keycode = cg.CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode)
            mods = flags & (CMD_MASK | CTRL_MASK | OPT_MASK)
            if mods == (CMD_MASK | CTRL_MASK | OPT_MASK) and keycode == UNLOCK_KEYCODE:
                shutdown()
                return event

        return None

    callback = CGEventTapCallBack(tap_callback)
    mask = (
        (1 << kCGEventKeyDown)
        | (1 << kCGEventKeyUp)
        | (1 << kCGEventFlagsChanged)
        | (1 << kCGEventSystemDefined)
    )

    tap = cg.CGEventTapCreate(
        kCGHIDEventTap,
        kCGHeadInsertEventTap,
        kCGEventTapOptionDefault,
        mask,
        callback,
        None,
    )
    if not tap:
        clear_pid()
        sys.exit(1)

    run_loop_source = cg.CFMachPortCreateRunLoopSource(None, tap, 0)
    cg.CGEventTapEnable(tap, True)

    cf.CFRunLoopAddSource(
        cf.CFRunLoopGetCurrent(),
        run_loop_source,
        cf.kCFRunLoopDefaultMode,
    )
    cf.CFRunLoopRun()
    clear_pid()
    return 0


def main() -> int:
    command = sys.argv[1] if len(sys.argv) > 1 else "status"

    if command == "status":
        print("locked" if is_locked() else "unlocked")
        return 0
    if command == "lock":
        return lock()
    if command == "unlock":
        return unlock()
    if command == "toggle":
        return unlock() if is_locked() else lock()

    print(f"Usage: {sys.argv[0]} [lock|unlock|toggle|status]", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
