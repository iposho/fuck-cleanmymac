# 📊 SwiftBar Plugin

Real-time macOS system monitor for your menu bar, with one-click access to the fuck-cleanmymac tools.

## Menu bar

`23% • 11.4/16 GB • 37 GB` — CPU load, RAM used / total, free disk space (CPU temperature appears when a sensor is available).

While the keyboard is locked the line starts with `⌨️🔒` (plus a countdown for timed locks).

## Menu

| Item | What it does |
| --- | --- |
| 🧹 **Clean Up** | *Clean Now*; *Scan* (sizes, paths and reasons, deletes nothing); *Create Cleanup Plan…*, then *Review Plan* / *Apply Plan* once a plan exists. Shows when cleanup last ran and how much it freed, opens the last report and `cleaner.conf` |
| 🚀 **Update Apps & Packages** | Runs `update.sh` (Homebrew, App Store, npm/pnpm globals, macOS update check) |
| 🩺 **Health Report** | Runs `health.sh` (SSD, battery, memory, security) |
| 💽 **Disk Utility** | Opens Disk Utility |
| ⌨️ **Keyboard Cleaning Mode** | See below |
| ⚔️ **Top CPU** / 🧠 **Top Memory** | Heaviest processes. Click one of yours to quit it (SIGTERM, SIGKILL after 1.5 s). System processes are shown in grey and cannot be killed from here |
| 🛠 **System Tools** | Activity Monitor, Storage settings |
| 🧩 **Update fuck-cleanmymac** | Updates the toolkit itself (`install.sh --skip-deps --skip-cron --skip-swiftbar`) |
| 🩹 **Check Setup (doctor)** | Runs `doctor.sh --online`: dependencies, installation, config, permissions, plugin, schedule |
| 📋 **Logs** | Latest cleanup / update / health logs, logs folder |

## ⌨️ Keyboard Cleaning Mode

Want to wipe the keyboard without typing garbage into some window? Pick **Lock for 1 minute**, **Lock for 5 minutes** or **Lock until I unlock it**.

- Every key is ignored, including media and brightness keys. Mouse and trackpad keep working, the screen stays on.
- The menu bar shows `⌨️🔒` (with a countdown for timed locks); the top menu item becomes **🔓 Unlock Keyboard**.
- Unlock from the menu or with **⌘⌃⌥K**; timed locks also end by themselves.
- The power button / Touch ID cannot be blocked by macOS — avoid pressing it.

**Permission:** SwiftBar needs *System Settings → Privacy & Security → Accessibility*. If it is missing the submenu shows a warning with an *Open Privacy Settings…* shortcut, and the first lock attempt shows the macOS permission prompt.

From a terminal: `swiftbar/keyboard-lock.py lock 60` (`lock 0` = until unlocked), `unlock`, `status` — the terminal app then needs the Accessibility permission.

## Installation

### Automatic (via installer)
[scripts/install.sh](../scripts/install.sh) links the plugin into your SwiftBar plugin folder when SwiftBar is installed. The link points to the installed repository, so plugin updates arrive with *Update fuck-cleanmymac*. Old copies of the plugin and of `keyboard-lock.py` are removed from the plugin folder.

### Manual
```bash
PLUGINS="$HOME/Library/Application Support/SwiftBar/Plugins"
mkdir -p "$PLUGINS"
ln -sf ~/.scripts/fuck-cleanmymac/swiftbar/system-monitor.5s.py "$PLUGINS/"
```
Then SwiftBar → *Refresh All*.

> **Important:** only `system-monitor.5s.py` belongs in the plugin folder. Do not copy `keyboard-lock.py` or this README there — SwiftBar runs every file in that folder as a plugin. If you point SwiftBar at the repo's `swiftbar/` folder for development, keep `swiftbar/.swiftbarignore` in place.

## Troubleshooting

- **Nothing in the menu bar** — check that the plugin is not disabled in SwiftBar (right-click → Plugins). Older installs kept the plugin inside a `system-monitor.5s.py/` folder that SwiftBar may have disabled; re-running the installer replaces it with a symlink.
- **Keyboard lock does nothing** — grant SwiftBar the Accessibility permission, then try again.
- **Anything else** — *Check Setup (doctor)* in the menu, or `doctor.sh` in a terminal.

## Configuration

The plugin refreshes every **5 seconds** (the `.5s` in the filename); rename it (e.g. `system-monitor.10s.py`) to change the interval. A refresh takes ~40 ms: CPU and memory are read from the kernel directly, the process list is cached for 15 s.

---

**Made with ❤️ for SwiftBar users.**
